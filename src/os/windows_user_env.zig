//! Per-user environment editing for the CLI lifecycle verbs
//! (`+install` / `+uninstall`): the user PATH list and named user
//! environment variables, stored under `HKCU\Environment`, plus the
//! `WM_SETTINGCHANGE` broadcast that tells running shells/Explorer to
//! re-read them.
//!
//! Semantics match `install-paramux.ps1`: PATH entries are compared
//! case-insensitively and edits never touch unrelated entries; values are
//! written as REG_SZ (matching what the PowerShell helper produces via
//! [Environment]::SetEnvironmentVariable). The pure PATH-list helpers are
//! split from the registry externs so they unit-test without a registry.

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.windows_user_env);

// ---------------------------------------------------------------------------
// Pure PATH-list helpers (unit-tested)
// ---------------------------------------------------------------------------

/// Whether `path_value` (a ";"-separated PATH string) already contains
/// `dir`, ignoring case and a trailing backslash difference.
pub fn pathContains(path_value: []const u8, dir: []const u8) bool {
    var it = std.mem.splitScalar(u8, path_value, ';');
    while (it.next()) |raw| {
        if (pathEntryEql(raw, dir)) return true;
    }
    return false;
}

/// PATH entry equality: case-insensitive, empty-safe, tolerant of one
/// trailing path separator on either side.
fn pathEntryEql(a: []const u8, b: []const u8) bool {
    const ta = std.mem.trimRight(u8, std.mem.trim(u8, a, " \t"), "\\/");
    const tb = std.mem.trimRight(u8, std.mem.trim(u8, b, " \t"), "\\/");
    if (ta.len == 0 or tb.len == 0) return ta.len == tb.len;
    return std.ascii.eqlIgnoreCase(ta, tb);
}

/// New PATH string with `dir` appended (unchanged if already present).
/// Caller owns the result.
pub fn pathWithDir(alloc: Allocator, path_value: []const u8, dir: []const u8) ![]u8 {
    if (pathContains(path_value, dir)) return alloc.dupe(u8, path_value);
    const trimmed = std.mem.trimRight(u8, path_value, ";");
    if (trimmed.len == 0) return alloc.dupe(u8, dir);
    return std.fmt.allocPrint(alloc, "{s};{s}", .{ trimmed, dir });
}

/// New PATH string with every entry equal to `dir` removed. Other entries
/// keep their exact text and order. Caller owns the result.
pub fn pathWithoutDir(alloc: Allocator, path_value: []const u8, dir: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(alloc);
    var first = true;
    var it = std.mem.splitScalar(u8, path_value, ';');
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        if (pathEntryEql(raw, dir)) continue;
        if (!first) try out.append(alloc, ';');
        try out.appendSlice(alloc, raw);
        first = false;
    }
    return out.toOwnedSlice(alloc);
}

// ---------------------------------------------------------------------------
// Registry + broadcast (Windows only)
// ---------------------------------------------------------------------------

const win = struct {
    const HKEY = *opaque {};
    const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
    const KEY_READ: u32 = 0x20019;
    const KEY_WRITE: u32 = 0x20006;
    const REG_SZ: u32 = 1;
    const RRF_RT_REG_SZ: u32 = 0x00000002;
    const RRF_RT_REG_EXPAND_SZ: u32 = 0x00000004;
    const RRF_NOEXPAND: u32 = 0x10000000;
    const ERROR_SUCCESS: i32 = 0;
    const ERROR_FILE_NOT_FOUND: i32 = 2;
    const ERROR_MORE_DATA: i32 = 234;
    const HWND_BROADCAST: usize = 0xffff;
    const WM_SETTINGCHANGE: u32 = 0x001A;
    const SMTO_ABORTIFHUNG: u32 = 0x0002;

    extern "advapi32" fn RegCreateKeyExW(
        hKey: HKEY,
        lpSubKey: [*:0]const u16,
        Reserved: u32,
        lpClass: ?[*:0]const u16,
        dwOptions: u32,
        samDesired: u32,
        lpSecurityAttributes: ?*anyopaque,
        phkResult: *HKEY,
        lpdwDisposition: ?*u32,
    ) callconv(.winapi) i32;
    extern "advapi32" fn RegSetValueExW(
        hKey: HKEY,
        lpValueName: ?[*:0]const u16,
        Reserved: u32,
        dwType: u32,
        lpData: [*]const u8,
        cbData: u32,
    ) callconv(.winapi) i32;
    extern "advapi32" fn RegDeleteValueW(hKey: HKEY, lpValueName: [*:0]const u16) callconv(.winapi) i32;
    extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.winapi) i32;
    extern "advapi32" fn RegGetValueW(
        hkey: HKEY,
        lpSubKey: ?[*:0]const u16,
        lpValue: ?[*:0]const u16,
        dwFlags: u32,
        pdwType: ?*u32,
        pvData: ?*anyopaque,
        pcbData: ?*u32,
    ) callconv(.winapi) i32;
    extern "user32" fn SendMessageTimeoutW(
        hWnd: ?*anyopaque,
        Msg: u32,
        wParam: usize,
        lParam: isize,
        fuFlags: u32,
        uTimeout: u32,
        lpdwResult: ?*usize,
    ) callconv(.winapi) isize;
};

const environment_subkey = std.unicode.utf8ToUtf16LeStringLiteral("Environment");

/// Read a value from `HKCU\Environment` as UTF-8. Returns null when the
/// value does not exist. Caller owns the result.
pub fn readUserEnv(alloc: Allocator, name: []const u8) !?[]u8 {
    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
    defer alloc.free(name_w);

    // Two-call pattern: size query, then read. RRF_NOEXPAND keeps
    // REG_EXPAND_SZ values (like %-references in PATH) verbatim.
    const flags = win.RRF_RT_REG_SZ | win.RRF_RT_REG_EXPAND_SZ | win.RRF_NOEXPAND;
    var cb: u32 = 0;
    const size_rc = win.RegGetValueW(win.HKEY_CURRENT_USER, environment_subkey, name_w, flags, null, null, &cb);
    if (size_rc == win.ERROR_FILE_NOT_FOUND) return null;
    if (size_rc != win.ERROR_SUCCESS and size_rc != win.ERROR_MORE_DATA) return error.RegistryReadFailed;
    if (cb == 0) return try alloc.dupe(u8, "");

    const wide = try alloc.alloc(u16, (cb / 2) + 1);
    defer alloc.free(wide);
    var cb2: u32 = @intCast(wide.len * 2);
    const rc = win.RegGetValueW(win.HKEY_CURRENT_USER, environment_subkey, name_w, flags, null, wide.ptr, &cb2);
    if (rc != win.ERROR_SUCCESS) return error.RegistryReadFailed;
    const span = std.mem.sliceTo(wide[0 .. cb2 / 2], 0);
    return try std.unicode.utf16LeToUtf8Alloc(alloc, span);
}

/// Write a REG_SZ value into `HKCU\Environment`.
pub fn writeUserEnv(alloc: Allocator, name: []const u8, value: []const u8) !void {
    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
    defer alloc.free(name_w);
    const value_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, value);
    defer alloc.free(value_w);

    var hkey: win.HKEY = undefined;
    const open_rc = win.RegCreateKeyExW(win.HKEY_CURRENT_USER, environment_subkey, 0, null, 0, win.KEY_WRITE, null, &hkey, null);
    if (open_rc != win.ERROR_SUCCESS) return error.RegistryWriteFailed;
    defer _ = win.RegCloseKey(hkey);

    const rc = win.RegSetValueExW(
        hkey,
        name_w,
        0,
        win.REG_SZ,
        @ptrCast(value_w.ptr),
        @intCast((value_w.len + 1) * 2),
    );
    if (rc != win.ERROR_SUCCESS) return error.RegistryWriteFailed;
}

/// Delete a value from `HKCU\Environment`. Missing values are fine.
pub fn deleteUserEnv(alloc: Allocator, name: []const u8) !void {
    const name_w = try std.unicode.utf8ToUtf16LeAllocZ(alloc, name);
    defer alloc.free(name_w);

    var hkey: win.HKEY = undefined;
    const open_rc = win.RegCreateKeyExW(win.HKEY_CURRENT_USER, environment_subkey, 0, null, 0, win.KEY_WRITE, null, &hkey, null);
    if (open_rc != win.ERROR_SUCCESS) return error.RegistryWriteFailed;
    defer _ = win.RegCloseKey(hkey);

    const rc = win.RegDeleteValueW(hkey, name_w);
    if (rc != win.ERROR_SUCCESS and rc != win.ERROR_FILE_NOT_FOUND) return error.RegistryWriteFailed;
}

/// Tell running processes the user environment changed (same broadcast
/// `[Environment]::SetEnvironmentVariable` performs). Best-effort.
pub fn broadcastEnvironmentChange() void {
    const env_w = std.unicode.utf8ToUtf16LeStringLiteral("Environment");
    _ = win.SendMessageTimeoutW(
        @ptrFromInt(win.HWND_BROADCAST),
        win.WM_SETTINGCHANGE,
        0,
        @bitCast(@intFromPtr(env_w.ptr)),
        win.SMTO_ABORTIFHUNG,
        2000,
        null,
    );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "user env: pathContains ignores case and trailing separators" {
    try testing.expect(pathContains("C:\\a;C:\\Tools\\Paramux;C:\\b", "c:\\tools\\paramux"));
    try testing.expect(pathContains("C:\\Tools\\Paramux\\", "C:\\Tools\\Paramux"));
    try testing.expect(!pathContains("C:\\Tools\\Paramux2", "C:\\Tools\\Paramux"));
    try testing.expect(!pathContains("", "C:\\Tools\\Paramux"));
}

test "user env: pathWithDir appends once" {
    const alloc = testing.allocator;
    const appended = try pathWithDir(alloc, "C:\\a;C:\\b", "C:\\p");
    defer alloc.free(appended);
    try testing.expectEqualStrings("C:\\a;C:\\b;C:\\p", appended);

    const unchanged = try pathWithDir(alloc, "C:\\a;C:\\P\\", "C:\\p");
    defer alloc.free(unchanged);
    try testing.expectEqualStrings("C:\\a;C:\\P\\", unchanged);

    const from_empty = try pathWithDir(alloc, "", "C:\\p");
    defer alloc.free(from_empty);
    try testing.expectEqualStrings("C:\\p", from_empty);
}

test "user env: pathWithoutDir removes only matching entries" {
    const alloc = testing.allocator;
    const removed = try pathWithoutDir(alloc, "C:\\a;C:\\p;C:\\b;c:\\P\\", "C:\\p");
    defer alloc.free(removed);
    try testing.expectEqualStrings("C:\\a;C:\\b", removed);

    const untouched = try pathWithoutDir(alloc, "C:\\a;C:\\b", "C:\\p");
    defer alloc.free(untouched);
    try testing.expectEqualStrings("C:\\a;C:\\b", untouched);
}
