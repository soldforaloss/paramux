//! Windows taskbar Jump List: right-click the paramux taskbar icon and
//! get real tasks — New Window, Settings, Attention Inbox. Registered
//! once at startup via ICustomDestinationList; tasks launch the
//! `paramux.com` console shim, whose actions forward into the running
//! instance over IPC (or start one for New Window).
//!
//! Mirrors the COM idiom of `win32_taskbar_progress.zig`: hand-rolled
//! vtables, best-effort HRESULTs (a jump-list failure must never affect
//! the app), and no COM init here — the caller owns the apartment.

const std = @import("std");
const windows = std.os.windows;

const GUID = windows.GUID;
const HRESULT = windows.HRESULT;

const CLSID_DestinationList = GUID.parse("{77F10CF0-3DB5-4966-B520-B7C54FD35ED6}");
const IID_ICustomDestinationList = GUID.parse("{6332DEBF-87B5-4670-90C0-5E57B408A49E}");
const CLSID_ShellLink = GUID.parse("{00021401-0000-0000-C000-000000000046}");
const IID_IShellLinkW = GUID.parse("{000214F9-0000-0000-C000-000000000046}");
const IID_IPropertyStore = GUID.parse("{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}");
const IID_IObjectCollection = GUID.parse("{5632B1A4-E38A-400A-928A-D4CD63230295}");
const CLSID_EnumerableObjectCollection = GUID.parse("{2D3468C1-36A7-43B6-AC24-D3F02FD9607A}");
const IID_IObjectArray = GUID.parse("{92CA9DCD-5622-4BBA-A805-5E9F541BD8C9}");
const IID_IUnknown = GUID.parse("{00000000-0000-0000-C000-000000000046}");

/// PKEY_Title: {F29F85E0-4FF9-1068-AB91-08002B27B3D9}, pid 2.
const PKEY_Title = extern struct {
    fmtid: GUID,
    pid: u32,
};
const pkey_title: PKEY_Title = .{
    .fmtid = GUID.parse("{F29F85E0-4FF9-1068-AB91-08002B27B3D9}"),
    .pid = 2,
};

const VT_LPWSTR: u16 = 31;

const PROPVARIANT = extern struct {
    vt: u16,
    r1: u16 = 0,
    r2: u16 = 0,
    r3: u16 = 0,
    val: extern union {
        pwszVal: [*:0]const u16,
        pad: [16]u8,
    },
};

const CLSCTX_INPROC_SERVER: u32 = 1;

extern "ole32" fn CoCreateInstance(
    rclsid: *const GUID,
    pUnkOuter: ?*anyopaque,
    dwClsContext: u32,
    riid: *const GUID,
    ppv: *?*anyopaque,
) callconv(.winapi) HRESULT;

const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
    Release: *const fn (*anyopaque) callconv(.winapi) u32,
};

const ICustomDestinationListVtbl = extern struct {
    base: IUnknownVtbl,
    SetAppID: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
    BeginList: *const fn (*anyopaque, *u32, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AppendCategory: *const fn (*anyopaque, [*:0]const u16, *anyopaque) callconv(.winapi) HRESULT,
    AppendKnownCategory: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
    AddUserTasks: *const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT,
    CommitList: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    GetRemovedDestinations: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    DeleteList: *const fn (*anyopaque, ?[*:0]const u16) callconv(.winapi) HRESULT,
    AbortList: *const fn (*anyopaque) callconv(.winapi) HRESULT,
};

const IShellLinkWVtbl = extern struct {
    base: IUnknownVtbl,
    GetPath: *const anyopaque,
    GetIDList: *const anyopaque,
    SetIDList: *const anyopaque,
    GetDescription: *const anyopaque,
    SetDescription: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
    GetWorkingDirectory: *const anyopaque,
    SetWorkingDirectory: *const anyopaque,
    GetArguments: *const anyopaque,
    SetArguments: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
    GetHotkey: *const anyopaque,
    SetHotkey: *const anyopaque,
    GetShowCmd: *const anyopaque,
    SetShowCmd: *const anyopaque,
    GetIconLocation: *const anyopaque,
    SetIconLocation: *const fn (*anyopaque, [*:0]const u16, i32) callconv(.winapi) HRESULT,
    SetRelativePath: *const anyopaque,
    Resolve: *const anyopaque,
    SetPath: *const fn (*anyopaque, [*:0]const u16) callconv(.winapi) HRESULT,
};

const IPropertyStoreVtbl = extern struct {
    base: IUnknownVtbl,
    GetCount: *const anyopaque,
    GetAt: *const anyopaque,
    GetValue: *const anyopaque,
    SetValue: *const fn (*anyopaque, *const PKEY_Title, *const PROPVARIANT) callconv(.winapi) HRESULT,
    Commit: *const fn (*anyopaque) callconv(.winapi) HRESULT,
};

const IObjectCollectionVtbl = extern struct {
    base: IUnknownVtbl,
    // IObjectArray
    GetCount: *const anyopaque,
    GetAt: *const anyopaque,
    // IObjectCollection
    AddObject: *const fn (*anyopaque, *anyopaque) callconv(.winapi) HRESULT,
    AddFromArray: *const anyopaque,
    RemoveObjectAt: *const anyopaque,
    Clear: *const anyopaque,
};

fn comVtbl(comptime V: type, obj: *anyopaque) *const V {
    const holder: *extern struct { vtbl: *const V } = @ptrCast(@alignCast(obj));
    return holder.vtbl;
}

fn release(obj: *anyopaque) void {
    _ = comVtbl(IUnknownVtbl, obj).Release(obj);
}

const Task = struct {
    title: [:0]const u16,
    /// Arguments passed to paramux.com; empty launches the GUI.
    arguments: [:0]const u16,
};

const tasks = [_]Task{
    .{
        .title = std.unicode.utf8ToUtf16LeStringLiteral("New Window"),
        .arguments = std.unicode.utf8ToUtf16LeStringLiteral(""),
    },
    .{
        .title = std.unicode.utf8ToUtf16LeStringLiteral("Settings"),
        .arguments = std.unicode.utf8ToUtf16LeStringLiteral("perform-action open_config"),
    },
    .{
        .title = std.unicode.utf8ToUtf16LeStringLiteral("Attention Inbox"),
        .arguments = std.unicode.utf8ToUtf16LeStringLiteral("perform-action attention_inbox"),
    },
};

/// Register the paramux jump-list tasks. Best-effort: any failure is
/// swallowed after logging — the jump list is chrome, not correctness.
/// Requires an initialized COM apartment on the calling thread.
pub fn register(launcher_path_w: [:0]const u16, icon_path_w: [:0]const u16) void {
    registerInner(launcher_path_w, icon_path_w) catch |err| {
        std.log.scoped(.win32).info("jump list registration skipped err={}", .{err});
    };
}

fn registerInner(launcher_path_w: [:0]const u16, icon_path_w: [:0]const u16) !void {
    var raw: ?*anyopaque = null;
    if (CoCreateInstance(&CLSID_DestinationList, null, CLSCTX_INPROC_SERVER, &IID_ICustomDestinationList, &raw) < 0)
        return error.DestinationListUnavailable;
    const list = raw orelse return error.DestinationListUnavailable;
    defer release(list);
    const list_vtbl = comVtbl(ICustomDestinationListVtbl, list);

    var min_slots: u32 = 0;
    var removed: ?*anyopaque = null;
    if (list_vtbl.BeginList(list, &min_slots, &IID_IObjectArray, &removed) < 0)
        return error.BeginListFailed;
    if (removed) |r| release(r);

    var col_raw: ?*anyopaque = null;
    if (CoCreateInstance(&CLSID_EnumerableObjectCollection, null, CLSCTX_INPROC_SERVER, &IID_IObjectCollection, &col_raw) < 0) {
        _ = list_vtbl.AbortList(list);
        return error.CollectionUnavailable;
    }
    const collection = col_raw.?;
    defer release(collection);
    const col_vtbl = comVtbl(IObjectCollectionVtbl, collection);

    for (tasks) |task| {
        const link = try createTaskLink(launcher_path_w, icon_path_w, task);
        defer release(link);
        if (col_vtbl.AddObject(collection, link) < 0) {
            _ = list_vtbl.AbortList(list);
            return error.AddObjectFailed;
        }
    }

    if (list_vtbl.AddUserTasks(list, collection) < 0) {
        _ = list_vtbl.AbortList(list);
        return error.AddUserTasksFailed;
    }
    if (list_vtbl.CommitList(list) < 0) return error.CommitFailed;
}

fn createTaskLink(
    launcher_path_w: [:0]const u16,
    icon_path_w: [:0]const u16,
    task: Task,
) !*anyopaque {
    var raw: ?*anyopaque = null;
    if (CoCreateInstance(&CLSID_ShellLink, null, CLSCTX_INPROC_SERVER, &IID_IShellLinkW, &raw) < 0)
        return error.ShellLinkUnavailable;
    const link = raw orelse return error.ShellLinkUnavailable;
    errdefer release(link);
    const link_vtbl = comVtbl(IShellLinkWVtbl, link);

    if (link_vtbl.SetPath(link, launcher_path_w.ptr) < 0) return error.SetPathFailed;
    if (link_vtbl.SetArguments(link, task.arguments.ptr) < 0) return error.SetArgumentsFailed;
    _ = link_vtbl.SetIconLocation(link, icon_path_w.ptr, 0);

    // The visible task title travels via the property store's PKEY_Title.
    var store_raw: ?*anyopaque = null;
    if (comVtbl(IUnknownVtbl, link).QueryInterface(link, &IID_IPropertyStore, &store_raw) < 0)
        return error.PropertyStoreUnavailable;
    const store = store_raw.?;
    defer release(store);
    const store_vtbl = comVtbl(IPropertyStoreVtbl, store);
    const value: PROPVARIANT = .{ .vt = VT_LPWSTR, .val = .{ .pwszVal = task.title.ptr } };
    if (store_vtbl.SetValue(store, &pkey_title, &value) < 0) return error.SetTitleFailed;
    if (store_vtbl.Commit(store) < 0) return error.CommitTitleFailed;

    return link;
}

test "jump list task table is well-formed" {
    try std.testing.expectEqual(@as(usize, 3), tasks.len);
    for (tasks) |task| {
        try std.testing.expect(task.title.len > 0);
    }
}
