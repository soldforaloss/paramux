//! Split-divider drag-resize: pure hit-testing + ratio math for dragging
//! the gap between two split panes to change their sizes.
//!
//! The Win32 host window proc (`hostWindowProc` in win32.zig) owns the mouse
//! capture and the tree mutation (`SplitTree.resizeInPlace`); this module holds
//! only the geometry so it is unit-testable without a live window.
//!
//! Coordinate model: all pixel inputs are host-client space — the same space
//! as WM_* mouse lParam and the pane rects computed by `Host.layout()`. A
//! `Divider` describes one split node's draggable edge. `hitTest` picks the
//! divider under a cursor; `DragState.ratioAt` converts a cursor position into
//! that split's local ratio (clamped so neither pane collapses).
//!
//! Tolerances/sizes here are UNSCALED constants — the caller multiplies by the
//! host DPI scale before passing them in, so this module stays DPI-agnostic.

const std = @import("std");

/// A horizontal split lays its children side-by-side, so its divider is a
/// VERTICAL bar dragged left/right (IDC_SIZEWE). A vertical split stacks its
/// children, so its divider is a HORIZONTAL bar dragged up/down (IDC_SIZENS).
pub const Orientation = enum { horizontal, vertical };

/// Half the divider gap, in unscaled px, that `Host.layout()` insets into each
/// adjacent pane's internal edge. The full grab strip between two panes is
/// twice this. 3 (=> ~6px at 96 DPI) is wide enough to grab reliably while
/// staying visually thin.
pub const divider_half_px: i32 = 3;

/// Extra unscaled px beyond the painted gap that still count as "on the
/// divider" for hover/hit-testing.
pub const grab_slop_px: i32 = 3;

/// Minimum unscaled px a pane may be shrunk to along the drag axis, so a
/// dragged divider can't collapse a pane to nothing.
pub const min_pane_px: i32 = 32;

/// One draggable split edge, in host-client pixels. `line` is the divider
/// centerline along the drag axis; `span_lo`/`span_hi` bound it on the
/// perpendicular axis; `axis_origin`/`axis_size` are the split's own extent
/// along the drag axis (used to convert a cursor position to a ratio).
pub const Divider = struct {
    /// Index of the split node in the tree's `nodes` slice.
    node_index: usize,
    orientation: Orientation,
    line: i32,
    span_lo: i32,
    span_hi: i32,
    axis_origin: i32,
    axis_size: i32,
};

fn absDiff(a: i32, b: i32) i32 {
    return if (a >= b) a - b else b - a;
}

/// Perpendicular distance from `(x, y)` to `d`'s divider line, if the cursor is
/// within the divider's perpendicular span and within `tol` px of the line;
/// otherwise null. Smaller means a closer hit.
pub fn hitDistance(x: i32, y: i32, d: Divider, tol: i32) ?i32 {
    switch (d.orientation) {
        // Vertical bar: distance measured along x, span checked along y.
        .horizontal => {
            if (y < d.span_lo or y > d.span_hi) return null;
            const dist = absDiff(x, d.line);
            return if (dist <= tol) dist else null;
        },
        // Horizontal bar: distance measured along y, span checked along x.
        .vertical => {
            if (x < d.span_lo or x > d.span_hi) return null;
            const dist = absDiff(y, d.line);
            return if (dist <= tol) dist else null;
        },
    }
}

/// Index of the closest divider under the cursor within `tol`, or null. On a
/// tie the earlier divider wins; dividers only coincide at crossings, so this
/// is unambiguous in practice.
pub fn hitTest(x: i32, y: i32, dividers: []const Divider, tol: i32) ?usize {
    var best: ?usize = null;
    var best_dist: i32 = std.math.maxInt(i32);
    for (dividers, 0..) |d, i| {
        if (hitDistance(x, y, d, tol)) |dist| {
            if (dist < best_dist) {
                best_dist = dist;
                best = i;
            }
        }
    }
    return best;
}

/// Live drag state, stored on the Host (plain fields + SetCapture, matching the
/// tab-drag convention). `axis_origin`/`axis_size`/`min_pane_px` are captured
/// at drag start and stay constant for the drag (ancestors and window size
/// don't change mid-drag).
pub const DragState = struct {
    active: bool = false,
    node_index: usize = 0,
    orientation: Orientation = .horizontal,
    axis_origin: i32 = 0,
    axis_size: i32 = 1,
    min_pane_px: i32 = 0,

    pub fn begin(self: *DragState, d: Divider, min_pane: i32) void {
        self.* = .{
            .active = true,
            .node_index = d.node_index,
            .orientation = d.orientation,
            .axis_origin = d.axis_origin,
            .axis_size = @max(1, d.axis_size),
            .min_pane_px = min_pane,
        };
    }

    pub fn end(self: *DragState) void {
        self.active = false;
    }

    /// New local ratio in [0,1] for the split, from the cursor position along
    /// the drag axis (x for horizontal, y for vertical), clamped so neither
    /// child shrinks below `min_pane_px`.
    pub fn ratioAt(self: *const DragState, cursor_axis: i32) f32 {
        const size: f32 = @floatFromInt(self.axis_size);
        const raw: f32 = @as(f32, @floatFromInt(cursor_axis - self.axis_origin)) / size;
        const min_ratio: f32 = @as(f32, @floatFromInt(self.min_pane_px)) / size;
        const lo = @min(min_ratio, 0.5);
        const hi = @max(1.0 - min_ratio, 0.5);
        return std.math.clamp(raw, lo, hi);
    }
};

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

fn hDivider(node_index: usize, line: i32, lo: i32, hi: i32, origin: i32, size: i32) Divider {
    return .{ .node_index = node_index, .orientation = .horizontal, .line = line, .span_lo = lo, .span_hi = hi, .axis_origin = origin, .axis_size = size };
}

test "split_resize: hitDistance on a vertical bar within span and tolerance" {
    const d = hDivider(1, 100, 0, 200, 0, 400);
    try testing.expectEqual(@as(?i32, 2), hitDistance(102, 50, d, 6));
    try testing.expectEqual(@as(?i32, 0), hitDistance(100, 199, d, 6));
}

test "split_resize: hitDistance rejects outside perpendicular span" {
    const d = hDivider(1, 100, 0, 200, 0, 400);
    try testing.expectEqual(@as(?i32, null), hitDistance(100, 201, d, 6));
    try testing.expectEqual(@as(?i32, null), hitDistance(100, -1, d, 6));
}

test "split_resize: hitDistance rejects beyond tolerance" {
    const d = hDivider(1, 100, 0, 200, 0, 400);
    try testing.expectEqual(@as(?i32, null), hitDistance(110, 50, d, 6));
}

test "split_resize: hitDistance on a horizontal bar measures along y" {
    const d = Divider{ .node_index = 2, .orientation = .vertical, .line = 80, .span_lo = 0, .span_hi = 300, .axis_origin = 0, .axis_size = 160 };
    try testing.expectEqual(@as(?i32, 3), hitDistance(150, 83, d, 6));
    try testing.expectEqual(@as(?i32, null), hitDistance(301, 80, d, 6)); // x outside span
}

test "split_resize: hitTest picks the nearest divider" {
    const dividers = [_]Divider{
        hDivider(1, 100, 0, 200, 0, 400),
        hDivider(3, 300, 0, 200, 0, 400),
    };
    try testing.expectEqual(@as(?usize, 0), hitTest(103, 50, &dividers, 6));
    try testing.expectEqual(@as(?usize, 1), hitTest(298, 50, &dividers, 6));
}

test "split_resize: hitTest returns null when nothing is close" {
    const dividers = [_]Divider{hDivider(1, 100, 0, 200, 0, 400)};
    try testing.expectEqual(@as(?usize, null), hitTest(200, 50, &dividers, 6));
}

test "split_resize: DragState.ratioAt maps cursor to a local ratio" {
    var ds = DragState{};
    ds.begin(hDivider(1, 100, 0, 200, 0, 400), 32);
    try testing.expectApproxEqAbs(@as(f32, 0.5), ds.ratioAt(200), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.25), ds.ratioAt(100), 0.001);
}

test "split_resize: DragState.ratioAt clamps to keep a minimum pane" {
    var ds = DragState{};
    ds.begin(hDivider(1, 100, 0, 200, 0, 400), 40); // min_ratio = 40/400 = 0.1
    try testing.expectApproxEqAbs(@as(f32, 0.1), ds.ratioAt(-100), 0.001); // far left clamps up
    try testing.expectApproxEqAbs(@as(f32, 0.9), ds.ratioAt(999), 0.001); // far right clamps down
}

test "split_resize: DragState.ratioAt pins tiny splits to center" {
    var ds = DragState{};
    ds.begin(hDivider(1, 20, 0, 200, 0, 50), 40); // min_ratio = 0.8 > 0.5 -> pinned
    try testing.expectApproxEqAbs(@as(f32, 0.5), ds.ratioAt(10), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.5), ds.ratioAt(45), 0.001);
}

test "split_resize: DragState begin/end toggles active" {
    var ds = DragState{};
    try testing.expect(!ds.active);
    ds.begin(hDivider(2, 100, 0, 200, 0, 400), 32);
    try testing.expect(ds.active);
    try testing.expectEqual(@as(usize, 2), ds.node_index);
    ds.end();
    try testing.expect(!ds.active);
}
