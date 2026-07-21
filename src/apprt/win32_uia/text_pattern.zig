//! `ITextProvider` / `ITextRangeProvider` for the terminal document.
//!
//! The pattern is created per `GetPatternProvider` call and owns an
//! immutable UTF-16 snapshot of the active pane's screen + scrollback.
//! UIA text ranges are snapshots by design — clients re-fetch after
//! TextChanged — so an immutable document is contract-correct; we do
//! not (yet) raise TextChanged, which means live-follow modes re-read
//! on their own cadence rather than streaming.
//!
//! First-slice degradations, all within the UIA contract:
//!   * Format / Paragraph units behave as Line (Word is real:
//!     ink runs with trailing blanks).
//!   * Bounding rects and point hit-testing are line/column-granular
//!     with column ≈ UTF-16 unit (wide glyphs approximate).
//!   * Selection is reported as unsupported (`SupportedTextSelection_None`).
//!
//! Threading: UIA invokes ServerSideProvider methods on RPC threads,
//! so every allocation in this file uses `std.heap.smp_allocator` —
//! never an App-owned allocator.

const std = @import("std");
const com = @import("com.zig");

const pattern_alloc = std.heap.smp_allocator;

fn iidEqual(a: *const com.GUID, b: *const com.GUID) bool {
    return std.mem.eql(u8, std.mem.asBytes(a), std.mem.asBytes(b));
}

pub const OffsetRange = struct {
    start: usize,
    end: usize,
};

/// Host snapshot for pattern creation: the full document (UTF-8), the
/// viewport's byte range within it, and the viewport's screen geometry
/// (all zeros when unknown — bounding rects then come back empty).
/// `origin_*` is the top-left of the viewport's first text cell in
/// physical screen pixels; `cell_*` the glyph cell size in pixels.
pub const TextDoc = struct {
    utf8: []const u8,
    visible_start: usize,
    visible_end: usize,
    cell_w: f64 = 0,
    cell_h: f64 = 0,
    origin_x: f64 = 0,
    origin_y: f64 = 0,
    viewport_cols: usize = 0,
};

pub const LineRect = struct {
    left: f64,
    top: f64,
    width: f64,
    height: f64,
};

pub const MoveResult = struct {
    offset: usize,
    moved: i32,
};

/// UTF-16 offsets of line starts. Same semantics as text.zig's byte
/// map: empty text is one line at 0, interior blank lines are kept, a
/// trailing `\n` terminates the last line instead of starting a
/// phantom one.
pub fn buildLineStarts(alloc: std.mem.Allocator, doc: []const u16) ![]usize {
    var line_starts: std.ArrayList(usize) = .empty;
    defer line_starts.deinit(alloc);
    try line_starts.append(alloc, 0);
    for (doc, 0..) |unit, i| {
        if (unit == '\n' and i + 1 < doc.len) try line_starts.append(alloc, i + 1);
    }
    return try line_starts.toOwnedSlice(alloc);
}

/// UTF-16 length of the UTF-8 prefix `utf8[0..byte_offset]`, tolerant
/// of a mid-codepoint or out-of-range offset (clamps forward). Used to
/// map the host's viewport byte range into snapshot UTF-16 offsets.
pub fn utf16LenOfPrefix(utf8: []const u8, byte_offset: usize) usize {
    const end = @min(byte_offset, utf8.len);
    var i: usize = 0;
    var n: usize = 0;
    while (i < end) {
        const seq_len = std.unicode.utf8ByteSequenceLength(utf8[i]) catch {
            i += 1;
            n += 1;
            continue;
        };
        const cp_end = @min(i + seq_len, utf8.len);
        const cp = std.unicode.utf8Decode(utf8[i..cp_end]) catch {
            i += 1;
            n += 1;
            continue;
        };
        i += seq_len;
        n += if (cp <= 0xFFFF) 1 else 2;
    }
    return n;
}

/// Per-line screen rectangles for `[start, end)` clipped to the
/// viewport. Column ≈ UTF-16 unit offset within the line, so wide
/// glyphs make widths approximate; line breaks and empty segments
/// produce no rect. Geometry zeros (cell_w <= 0) → empty result.
pub fn boundingLineRects(
    alloc: std.mem.Allocator,
    doc: []const u16,
    line_starts: []const usize,
    visible_start: usize,
    visible_end: usize,
    start: usize,
    end: usize,
    geo: TextDoc,
) ![]LineRect {
    var rects: std.ArrayList(LineRect) = .empty;
    defer rects.deinit(alloc);

    const clip_start = @max(start, visible_start);
    const clip_end = @min(end, visible_end);
    if (geo.cell_w <= 0 or geo.cell_h <= 0 or clip_start >= clip_end)
        return try rects.toOwnedSlice(alloc);

    const first_visible_line = lineIndexForOffset(line_starts, visible_start);
    var line = lineIndexForOffset(line_starts, clip_start);
    while (line < line_starts.len and line_starts[line] < clip_end) : (line += 1) {
        const line_start = line_starts[line];
        const line_end = if (line + 1 < line_starts.len)
            line_starts[line + 1]
        else
            doc.len;
        // The newline unit occupies no cell.
        var content_end = line_end;
        if (content_end > line_start and doc[content_end - 1] == '\n')
            content_end -= 1;

        const seg_start = @max(clip_start, line_start);
        const seg_end = @min(clip_end, content_end);
        if (seg_end <= seg_start) continue;

        const col_start = @min(seg_start - line_start, geo.viewport_cols);
        const col_end = @min(seg_end - line_start, geo.viewport_cols);
        if (col_end <= col_start) continue;

        const row = line - first_visible_line;
        try rects.append(alloc, .{
            .left = geo.origin_x + @as(f64, @floatFromInt(col_start)) * geo.cell_w,
            .top = geo.origin_y + @as(f64, @floatFromInt(row)) * geo.cell_h,
            .width = @as(f64, @floatFromInt(col_end - col_start)) * geo.cell_w,
            .height = geo.cell_h,
        });
    }
    return try rects.toOwnedSlice(alloc);
}

/// Map a screen point to a document offset using the viewport
/// geometry: row/column arithmetic against the cell grid, clamped to
/// the visible range. Unknown geometry maps everything to offset 0.
pub fn offsetForPoint(
    doc: []const u16,
    line_starts: []const usize,
    visible_start: usize,
    visible_end: usize,
    geo: TextDoc,
    x: f64,
    y: f64,
) usize {
    if (geo.cell_w <= 0 or geo.cell_h <= 0) return 0;

    const row_f = @floor((y - geo.origin_y) / geo.cell_h);
    const col_f = @floor((x - geo.origin_x) / geo.cell_w);
    const row: usize = if (row_f < 0) 0 else @intFromFloat(row_f);
    const col: usize = if (col_f < 0) 0 else @intFromFloat(col_f);

    const first_visible_line = lineIndexForOffset(line_starts, visible_start);
    const line = @min(first_visible_line + row, line_starts.len - 1);
    const line_start = line_starts[line];
    const line_end = if (line + 1 < line_starts.len) line_starts[line + 1] else doc.len;
    var content_end = line_end;
    if (content_end > line_start and doc[content_end - 1] == '\n') content_end -= 1;

    const offset = @min(line_start + @min(col, geo.viewport_cols), content_end);
    return std.math.clamp(offset, visible_start, visible_end);
}

/// Word separators for TextUnit_Word: blanks and the line break. The
/// terminal has no richer segmentation to offer than runs of ink.
fn isWordSep(unit: u16) bool {
    return unit == ' ' or unit == '\t' or unit == '\n';
}

/// Start of the word containing `offset`. A word is a maximal run of
/// non-separators plus its TRAILING separators (the UIA convention),
/// so an offset inside blanks belongs to the word whose tail they are;
/// leading separators at document start form a degenerate word at 0.
pub fn wordStartAt(doc: []const u16, offset: usize) usize {
    var i = @min(offset, doc.len);
    if (i == doc.len) {
        if (i == 0) return 0;
        i -= 1; // the degenerate end position belongs to the last word
    }
    if (isWordSep(doc[i])) {
        // Inside a trailing-separator run: back to its first separator,
        // then over the ink run it terminates.
        while (i > 0 and isWordSep(doc[i - 1])) i -= 1;
        while (i > 0 and !isWordSep(doc[i - 1])) i -= 1;
        return i;
    }
    while (i > 0 and !isWordSep(doc[i - 1])) i -= 1;
    return i;
}

/// Start of the next word after the word containing `offset`
/// (equivalently: end of that word, trailing separators included).
pub fn wordEndAt(doc: []const u16, offset: usize) usize {
    var i = @min(offset, doc.len);
    // Forward over the ink run.
    while (i < doc.len and !isWordSep(doc[i])) i += 1;
    // Forward over the trailing separator run.
    while (i < doc.len and isWordSep(doc[i])) i += 1;
    return i;
}

/// Index of the line containing `offset` (last line whose start <= offset).
pub fn lineIndexForOffset(line_starts: []const usize, offset: usize) usize {
    var lo: usize = 0;
    var hi: usize = line_starts.len; // invariant: line_starts[lo] <= offset < line_starts[hi]
    while (hi - lo > 1) {
        const mid = lo + (hi - lo) / 2;
        if (line_starts[mid] <= offset) lo = mid else hi = mid;
    }
    return lo;
}

/// Expand `[start, end)` to enclosing `unit` boundaries.
pub fn expandRange(
    doc: []const u16,
    line_starts: []const usize,
    start: usize,
    unit: i32,
) OffsetRange {
    const doc_len = doc.len;
    switch (unit) {
        com.TextUnit_Character => {
            const s = @min(start, doc_len);
            return .{ .start = s, .end = @min(s + 1, doc_len) };
        },
        com.TextUnit_Word => {
            const s = @min(start, doc_len);
            return .{ .start = wordStartAt(doc, s), .end = wordEndAt(doc, s) };
        },
        com.TextUnit_Format,
        com.TextUnit_Paragraph,
        com.TextUnit_Line,
        => {
            const line = lineIndexForOffset(line_starts, @min(start, doc_len));
            const line_end = if (line + 1 < line_starts.len)
                line_starts[line + 1]
            else
                doc_len;
            return .{ .start = line_starts[line], .end = line_end };
        },
        else => return .{ .start = 0, .end = doc_len },
    }
}

/// Move a single endpoint by `count` units; reports how many units the
/// endpoint actually crossed (clamped at the document edges).
pub fn moveOffsetByUnit(
    doc: []const u16,
    line_starts: []const usize,
    offset: usize,
    unit: i32,
    count: i32,
) MoveResult {
    const doc_len = doc.len;
    const clamped_offset = @min(offset, doc_len);
    if (count == 0) return .{ .offset = clamped_offset, .moved = 0 };
    switch (unit) {
        com.TextUnit_Character => {
            const cur: i64 = @intCast(clamped_offset);
            const target_i64 = std.math.clamp(cur + count, 0, @as(i64, @intCast(doc_len)));
            return .{
                .offset = @intCast(target_i64),
                .moved = @intCast(target_i64 - cur),
            };
        },
        com.TextUnit_Word => {
            var pos = clamped_offset;
            var moved: i32 = 0;
            if (count > 0) {
                while (moved < count) {
                    const next = wordEndAt(doc, pos);
                    if (next == pos) break;
                    pos = next;
                    moved += 1;
                }
            } else {
                while (moved > count) {
                    const cur_start = wordStartAt(doc, pos);
                    // Standing exactly on a word start steps to the
                    // previous word; anywhere else snaps to this one.
                    const target = if (cur_start == pos)
                        (if (pos == 0) pos else wordStartAt(doc, pos - 1))
                    else
                        cur_start;
                    if (target == pos) break;
                    pos = target;
                    moved -= 1;
                }
            }
            return .{ .offset = pos, .moved = moved };
        },
        com.TextUnit_Format,
        com.TextUnit_Paragraph,
        com.TextUnit_Line,
        => {
            const cur: i64 = @intCast(lineIndexForOffset(line_starts, clamped_offset));
            const last: i64 = @intCast(line_starts.len - 1);
            const target = std.math.clamp(cur + count, 0, last);
            return .{
                .offset = line_starts[@intCast(target)],
                .moved = @intCast(target - cur),
            };
        },
        else => {
            if (count < 0) {
                return .{ .offset = 0, .moved = if (clamped_offset > 0) -1 else 0 };
            }
            return .{ .offset = doc_len, .moved = if (clamped_offset < doc_len) 1 else 0 };
        },
    }
}

/// Case-insensitive (ASCII) or exact search inside `doc[start..end)`.
pub fn findTextInDoc(
    doc: []const u16,
    start: usize,
    end: usize,
    needle: []const u16,
    backward: bool,
    ignore_case: bool,
) ?OffsetRange {
    if (needle.len == 0) return null;
    const hay_end = @min(end, doc.len);
    const hay_start = @min(start, hay_end);
    if (hay_end - hay_start < needle.len) return null;

    const last_candidate = hay_end - needle.len;
    var candidate = if (backward) last_candidate else hay_start;
    while (true) {
        var match = true;
        for (needle, 0..) |n, i| {
            if (!unitsEqual(doc[candidate + i], n, ignore_case)) {
                match = false;
                break;
            }
        }
        if (match) return .{ .start = candidate, .end = candidate + needle.len };
        if (backward) {
            if (candidate == hay_start) return null;
            candidate -= 1;
        } else {
            if (candidate == last_candidate) return null;
            candidate += 1;
        }
    }
}

fn unitsEqual(a: u16, b: u16, ignore_case: bool) bool {
    if (a == b) return true;
    if (!ignore_case) return false;
    return a < 128 and b < 128 and
        std.ascii.toLower(@intCast(a)) == std.ascii.toLower(@intCast(b));
}

// ── TextPattern (ITextProvider) ─────────────────────────────────────────

pub const TextPattern = struct {
    base: com.ITextProvider,
    refcount: std.atomic.Value(u32),
    /// Owned UTF-16 document snapshot.
    doc: []const u16,
    /// Owned UTF-16 line-start offsets.
    line_starts: []const usize,
    /// Viewport bounds within `doc`, UTF-16 units (start <= end).
    visible_start: usize,
    visible_end: usize,
    /// Viewport screen geometry as captured (utf8/visible fields unused).
    geo: TextDoc,
    /// The window element ranges report as enclosing. Holds a ref.
    root: *com.IRawElementProviderSimple,

    const vtbl: com.ITextProviderVtbl = .{
        .QueryInterface = TextPattern.QueryInterface,
        .AddRef = TextPattern.AddRef,
        .Release = TextPattern.Release,
        .GetSelection = TextPattern.GetSelection,
        .GetVisibleRanges = TextPattern.GetVisibleRanges,
        .RangeFromChild = TextPattern.RangeFromChild,
        .RangeFromPoint = TextPattern.RangeFromPoint,
        .get_DocumentRange = TextPattern.get_DocumentRange,
        .get_SupportedTextSelection = TextPattern.get_SupportedTextSelection,
    };

    /// Takes a host snapshot (utf8 not owned; copied) and the root
    /// element (AddRef'd for the pattern's lifetime).
    pub fn create(
        root_provider: *com.IRawElementProviderSimple,
        source: TextDoc,
    ) !*TextPattern {
        const doc = try std.unicode.utf8ToUtf16LeAlloc(pattern_alloc, source.utf8);
        errdefer pattern_alloc.free(doc);
        const line_starts = try buildLineStarts(pattern_alloc, doc);
        errdefer pattern_alloc.free(line_starts);

        const vis_start = @min(
            utf16LenOfPrefix(source.utf8, source.visible_start),
            doc.len,
        );
        const vis_end = @min(
            @max(utf16LenOfPrefix(source.utf8, source.visible_end), vis_start),
            doc.len,
        );

        const self = try pattern_alloc.create(TextPattern);
        self.* = .{
            .base = .{ .vtbl = &vtbl },
            .refcount = std.atomic.Value(u32).init(1),
            .doc = doc,
            .line_starts = line_starts,
            .visible_start = vis_start,
            .visible_end = vis_end,
            .geo = .{
                .utf8 = &.{},
                .visible_start = 0,
                .visible_end = 0,
                .cell_w = source.cell_w,
                .cell_h = source.cell_h,
                .origin_x = source.origin_x,
                .origin_y = source.origin_y,
                .viewport_cols = source.viewport_cols,
            },
            .root = root_provider,
        };
        _ = root_provider.vtbl.AddRef(root_provider);
        return self;
    }

    fn fromBase(p: *com.ITextProvider) *TextPattern {
        return @fieldParentPtr("base", p);
    }

    fn retain(self: *TextPattern) void {
        _ = self.refcount.fetchAdd(1, .monotonic);
    }

    /// Allocate a new range over `[start, end)`, refcount 1, holding a
    /// pattern ref. Ownership passes to the caller (usually straight to
    /// a COM out-param).
    fn newRange(self: *TextPattern, start: usize, end: usize) !*TextRange {
        const range = try pattern_alloc.create(TextRange);
        range.* = .{
            .base = .{ .vtbl = &TextRange.vtbl },
            .refcount = std.atomic.Value(u32).init(1),
            .pattern = self,
            .start = @min(start, self.doc.len),
            .end = @min(end, self.doc.len),
        };
        self.retain();
        return range;
    }

    /// Empty SAFEARRAY of the given VARTYPE, or null on failure.
    fn emptyArray(vt: u16) ?*com.SAFEARRAY {
        return com.SafeArrayCreateVector(vt, 0, 0);
    }

    // ── IUnknown ────────────────────────────────────────────────────

    fn QueryInterface(
        self_base: *com.ITextProvider,
        iid: *const com.GUID,
        out: *?*anyopaque,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = null;
        if (iidEqual(iid, &com.IID_IUnknown) or
            iidEqual(iid, &com.IID_ITextProvider))
        {
            out.* = @ptrCast(&self.base);
            self.retain();
            return com.S_OK;
        }
        return com.E_NOINTERFACE;
    }

    fn AddRef(self_base: *com.ITextProvider) callconv(.winapi) u32 {
        const self = fromBase(self_base);
        return self.refcount.fetchAdd(1, .monotonic) + 1;
    }

    fn Release(self_base: *com.ITextProvider) callconv(.winapi) u32 {
        const self = fromBase(self_base);
        const prev = self.refcount.fetchSub(1, .acq_rel);
        if (prev == 1) {
            _ = self.root.vtbl.Release(self.root);
            pattern_alloc.free(self.line_starts);
            pattern_alloc.free(self.doc);
            pattern_alloc.destroy(self);
            return 0;
        }
        return prev - 1;
    }

    // ── ITextProvider ───────────────────────────────────────────────

    fn GetSelection(
        _: *com.ITextProvider,
        out: *?*com.SAFEARRAY,
    ) callconv(.winapi) com.HRESULT {
        // SupportedTextSelection_None: report no selection ranges.
        out.* = emptyArray(com.VT_UNKNOWN) orelse return com.E_OUTOFMEMORY;
        return com.S_OK;
    }

    fn GetVisibleRanges(
        self_base: *com.ITextProvider,
        out: *?*com.SAFEARRAY,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = null;
        const array = com.SafeArrayCreateVector(com.VT_UNKNOWN, 0, 1) orelse
            return com.E_OUTOFMEMORY;
        const range = self.newRange(self.visible_start, self.visible_end) catch {
            _ = com.SafeArrayDestroy(array);
            return com.E_OUTOFMEMORY;
        };
        var index: i32 = 0;
        const hr = com.SafeArrayPutElement(array, &index, @ptrCast(&range.base));
        // PutElement AddRef'd on success; our local ref goes either way.
        _ = TextRange.Release(&range.base);
        if (hr != com.S_OK) {
            _ = com.SafeArrayDestroy(array);
            return hr;
        }
        out.* = array;
        return com.S_OK;
    }

    fn RangeFromChild(
        _: *com.ITextProvider,
        _: ?*com.IRawElementProviderSimple,
        out: *?*com.ITextRangeProvider,
    ) callconv(.winapi) com.HRESULT {
        // The document has no child text elements.
        out.* = null;
        return com.S_OK;
    }

    fn RangeFromPoint(
        self_base: *com.ITextProvider,
        point: com.UiaPoint,
        out: *?*com.ITextRangeProvider,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        const offset = offsetForPoint(
            self.doc,
            self.line_starts,
            self.visible_start,
            self.visible_end,
            self.geo,
            point.x,
            point.y,
        );
        const range = self.newRange(offset, offset) catch
            return com.E_OUTOFMEMORY;
        out.* = &range.base;
        return com.S_OK;
    }

    fn get_DocumentRange(
        self_base: *com.ITextProvider,
        out: *?*com.ITextRangeProvider,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        const range = self.newRange(0, self.doc.len) catch return com.E_OUTOFMEMORY;
        out.* = &range.base;
        return com.S_OK;
    }

    fn get_SupportedTextSelection(
        _: *com.ITextProvider,
        out: *i32,
    ) callconv(.winapi) com.HRESULT {
        out.* = com.SupportedTextSelection_None;
        return com.S_OK;
    }
};

// ── TextRange (ITextRangeProvider) ──────────────────────────────────────

pub const TextRange = struct {
    base: com.ITextRangeProvider,
    refcount: std.atomic.Value(u32),
    /// Holds a ref for the range's lifetime; the pattern owns the doc.
    pattern: *TextPattern,
    /// UTF-16 code-unit offsets, half-open, start <= end.
    start: usize,
    end: usize,

    const vtbl: com.ITextRangeProviderVtbl = .{
        .QueryInterface = TextRange.QueryInterface,
        .AddRef = TextRange.AddRef,
        .Release = TextRange.Release,
        .Clone = TextRange.Clone,
        .Compare = TextRange.Compare,
        .CompareEndpoints = TextRange.CompareEndpoints,
        .ExpandToEnclosingUnit = TextRange.ExpandToEnclosingUnit,
        .FindAttribute = TextRange.FindAttribute,
        .FindText = TextRange.FindText,
        .GetAttributeValue = TextRange.GetAttributeValue,
        .GetBoundingRectangles = TextRange.GetBoundingRectangles,
        .GetEnclosingElement = TextRange.GetEnclosingElement,
        .GetText = TextRange.GetText,
        .Move = TextRange.Move,
        .MoveEndpointByUnit = TextRange.MoveEndpointByUnit,
        .MoveEndpointByRange = TextRange.MoveEndpointByRange,
        .Select = TextRange.Select,
        .AddToSelection = TextRange.AddToSelection,
        .RemoveFromSelection = TextRange.RemoveFromSelection,
        .ScrollIntoView = TextRange.ScrollIntoView,
        .GetChildren = TextRange.GetChildren,
    };

    fn fromBase(p: *com.ITextRangeProvider) *TextRange {
        return @fieldParentPtr("base", p);
    }

    /// Recover our object from a caller-supplied range pointer, but only
    /// if it is actually ours: a foreign provider's object must never be
    /// reinterpreted. The shared vtable address is the identity check.
    fn fromForeign(p: ?*com.ITextRangeProvider) ?*TextRange {
        const other = p orelse return null;
        if (other.vtbl != &vtbl) return null;
        return fromBase(other);
    }

    fn doc(self: *const TextRange) []const u16 {
        return self.pattern.doc;
    }

    fn endpointOffset(self: *const TextRange, endpoint: i32) usize {
        return if (endpoint == com.TextPatternRangeEndpoint_Start)
            self.start
        else
            self.end;
    }

    // ── IUnknown ────────────────────────────────────────────────────

    fn QueryInterface(
        self_base: *com.ITextRangeProvider,
        iid: *const com.GUID,
        out: *?*anyopaque,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = null;
        if (iidEqual(iid, &com.IID_IUnknown) or
            iidEqual(iid, &com.IID_ITextRangeProvider))
        {
            out.* = @ptrCast(&self.base);
            _ = self.refcount.fetchAdd(1, .monotonic);
            return com.S_OK;
        }
        return com.E_NOINTERFACE;
    }

    fn AddRef(self_base: *com.ITextRangeProvider) callconv(.winapi) u32 {
        const self = fromBase(self_base);
        return self.refcount.fetchAdd(1, .monotonic) + 1;
    }

    fn Release(self_base: *com.ITextRangeProvider) callconv(.winapi) u32 {
        const self = fromBase(self_base);
        const prev = self.refcount.fetchSub(1, .acq_rel);
        if (prev == 1) {
            _ = TextPattern.Release(&self.pattern.base);
            pattern_alloc.destroy(self);
            return 0;
        }
        return prev - 1;
    }

    // ── ITextRangeProvider ──────────────────────────────────────────

    fn Clone(
        self_base: *com.ITextRangeProvider,
        out: *?*com.ITextRangeProvider,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        const copy = self.pattern.newRange(self.start, self.end) catch
            return com.E_OUTOFMEMORY;
        out.* = &copy.base;
        return com.S_OK;
    }

    fn Compare(
        self_base: *com.ITextRangeProvider,
        other_base: ?*com.ITextRangeProvider,
        out: *com.BOOL,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = 0;
        const other = fromForeign(other_base) orelse return com.S_OK;
        if (other.pattern == self.pattern and
            other.start == self.start and other.end == self.end)
        {
            out.* = 1;
        }
        return com.S_OK;
    }

    fn CompareEndpoints(
        self_base: *com.ITextRangeProvider,
        endpoint: i32,
        other_base: ?*com.ITextRangeProvider,
        other_endpoint: i32,
        out: *i32,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = 0;
        const other = fromForeign(other_base) orelse return com.E_INVALIDARG;
        if (other.pattern != self.pattern) return com.E_INVALIDARG;
        const a: i64 = @intCast(self.endpointOffset(endpoint));
        const b: i64 = @intCast(other.endpointOffset(other_endpoint));
        out.* = @intCast(std.math.clamp(
            a - b,
            @as(i64, std.math.minInt(i32)),
            @as(i64, std.math.maxInt(i32)),
        ));
        return com.S_OK;
    }

    fn ExpandToEnclosingUnit(
        self_base: *com.ITextRangeProvider,
        unit: i32,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        const expanded = expandRange(
            self.doc(),
            self.pattern.line_starts,
            self.start,
            unit,
        );
        self.start = expanded.start;
        self.end = expanded.end;
        return com.S_OK;
    }

    fn FindAttribute(
        _: *com.ITextRangeProvider,
        _: i32,
        _: com.VARIANT,
        _: com.BOOL,
        out: *?*com.ITextRangeProvider,
    ) callconv(.winapi) com.HRESULT {
        // No attributes are tracked; "not found" is the honest answer.
        out.* = null;
        return com.S_OK;
    }

    fn FindText(
        self_base: *com.ITextRangeProvider,
        needle: ?[*:0]const u16,
        backward: com.BOOL,
        ignore_case: com.BOOL,
        out: *?*com.ITextRangeProvider,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = null;
        const needle_ptr = needle orelse return com.S_OK;
        const needle_slice = std.mem.span(needle_ptr);
        const hit = findTextInDoc(
            self.doc(),
            self.start,
            self.end,
            needle_slice,
            backward != 0,
            ignore_case != 0,
        ) orelse return com.S_OK;
        const range = self.pattern.newRange(hit.start, hit.end) catch
            return com.E_OUTOFMEMORY;
        out.* = &range.base;
        return com.S_OK;
    }

    fn GetAttributeValue(
        _: *com.ITextRangeProvider,
        _: i32,
        out: *com.VARIANT,
    ) callconv(.winapi) com.HRESULT {
        var not_supported: ?*com.IUnknown = null;
        _ = com.UiaGetReservedNotSupportedValue(&not_supported);
        out.* = com.VARIANT.fromUnknown(not_supported);
        return com.S_OK;
    }

    fn GetBoundingRectangles(
        self_base: *com.ITextRangeProvider,
        out: *?*com.SAFEARRAY,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = null;
        const rects = boundingLineRects(
            pattern_alloc,
            self.doc(),
            self.pattern.line_starts,
            self.pattern.visible_start,
            self.pattern.visible_end,
            self.start,
            self.end,
            self.pattern.geo,
        ) catch return com.E_OUTOFMEMORY;
        defer pattern_alloc.free(rects);

        const array = com.SafeArrayCreateVector(
            com.VT_R8,
            0,
            @intCast(rects.len * 4),
        ) orelse return com.E_OUTOFMEMORY;
        var index: i32 = 0;
        for (rects) |rect| {
            for ([_]f64{ rect.left, rect.top, rect.width, rect.height }) |value| {
                var v = value;
                if (com.SafeArrayPutElement(array, &index, @ptrCast(&v)) != com.S_OK) {
                    _ = com.SafeArrayDestroy(array);
                    return com.E_OUTOFMEMORY;
                }
                index += 1;
            }
        }
        out.* = array;
        return com.S_OK;
    }

    fn GetEnclosingElement(
        self_base: *com.ITextRangeProvider,
        out: *?*com.IRawElementProviderSimple,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        const root = self.pattern.root;
        _ = root.vtbl.AddRef(root);
        out.* = root;
        return com.S_OK;
    }

    fn GetText(
        self_base: *com.ITextRangeProvider,
        max_length: i32,
        out: *?[*:0]u16,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        var len = self.end - self.start;
        if (max_length >= 0) len = @min(len, @as(usize, @intCast(max_length)));
        const slice = self.doc()[self.start .. self.start + len];
        out.* = com.SysAllocStringLen(
            if (slice.len == 0) null else slice.ptr,
            @intCast(slice.len),
        ) orelse return com.E_OUTOFMEMORY;
        return com.S_OK;
    }

    fn Move(
        self_base: *com.ITextRangeProvider,
        unit: i32,
        count: i32,
        out: *i32,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        // Normalize to a degenerate range at start, move, then expand —
        // the standard provider recipe for snapshot documents.
        const result = moveOffsetByUnit(
            self.doc(),
            self.pattern.line_starts,
            self.start,
            unit,
            count,
        );
        self.start = result.offset;
        self.end = result.offset;
        const expanded = expandRange(
            self.doc(),
            self.pattern.line_starts,
            self.start,
            unit,
        );
        self.start = expanded.start;
        self.end = expanded.end;
        out.* = result.moved;
        return com.S_OK;
    }

    fn MoveEndpointByUnit(
        self_base: *com.ITextRangeProvider,
        endpoint: i32,
        unit: i32,
        count: i32,
        out: *i32,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        const moving_start = endpoint == com.TextPatternRangeEndpoint_Start;
        const result = moveOffsetByUnit(
            self.doc(),
            self.pattern.line_starts,
            self.endpointOffset(endpoint),
            unit,
            count,
        );
        if (moving_start) self.start = result.offset else self.end = result.offset;
        // A crossed endpoint drags the other one along (degenerate range).
        if (self.start > self.end) {
            if (moving_start) self.end = self.start else self.start = self.end;
        }
        out.* = result.moved;
        return com.S_OK;
    }

    fn MoveEndpointByRange(
        self_base: *com.ITextRangeProvider,
        endpoint: i32,
        other_base: ?*com.ITextRangeProvider,
        other_endpoint: i32,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        const other = fromForeign(other_base) orelse return com.E_INVALIDARG;
        if (other.pattern != self.pattern) return com.E_INVALIDARG;
        const target = other.endpointOffset(other_endpoint);
        if (endpoint == com.TextPatternRangeEndpoint_Start) {
            self.start = target;
            if (self.start > self.end) self.end = self.start;
        } else {
            self.end = target;
            if (self.start > self.end) self.start = self.end;
        }
        return com.S_OK;
    }

    fn Select(_: *com.ITextRangeProvider) callconv(.winapi) com.HRESULT {
        return com.E_NOTIMPL;
    }

    fn AddToSelection(_: *com.ITextRangeProvider) callconv(.winapi) com.HRESULT {
        return com.E_NOTIMPL;
    }

    fn RemoveFromSelection(_: *com.ITextRangeProvider) callconv(.winapi) com.HRESULT {
        return com.E_NOTIMPL;
    }

    fn ScrollIntoView(
        _: *com.ITextRangeProvider,
        _: com.BOOL,
    ) callconv(.winapi) com.HRESULT {
        // The snapshot has no viewport to move; succeed quietly.
        return com.S_OK;
    }

    fn GetChildren(
        _: *com.ITextRangeProvider,
        out: *?*com.SAFEARRAY,
    ) callconv(.winapi) com.HRESULT {
        out.* = com.SafeArrayCreateVector(com.VT_UNKNOWN, 0, 0) orelse
            return com.E_OUTOFMEMORY;
        return com.S_OK;
    }
};

// ── Tests (pure math; named win32 so the per-commit gate runs them) ─────

fn testLineStarts(comptime utf8: []const u8) ![]usize {
    const doc = std.unicode.utf8ToUtf16LeStringLiteral(utf8);
    return try buildLineStarts(std.testing.allocator, doc);
}

test "win32 uia text pattern line starts" {
    {
        const starts = try testLineStarts("one\ntwo\n\nfour");
        defer std.testing.allocator.free(starts);
        try std.testing.expectEqualSlices(usize, &.{ 0, 4, 8, 9 }, starts);
    }
    {
        // Trailing newline terminates the last line; no phantom line.
        const starts = try testLineStarts("one\ntwo\n");
        defer std.testing.allocator.free(starts);
        try std.testing.expectEqualSlices(usize, &.{ 0, 4 }, starts);
    }
    {
        const starts = try testLineStarts("");
        defer std.testing.allocator.free(starts);
        try std.testing.expectEqualSlices(usize, &.{0}, starts);
    }
}

test "win32 uia text pattern line index lookup" {
    const starts = [_]usize{ 0, 4, 8, 9 };
    try std.testing.expectEqual(@as(usize, 0), lineIndexForOffset(&starts, 0));
    try std.testing.expectEqual(@as(usize, 0), lineIndexForOffset(&starts, 3));
    try std.testing.expectEqual(@as(usize, 1), lineIndexForOffset(&starts, 4));
    try std.testing.expectEqual(@as(usize, 2), lineIndexForOffset(&starts, 8));
    try std.testing.expectEqual(@as(usize, 3), lineIndexForOffset(&starts, 100));
}

test "win32 uia text pattern expand units" {
    // doc = "one\ntwo\n\nfour" (13 units), lines at 0/4/8/9.
    const doc = std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo\n\nfour");
    const starts = [_]usize{ 0, 4, 8, 9 };

    const line = expandRange(doc, &starts, 5, com.TextUnit_Line);
    try std.testing.expectEqual(OffsetRange{ .start = 4, .end = 8 }, line);

    // "two" plus its whole trailing separator run — the newline AND the
    // blank line's newline — so word navigation skips empty lines.
    const word = expandRange(doc, &starts, 5, com.TextUnit_Word);
    try std.testing.expectEqual(OffsetRange{ .start = 4, .end = 9 }, word);

    const last = expandRange(doc, &starts, 10, com.TextUnit_Line);
    try std.testing.expectEqual(OffsetRange{ .start = 9, .end = 13 }, last);

    const char = expandRange(doc, &starts, 12, com.TextUnit_Character);
    try std.testing.expectEqual(OffsetRange{ .start = 12, .end = 13 }, char);

    const document = expandRange(doc, &starts, 5, com.TextUnit_Document);
    try std.testing.expectEqual(OffsetRange{ .start = 0, .end = 13 }, document);
}

test "win32 uia text pattern endpoint moves clamp at edges" {
    const doc = std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo\n\nfour");
    const starts = [_]usize{ 0, 4, 8, 9 };

    const fwd = moveOffsetByUnit(doc, &starts, 0, com.TextUnit_Character, 5);
    try std.testing.expectEqual(MoveResult{ .offset = 5, .moved = 5 }, fwd);

    const clamped = moveOffsetByUnit(doc, &starts, 10, com.TextUnit_Character, 99);
    try std.testing.expectEqual(MoveResult{ .offset = 13, .moved = 3 }, clamped);

    const back_line = moveOffsetByUnit(doc, &starts, 9, com.TextUnit_Line, -2);
    try std.testing.expectEqual(MoveResult{ .offset = 4, .moved = -2 }, back_line);

    const line_clamp = moveOffsetByUnit(doc, &starts, 0, com.TextUnit_Line, -5);
    try std.testing.expectEqual(MoveResult{ .offset = 0, .moved = 0 }, line_clamp);

    const doc_fwd = moveOffsetByUnit(doc, &starts, 3, com.TextUnit_Document, 1);
    try std.testing.expectEqual(MoveResult{ .offset = 13, .moved = 1 }, doc_fwd);

    const zero = moveOffsetByUnit(doc, &starts, 3, com.TextUnit_Line, 0);
    try std.testing.expectEqual(MoveResult{ .offset = 3, .moved = 0 }, zero);
}

test "win32 uia text pattern utf16 prefix lengths" {
    const utf8 = "A\xf0\x9f\x94\xa5B"; // A + U+1F525 (surrogate pair) + B
    try std.testing.expectEqual(@as(usize, 0), utf16LenOfPrefix(utf8, 0));
    try std.testing.expectEqual(@as(usize, 1), utf16LenOfPrefix(utf8, 1));
    try std.testing.expectEqual(@as(usize, 3), utf16LenOfPrefix(utf8, 5));
    try std.testing.expectEqual(@as(usize, 4), utf16LenOfPrefix(utf8, 6));
    // Out-of-range clamps to the full length.
    try std.testing.expectEqual(@as(usize, 4), utf16LenOfPrefix(utf8, 99));
}

test "win32 uia text pattern bounding rects" {
    const doc = std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo\n\nfour");
    const starts = [_]usize{ 0, 4, 8, 9 };
    const geo: TextDoc = .{
        .utf8 = &.{},
        .visible_start = 0,
        .visible_end = 0,
        .cell_w = 8,
        .cell_h = 16,
        .origin_x = 100,
        .origin_y = 200,
        .viewport_cols = 80,
    };

    // Range over the first two lines: one rect per ink segment, the
    // newline occupies no cell.
    {
        const rects = try boundingLineRects(
            std.testing.allocator,
            doc,
            &starts,
            0,
            doc.len,
            0,
            7,
            geo,
        );
        defer std.testing.allocator.free(rects);
        try std.testing.expectEqual(@as(usize, 2), rects.len);
        try std.testing.expectEqual(
            LineRect{ .left = 100, .top = 200, .width = 24, .height = 16 },
            rects[0],
        );
        try std.testing.expectEqual(
            LineRect{ .left = 100, .top = 216, .width = 24, .height = 16 },
            rects[1],
        );
    }

    // A range crossing the blank line skips it; the viewport clip
    // shifts rows relative to the first visible line.
    {
        const rects = try boundingLineRects(
            std.testing.allocator,
            doc,
            &starts,
            4,
            doc.len,
            4,
            13,
            geo,
        );
        defer std.testing.allocator.free(rects);
        try std.testing.expectEqual(@as(usize, 2), rects.len);
        try std.testing.expectEqual(@as(f64, 200), rects[0].top);
        try std.testing.expectEqual(
            LineRect{ .left = 100, .top = 232, .width = 32, .height = 16 },
            rects[1],
        );
    }

    // Unknown geometry → no rects.
    {
        var no_geo = geo;
        no_geo.cell_w = 0;
        const rects = try boundingLineRects(
            std.testing.allocator,
            doc,
            &starts,
            0,
            doc.len,
            0,
            13,
            no_geo,
        );
        defer std.testing.allocator.free(rects);
        try std.testing.expectEqual(@as(usize, 0), rects.len);
    }
}

test "win32 uia text pattern point hit-testing" {
    const doc = std.unicode.utf8ToUtf16LeStringLiteral("one\ntwo\n\nfour");
    const starts = [_]usize{ 0, 4, 8, 9 };
    const geo: TextDoc = .{
        .utf8 = &.{},
        .visible_start = 0,
        .visible_end = 0,
        .cell_w = 8,
        .cell_h = 16,
        .origin_x = 100,
        .origin_y = 200,
        .viewport_cols = 80,
    };

    // Row 1 col 2 -> line "two", offset 4+2.
    try std.testing.expectEqual(
        @as(usize, 6),
        offsetForPoint(doc, &starts, 0, doc.len, geo, 117, 217),
    );
    // Past the line's ink clamps to its content end (before the '\n').
    try std.testing.expectEqual(
        @as(usize, 7),
        offsetForPoint(doc, &starts, 0, doc.len, geo, 900, 217),
    );
    // Above/left of the grid clamps to the first cell.
    try std.testing.expectEqual(
        @as(usize, 0),
        offsetForPoint(doc, &starts, 0, doc.len, geo, 0, 0),
    );
    // Below the last line clamps into the last line.
    try std.testing.expectEqual(
        @as(usize, 10),
        offsetForPoint(doc, &starts, 0, doc.len, geo, 108, 900),
    );
    // Unknown geometry -> offset 0.
    var no_geo = geo;
    no_geo.cell_w = 0;
    try std.testing.expectEqual(
        @as(usize, 0),
        offsetForPoint(doc, &starts, 0, doc.len, no_geo, 117, 217),
    );
}

test "win32 uia text pattern word boundaries" {
    // Offsets: alpha=0..5, blanks=5..7, beta=7..11, newline=11, gamma=12..17.
    const doc = std.unicode.utf8ToUtf16LeStringLiteral("alpha  beta\ngamma");
    const starts = [_]usize{ 0, 12 };

    // A word is its ink plus trailing blanks; standing on a blank
    // still belongs to the word whose tail it is.
    try std.testing.expectEqual(
        OffsetRange{ .start = 0, .end = 7 },
        expandRange(doc, &starts, 2, com.TextUnit_Word),
    );
    try std.testing.expectEqual(
        OffsetRange{ .start = 0, .end = 7 },
        expandRange(doc, &starts, 5, com.TextUnit_Word),
    );
    try std.testing.expectEqual(
        OffsetRange{ .start = 7, .end = 12 },
        expandRange(doc, &starts, 8, com.TextUnit_Word),
    );
    try std.testing.expectEqual(
        OffsetRange{ .start = 12, .end = 17 },
        expandRange(doc, &starts, 16, com.TextUnit_Word),
    );

    // Forward moves land on successive word starts; clamp at the end.
    const fwd = moveOffsetByUnit(doc, &starts, 0, com.TextUnit_Word, 2);
    try std.testing.expectEqual(MoveResult{ .offset = 12, .moved = 2 }, fwd);
    const fwd_clamp = moveOffsetByUnit(doc, &starts, 0, com.TextUnit_Word, 9);
    try std.testing.expectEqual(MoveResult{ .offset = 17, .moved = 3 }, fwd_clamp);

    // Backward from a word start steps to the previous word; from
    // mid-word it snaps to this word's start first.
    const back = moveOffsetByUnit(doc, &starts, 12, com.TextUnit_Word, -1);
    try std.testing.expectEqual(MoveResult{ .offset = 7, .moved = -1 }, back);
    const snap = moveOffsetByUnit(doc, &starts, 9, com.TextUnit_Word, -1);
    try std.testing.expectEqual(MoveResult{ .offset = 7, .moved = -1 }, snap);
    const back_clamp = moveOffsetByUnit(doc, &starts, 0, com.TextUnit_Word, -3);
    try std.testing.expectEqual(MoveResult{ .offset = 0, .moved = 0 }, back_clamp);
}

test "win32 uia text pattern find text" {
    const doc = std.unicode.utf8ToUtf16LeStringLiteral("Error: FAIL then error again");
    const needle = std.unicode.utf8ToUtf16LeStringLiteral("error");

    const fwd = findTextInDoc(doc, 0, doc.len, needle, false, true).?;
    try std.testing.expectEqual(OffsetRange{ .start = 0, .end = 5 }, fwd);

    const back = findTextInDoc(doc, 0, doc.len, needle, true, true).?;
    try std.testing.expectEqual(OffsetRange{ .start = 17, .end = 22 }, back);

    const exact = findTextInDoc(doc, 0, doc.len, needle, false, false).?;
    try std.testing.expectEqual(OffsetRange{ .start = 17, .end = 22 }, exact);

    try std.testing.expect(findTextInDoc(doc, 0, 3, needle, false, true) == null);
    try std.testing.expect(findTextInDoc(doc, 0, doc.len, needle[0..0], false, true) == null);
}
