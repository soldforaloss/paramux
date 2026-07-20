//! Root `IRawElementProviderSimple` for the paramux host HWND.
//!
//! Returned from `WM_GETOBJECT` when the client asks for
//! `UiaRootObjectId`. Reports:
//!   * `UIA_NamePropertyId`            = live window title
//!   * `UIA_ControlTypePropertyId`     = UIA_WindowControlTypeId
//!   * `UIA_LocalizedControlTypePropertyId` = "terminal window"
//!   * `UIA_IsKeyboardFocusablePropertyId`  = false (focus lives on panes)
//!   * `UIA_HasKeyboardFocusPropertyId`     = false
//!   * `UIA_IsEnabledPropertyId`            = true
//!   * `UIA_IsControlElementPropertyId`     = true
//!   * `UIA_FrameworkIdPropertyId`          = "Win32"
//!
//! BSTR ownership: `GetPropertyValue` hands a BSTR to the caller who
//! will `VariantClear` (which `SysFreeString`s it). We must allocate a
//! fresh BSTR per call — caching pointers and handing the same one
//! back twice produces a use-after-free the second time and a
//! double-free when we try to free our "cached" pointer too.
//!
//! `get_HostRawElementProvider` chains to `UiaHostProviderFromHwnd` so
//! the system's default provider is merged in — that is what lets
//! Narrator pick up `Minimize/Maximize/Close` caption-button focus out
//! of the box even before we ship the integrated titlebar.

const std = @import("std");
const com = @import("com.zig");
const constants = @import("constants.zig");
const text_pattern = @import("text_pattern.zig");

/// Optional callback the host registers so the window's UIA HelpText
/// can carry a live fleet summary ("2 waiting, 1 done; 4 panes").
/// Writes UTF-8 into `buf` and returns the length (0 = no text).
pub var fleet_help_fn: ?*const fn (com.HWND, []u8) usize = null;

pub fn setFleetHelpFn(f: *const fn (com.HWND, []u8) usize) void {
    fleet_help_fn = f;
}

/// Snapshot handed back by the host for the UIA TextPattern: the full
/// document (screen + scrollback, UTF-8) plus the viewport's byte range
/// within it. `utf8` MUST be allocated with `std.heap.smp_allocator` —
/// the caller frees it there, and the call may arrive on a UIA RPC
/// thread.
pub const TextDoc = struct {
    utf8: []const u8,
    visible_start: usize,
    visible_end: usize,
};

pub var text_doc_fn: ?*const fn (com.HWND) ?TextDoc = null;

pub fn setTextDocFn(f: *const fn (com.HWND) ?TextDoc) void {
    text_doc_fn = f;
}

pub const RootProvider = struct {
    // COM interface shape MUST be first so &self.base == &self (COM layout).
    base: com.IRawElementProviderSimple,
    refcount: std.atomic.Value(u32),
    alloc: std.mem.Allocator,
    hwnd: com.HWND,

    /// The singleton vtable pointer. All RootProvider instances share it.
    const vtbl: com.IRawElementProviderSimpleVtbl = .{
        .QueryInterface = RootProvider.QueryInterface,
        .AddRef = RootProvider.AddRef,
        .Release = RootProvider.Release,
        .get_ProviderOptions = RootProvider.get_ProviderOptions,
        .GetPatternProvider = RootProvider.GetPatternProvider,
        .GetPropertyValue = RootProvider.GetPropertyValue,
        .get_HostRawElementProvider = RootProvider.get_HostRawElementProvider,
    };

    pub fn create(alloc: std.mem.Allocator, hwnd: com.HWND) !*RootProvider {
        const self = try alloc.create(RootProvider);
        self.* = .{
            .base = .{ .vtbl = &vtbl },
            .refcount = std.atomic.Value(u32).init(1),
            .alloc = alloc,
            .hwnd = hwnd,
        };
        return self;
    }

    fn fromBase(p: *com.IRawElementProviderSimple) *RootProvider {
        return @fieldParentPtr("base", p);
    }

    /// Allocate a BSTR copy of `literal` for a per-call property return.
    fn allocBstrFromLiteral(literal: [*:0]const u16) ?[*:0]u16 {
        return com.SysAllocString(literal);
    }

    /// Allocate a BSTR for the current HWND title, or a "paramux"
    /// fallback if the title is empty or the query fails. Runs per
    /// property query — caching is unsafe because the caller frees.
    fn allocNameBstr(self: *RootProvider) ?[*:0]u16 {
        const fallback = std.unicode.utf8ToUtf16LeStringLiteral("paramux");
        const len = com.GetWindowTextLengthW(self.hwnd);
        if (len <= 0) return com.SysAllocString(fallback);

        // GetWindowTextLengthW returns chars excluding the null
        // terminator; allocate len+1 u16s + a sentinel slot.
        const size: usize = @intCast(len);
        const buf = self.alloc.allocSentinel(u16, size, 0) catch
            return com.SysAllocString(fallback);
        defer self.alloc.free(buf);
        const copied = com.GetWindowTextW(self.hwnd, buf.ptr, @intCast(size + 1));
        if (copied <= 0) return com.SysAllocString(fallback);
        buf[@intCast(copied)] = 0;
        return com.SysAllocString(@ptrCast(buf.ptr));
    }

    // ── IUnknown ────────────────────────────────────────────────────────

    pub fn QueryInterface(
        self_base: *com.IRawElementProviderSimple,
        iid: *const com.GUID,
        out: *?*anyopaque,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = null;
        if (iidEqual(iid, &com.IID_IUnknown) or
            iidEqual(iid, &com.IID_IRawElementProviderSimple))
        {
            out.* = @ptrCast(&self.base);
            _ = self.refcount.fetchAdd(1, .monotonic);
            return com.S_OK;
        }
        return com.E_NOINTERFACE;
    }

    pub fn AddRef(self_base: *com.IRawElementProviderSimple) callconv(.winapi) u32 {
        const self = fromBase(self_base);
        return self.refcount.fetchAdd(1, .monotonic) + 1;
    }

    pub fn Release(self_base: *com.IRawElementProviderSimple) callconv(.winapi) u32 {
        const self = fromBase(self_base);
        const prev = self.refcount.fetchSub(1, .acq_rel);
        if (prev == 1) {
            self.alloc.destroy(self);
            return 0;
        }
        return prev - 1;
    }

    // ── IRawElementProviderSimple ───────────────────────────────────────

    fn get_ProviderOptions(
        _: *com.IRawElementProviderSimple,
        out: *i32,
    ) callconv(.winapi) com.HRESULT {
        out.* = com.ProviderOptions_ServerSideProvider;
        return com.S_OK;
    }

    fn GetPatternProvider(
        self_base: *com.IRawElementProviderSimple,
        pattern_id: i32,
        out: *?*com.IUnknown,
    ) callconv(.winapi) com.HRESULT {
        // Unsupported patterns return S_OK with out=null per the UIA
        // contract, never E_NOTIMPL.
        out.* = null;
        if (pattern_id == constants.UIA_TextPatternId) {
            const self = fromBase(self_base);
            const doc_fn = text_doc_fn orelse return com.S_OK;
            const doc = doc_fn(self.hwnd) orelse return com.S_OK;
            defer std.heap.smp_allocator.free(doc.utf8);
            const pattern = text_pattern.TextPattern.create(
                &self.base,
                doc.utf8,
                doc.visible_start,
                doc.visible_end,
            ) catch return com.S_OK;
            // Ownership of the initial ref transfers to the caller.
            out.* = @ptrCast(&pattern.base);
        }
        return com.S_OK;
    }

    fn GetPropertyValue(
        self_base: *com.IRawElementProviderSimple,
        prop_id: i32,
        out: *com.VARIANT,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        out.* = com.VARIANT.empty();

        switch (prop_id) {
            constants.UIA_ControlTypePropertyId => {
                out.* = com.VARIANT.fromI4(constants.UIA_WindowControlTypeId);
            },
            constants.UIA_NamePropertyId => {
                out.* = com.VARIANT.fromBstr(self.allocNameBstr());
            },
            constants.UIA_HelpTextPropertyId => {
                if (fleet_help_fn) |help_fn| {
                    var help_buf: [160]u8 = undefined;
                    const n = help_fn(self.hwnd, &help_buf);
                    if (n > 0) {
                        var w_buf: [161]u16 = undefined;
                        const wn = std.unicode.utf8ToUtf16Le(w_buf[0..160], help_buf[0..n]) catch 0;
                        if (wn > 0) {
                            w_buf[wn] = 0;
                            out.* = com.VARIANT.fromBstr(com.SysAllocString(@ptrCast(&w_buf)));
                        }
                    }
                }
            },
            constants.UIA_LocalizedControlTypePropertyId => {
                const literal = std.unicode.utf8ToUtf16LeStringLiteral("terminal window");
                out.* = com.VARIANT.fromBstr(allocBstrFromLiteral(literal));
            },
            constants.UIA_FrameworkIdPropertyId => {
                const literal = std.unicode.utf8ToUtf16LeStringLiteral("Win32");
                out.* = com.VARIANT.fromBstr(allocBstrFromLiteral(literal));
            },
            constants.UIA_IsControlElementPropertyId,
            constants.UIA_IsContentElementPropertyId,
            constants.UIA_IsEnabledPropertyId,
            => out.* = com.VARIANT.fromBool(true),
            constants.UIA_IsKeyboardFocusablePropertyId,
            constants.UIA_HasKeyboardFocusPropertyId,
            => out.* = com.VARIANT.fromBool(false),
            else => {
                // Unreported property: empty VARIANT + S_OK is the correct
                // UIA contract; do NOT return E_NOTIMPL.
            },
        }
        return com.S_OK;
    }

    fn get_HostRawElementProvider(
        self_base: *com.IRawElementProviderSimple,
        out: *?*com.IRawElementProviderSimple,
    ) callconv(.winapi) com.HRESULT {
        const self = fromBase(self_base);
        // Chain the system's default provider so the caption buttons,
        // system menu, and window-level accessibility tree come through
        // unchanged. We do NOT hold onto the returned provider — the
        // client does.
        return com.UiaHostProviderFromHwnd(self.hwnd, out);
    }
};

fn iidEqual(a: *const com.GUID, b: *const com.GUID) bool {
    return std.mem.eql(u8, std.mem.asBytes(a), std.mem.asBytes(b));
}

test "RootProvider create / release balances refcount" {
    // We can't call the real Win32 `UiaHostProviderFromHwnd` inside a
    // unit test, but we can exercise create/AddRef/Release directly.
    var rp = try RootProvider.create(std.testing.allocator, @ptrFromInt(0x1));
    // Initial refcount 1 after create.
    try std.testing.expectEqual(@as(u32, 2), RootProvider.AddRef(&rp.base));
    try std.testing.expectEqual(@as(u32, 1), RootProvider.Release(&rp.base));
    // Final Release drops to 0 and destroys the instance.
    try std.testing.expectEqual(@as(u32, 0), RootProvider.Release(&rp.base));
}

test "RootProvider QueryInterface returns IRawElementProviderSimple" {
    var rp = try RootProvider.create(std.testing.allocator, @ptrFromInt(0x1));
    defer _ = RootProvider.Release(&rp.base);

    var out: ?*anyopaque = null;
    const hr = RootProvider.QueryInterface(&rp.base, &com.IID_IRawElementProviderSimple, &out);
    try std.testing.expectEqual(com.S_OK, hr);
    try std.testing.expect(out != null);
    // QI returned a new ref — release it.
    _ = RootProvider.Release(&rp.base);
}

test "RootProvider QueryInterface rejects unknown IID" {
    var rp = try RootProvider.create(std.testing.allocator, @ptrFromInt(0x1));
    defer _ = RootProvider.Release(&rp.base);

    const bogus = com.GUID.parse("{DEADBEEF-0000-0000-0000-000000000000}");
    var out: ?*anyopaque = null;
    const hr = RootProvider.QueryInterface(&rp.base, &bogus, &out);
    try std.testing.expectEqual(com.E_NOINTERFACE, hr);
    try std.testing.expect(out == null);
}
