//! Windows Explorer "Open in Paramux" context-menu integration.
//!
//! Registers per-user (HKCU, no elevation) shell verbs so right-clicking a
//! folder, a folder background, or a drive offers "Open in Paramux", which
//! launches `paramux.exe --working-directory="<folder>\."`. The launch rides
//! the normal single-instance forward: if a primary instance is running the
//! folder opens as a new window inside it; otherwise a fresh instance starts
//! there.
//!
//! Three registration surfaces write the same keys:
//!   * The in-app Settings window toggle (interactive opt-in/out).
//!   * `install-paramux.ps1` (portable-ZIP install path).
//!   * The Inno Setup installer ([Registry] section, uninstall-aware).
//!
//! The command embeds an absolute exe path, so a moved portable folder would
//! leave a dead verb behind. `refreshIfStale` runs at app startup and only
//! rewrites the keys when the user already opted in but the recorded exe path
//! no longer matches the running one — it never registers from scratch, so
//! merely launching paramux does not touch the Explorer menu.
//!
//! The working-directory argument uses the `"%V\."` idiom (same trick as
//! Windows Terminal): a bare `"%V"` breaks for root paths because `C:\"`
//! makes the backslash escape the closing quote; the `\.` suffix keeps the
//! quote intact and normalizes away in path resolution.
//!
//! On Windows 11 these verbs appear under "Show more options" (Shift+F10 or
//! the classic menu); the modern top-level menu requires MSIX packaging with
//! an IExplorerCommand handler, which the unsigned portable distribution
//! deliberately does not have.

const std = @import("std");
const win32_types = @import("win32_types.zig");

const LPCWSTR = win32_types.LPCWSTR;
const DWORD = win32_types.DWORD;
const HKEY = *opaque {};
const REGSAM = u32;

const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
const KEY_WRITE: REGSAM = 0x20006;
const REG_OPTION_NON_VOLATILE: DWORD = 0;
const REG_SZ: DWORD = 1;
const ERROR_SUCCESS: i32 = 0;
const ERROR_FILE_NOT_FOUND: i32 = 2;
const RRF_RT_REG_SZ: DWORD = 0x00000002;

extern "advapi32" fn RegCreateKeyExW(
    hKey: HKEY,
    lpSubKey: LPCWSTR,
    Reserved: DWORD,
    lpClass: ?LPCWSTR,
    dwOptions: DWORD,
    samDesired: REGSAM,
    lpSecurityAttributes: ?*anyopaque,
    phkResult: *HKEY,
    lpdwDisposition: ?*DWORD,
) callconv(.winapi) i32;

extern "advapi32" fn RegSetValueExW(
    hKey: HKEY,
    lpValueName: ?LPCWSTR,
    Reserved: DWORD,
    dwType: DWORD,
    lpData: [*]const u8,
    cbData: DWORD,
) callconv(.winapi) i32;

extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.winapi) i32;

extern "advapi32" fn RegDeleteTreeW(hKey: HKEY, lpSubKey: ?LPCWSTR) callconv(.winapi) i32;

extern "advapi32" fn RegGetValueW(
    hkey: HKEY,
    lpSubKey: ?LPCWSTR,
    lpValue: ?LPCWSTR,
    dwFlags: DWORD,
    pdwType: ?*DWORD,
    pvData: ?*anyopaque,
    pcbData: ?*DWORD,
) callconv(.winapi) i32;

pub const menu_label = "Open in Paramux";

/// The verb keys, relative to HKCU. `Directory` covers right-click on a
/// folder icon, `Directory\Background` the empty space inside an open
/// folder, and `Drive` a drive root in This PC. `%V` resolves to the
/// affected folder for all three.
const verb_subkeys = [_][:0]const u8{
    "Software\\Classes\\Directory\\shell\\Paramux",
    "Software\\Classes\\Directory\\Background\\shell\\Paramux",
    "Software\\Classes\\Drive\\shell\\Paramux",
};

/// The key consulted for status checks; all three are written together, so
/// probing one is representative.
const probe_command_subkey = "Software\\Classes\\Directory\\shell\\Paramux\\command";

pub const Status = enum {
    /// No verb registered.
    not_registered,
    /// Registered and the command points at the running exe.
    registered,
    /// Registered but the command references some other exe path (moved
    /// portable folder or a different install).
    stale,
};

/// Shell-verb command line for a given exe path. See the module docs for
/// why the argument is `"%V\."` and not `"%V"`.
pub fn buildCommand(alloc: std.mem.Allocator, exe_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "\"{s}\" --working-directory=\"%V\\.\"", .{exe_path});
}

/// Icon registry value for a given exe path: quoted, with the icon-group
/// index, so paths containing commas or spaces stay parseable.
fn buildIconValue(alloc: std.mem.Allocator, exe_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "\"{s}\",0", .{exe_path});
}

/// Whether a registered command string launches `exe_path`. Used for stale
/// detection, so it only matches an exact quoted-prefix occurrence.
pub fn commandMatchesExe(command: []const u8, exe_path: []const u8) bool {
    if (command.len < exe_path.len + 2) return false;
    if (command[0] != '"') return false;
    if (!std.ascii.eqlIgnoreCase(command[1 .. 1 + exe_path.len], exe_path)) return false;
    return command[1 + exe_path.len] == '"';
}

/// The exe the verbs should launch: always the GUI `paramux.exe`. When the
/// caller is the console launcher (`paramux.com`, e.g. `paramux +install`),
/// the sibling `paramux.exe` is used so Explorer launches never flash a
/// console window. Falls back to the running image if no sibling exists
/// (unusual dev layouts). Caller owns the result.
pub fn registrationTargetPath(alloc: std.mem.Allocator) ![]u8 {
    const self_path = try std.fs.selfExePathAlloc(alloc);
    if (std.ascii.endsWithIgnoreCase(self_path, "\\paramux.exe")) return self_path;
    defer alloc.free(self_path);

    const dir = std.fs.path.dirname(self_path) orelse return error.FileNotFound;
    const gui_path = try std.fs.path.join(alloc, &.{ dir, "paramux.exe" });
    errdefer alloc.free(gui_path);
    try std.fs.accessAbsolute(gui_path, .{});
    return gui_path;
}

/// Write all three verb keys pointing at the GUI exe. Failures are
/// advisory (logged, best-effort): Explorer integration is never worth
/// blocking the app over.
pub fn register(alloc: std.mem.Allocator) void {
    const exe_path = registrationTargetPath(alloc) catch |err| {
        std.log.warn("explorer menu: registration target unavailable err={}", .{err});
        return;
    };
    defer alloc.free(exe_path);
    registerForExe(alloc, exe_path);
}

fn registerForExe(alloc: std.mem.Allocator, exe_path: []const u8) void {
    const command = buildCommand(alloc, exe_path) catch return;
    defer alloc.free(command);
    const icon = buildIconValue(alloc, exe_path) catch return;
    defer alloc.free(icon);

    const label_w = std.unicode.utf8ToUtf16LeStringLiteral(menu_label);
    const command_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, command) catch return;
    defer alloc.free(command_w);
    const icon_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, icon) catch return;
    defer alloc.free(icon_w);

    for (verb_subkeys) |subkey| {
        const subkey_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey) catch return;
        defer alloc.free(subkey_w);

        var verb_key: HKEY = undefined;
        const verb_rc = RegCreateKeyExW(
            HKEY_CURRENT_USER,
            subkey_w,
            0,
            null,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            null,
            &verb_key,
            null,
        );
        if (verb_rc != ERROR_SUCCESS) {
            std.log.warn("explorer menu: create {s} failed rc={d}", .{ subkey, verb_rc });
            continue;
        }
        {
            defer _ = RegCloseKey(verb_key);
            // Default value = menu label; Icon = the exe's embedded icon.
            _ = writeRegSz(verb_key, null, label_w);
            _ = writeRegSz(verb_key, std.unicode.utf8ToUtf16LeStringLiteral("Icon"), icon_w);
        }

        const command_subkey = std.fmt.allocPrint(alloc, "{s}\\command", .{subkey}) catch return;
        defer alloc.free(command_subkey);
        const command_subkey_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, command_subkey) catch return;
        defer alloc.free(command_subkey_w);

        var command_key: HKEY = undefined;
        const cmd_rc = RegCreateKeyExW(
            HKEY_CURRENT_USER,
            command_subkey_w,
            0,
            null,
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            null,
            &command_key,
            null,
        );
        if (cmd_rc != ERROR_SUCCESS) {
            std.log.warn("explorer menu: create {s} failed rc={d}", .{ command_subkey, cmd_rc });
            continue;
        }
        defer _ = RegCloseKey(command_key);
        _ = writeRegSz(command_key, null, command_w);
    }
    std.log.info("explorer menu: registered 'Open in Paramux' for {s}", .{exe_path});
}

/// Delete all three verb keys. Missing keys are fine (idempotent).
pub fn unregister(alloc: std.mem.Allocator) void {
    for (verb_subkeys) |subkey| {
        const subkey_w = std.unicode.utf8ToUtf16LeAllocZ(alloc, subkey) catch return;
        defer alloc.free(subkey_w);
        const rc = RegDeleteTreeW(HKEY_CURRENT_USER, subkey_w);
        if (rc != ERROR_SUCCESS and rc != ERROR_FILE_NOT_FOUND) {
            std.log.warn("explorer menu: delete {s} failed rc={d}", .{ subkey, rc });
        }
    }
}

/// Read the registered command (if any) and classify it against the running
/// exe path.
pub fn status(alloc: std.mem.Allocator) Status {
    var buf: [1024]u16 = undefined;
    var cb: DWORD = @sizeOf(@TypeOf(buf));
    const rc = RegGetValueW(
        HKEY_CURRENT_USER,
        std.unicode.utf8ToUtf16LeStringLiteral(probe_command_subkey),
        null,
        RRF_RT_REG_SZ,
        null,
        &buf,
        &cb,
    );
    if (rc != ERROR_SUCCESS) return .not_registered;

    // cb counts bytes including the terminator; recover the u16 length.
    const wide_len = @min(buf.len, cb / 2);
    const wide = std.mem.sliceTo(buf[0..wide_len], 0);
    const command = std.unicode.utf16LeToUtf8Alloc(alloc, wide) catch return .stale;
    defer alloc.free(command);

    const exe_path = registrationTargetPath(alloc) catch return .stale;
    defer alloc.free(exe_path);

    return if (commandMatchesExe(command, exe_path)) .registered else .stale;
}

/// Startup hook: if the user opted in previously but the exe has moved,
/// rewrite the keys to the current path. Never registers from scratch.
pub fn refreshIfStale(alloc: std.mem.Allocator) void {
    if (status(alloc) != .stale) return;
    std.log.info("explorer menu: registered exe path is stale; refreshing", .{});
    register(alloc);
}

fn writeRegSz(hkey: HKEY, value_name: ?LPCWSTR, value: [:0]const u16) i32 {
    return RegSetValueExW(
        hkey,
        value_name,
        0,
        REG_SZ,
        @ptrCast(value.ptr),
        @intCast((value.len + 1) * @sizeOf(u16)),
    );
}

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

test "explorer menu: buildCommand quotes exe and neutralizes root backslash" {
    const cmd = try buildCommand(testing.allocator, "C:\\Tools\\paramux\\paramux.exe");
    defer testing.allocator.free(cmd);
    try testing.expectEqualStrings(
        "\"C:\\Tools\\paramux\\paramux.exe\" --working-directory=\"%V\\.\"",
        cmd,
    );
}

test "explorer menu: buildIconValue quotes and appends icon index" {
    const icon = try buildIconValue(testing.allocator, "C:\\Program Files\\paramux\\paramux.exe");
    defer testing.allocator.free(icon);
    try testing.expectEqualStrings("\"C:\\Program Files\\paramux\\paramux.exe\",0", icon);
}

test "explorer menu: commandMatchesExe accepts exact quoted prefix" {
    const exe = "C:\\Tools\\paramux\\paramux.exe";
    const cmd = try buildCommand(testing.allocator, exe);
    defer testing.allocator.free(cmd);
    try testing.expect(commandMatchesExe(cmd, exe));
}

test "explorer menu: commandMatchesExe is case-insensitive on the path" {
    try testing.expect(commandMatchesExe(
        "\"c:\\tools\\PARAMUX\\paramux.EXE\" --working-directory=\"%V\\.\"",
        "C:\\Tools\\paramux\\paramux.exe",
    ));
}

test "explorer menu: commandMatchesExe rejects other exe or malformed command" {
    const exe = "C:\\Tools\\paramux\\paramux.exe";
    try testing.expect(!commandMatchesExe(
        "\"C:\\Elsewhere\\paramux.exe\" --working-directory=\"%V\\.\"",
        exe,
    ));
    // Prefix-only match must not count (a longer path sharing the prefix).
    try testing.expect(!commandMatchesExe(
        "\"C:\\Tools\\paramux\\paramux.exe.bak\" --working-directory=\"%V\\.\"",
        exe,
    ));
    try testing.expect(!commandMatchesExe("paramux.exe", exe));
    try testing.expect(!commandMatchesExe("", exe));
}
