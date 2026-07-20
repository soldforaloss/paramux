const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const build_config = @import("../build_config.zig");
const github_releases = @import("../update/github_releases.zig");

pub const Options = struct {
    /// Only report whether an update is available; change nothing.
    check: bool = false,

    /// Restore the previous version's files (kept as `*.old` by the
    /// last update). The window closes when the next update sweeps.
    rollback: bool = false,

    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return actionpkg.help_error;
    }
};

/// The `update` command updates this portable Paramux install in place:
///
///   1. queries GitHub for the newest release (prereleases included)
///   2. downloads the portable ZIP plus its checksum file and verifies the
///      SHA-256 digest before touching anything
///   3. swaps the new files into the folder containing this executable
///      (existing files are renamed to `*.old` first, so the running
///      `paramux.com` can update itself; leftovers are swept on the next
///      run)
///
/// The update is refused while a paramux window is running from this
/// folder — close the windows first. Configuration under
/// `%LOCALAPPDATA%\paramux` is never touched. `--check` prints whether an
/// update is available without changing anything.
///
/// PATH and Explorer integration keep working because the folder path does
/// not change; there is nothing to re-run after updating.
///
/// Available since: 1.3.0
pub fn run(alloc: Allocator) !u8 {
    var opts: Options = .{};
    defer opts.deinit();

    {
        var iter = try args.argsIterator(alloc);
        defer iter.deinit();
        try args.parse(Options, alloc, &opts, &iter);
    }

    if (comptime builtin.os.tag != .windows) {
        std.debug.print("update is a Windows lifecycle command.\n", .{});
        return 1;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    const exe_dir = std.fs.selfExeDirPathAlloc(alloc) catch {
        try stdout.print("error: could not resolve the paramux install folder.\n", .{});
        return 1;
    };
    defer alloc.free(exe_dir);

    // Rollback restores the previous files (kept as `*.old` by the
    // last update) and must run BEFORE the sweep would destroy them.
    // The window closes at the next `paramux update` invocation.
    if (opts.rollback) {
        const restored = rollbackOldFiles(exe_dir);
        if (restored == 0) {
            try stdout.print("Nothing to roll back: no *.old files remain (the window closes when the next update sweeps them).\n", .{});
            return 1;
        }
        try stdout.print("Rolled back {d} file(s) to the previous version. Restart paramux.\n", .{restored});
        return 0;
    }

    // Sweep *.old leftovers from a previous self-update; failures are
    // fine (a straggler process may still hold one).
    sweepOldFiles(exe_dir);

    try stdout.print("Current version: {s}\n", .{build_config.version_string});
    try stdout.print("Checking {s} ...\n", .{github_releases.releases_url});
    try stdout.flush();

    var release = github_releases.fetchLatestPortableRelease(alloc) catch |err| {
        try stdout.print("error: release check failed ({s}).\n", .{@errorName(err)});
        return 1;
    };
    defer release.deinit(alloc);

    try stdout.print("Latest release : {s}\n", .{release.version_text});

    const latest = std.SemanticVersion.parse(release.version_text) catch {
        try stdout.print("error: latest release has an unparseable version.\n", .{});
        return 1;
    };
    if (build_config.version.order(latest) != .lt) {
        try stdout.print("Already up to date.\n", .{});
        return 0;
    }

    if (opts.check) {
        try stdout.print(
            "Update available: {s} -> {s}\nRelease notes: {s}\nRun `paramux update` to apply it.\n",
            .{ build_config.version_string, release.version_text, release.release_url },
        );
        return 0;
    }

    // Refuse while the GUI runs from this install: swapped-in files
    // would only half-apply and the restart story gets confusing.
    if (paramuxGuiRunningIn(alloc, exe_dir)) {
        try stdout.print(
            "error: paramux is running from this folder. Close its windows, then run `paramux update` again.\n",
            .{},
        );
        return 1;
    }

    const state_path = github_releases.defaultStatePath(alloc) catch {
        try stdout.print("error: could not resolve the update staging directory.\n", .{});
        return 1;
    };
    defer alloc.free(state_path);

    try stdout.print("Release notes: {s}\n", .{release.release_url});
    try stdout.print("Downloading and verifying {s} ...\n", .{release.version_text});
    try stdout.flush();
    var staged = github_releases.stagePortableUpdate(alloc, state_path, &release) catch |err| {
        try stdout.print("error: download/verify failed ({s}).\n", .{@errorName(err)});
        return 1;
    };
    defer staged.deinit(alloc);
    try stdout.print("SHA-256 verified: {s}\n", .{staged.sha256_hex});

    try stdout.print("Applying update ...\n", .{});
    try stdout.flush();
    applyPortableZip(alloc, staged.installer_path, exe_dir) catch |err| {
        try stdout.print(
            "error: applying the update failed ({s}). The install may be partially updated; re-run `paramux update` or extract the ZIP manually:\n  {s}\n",
            .{ @errorName(err), staged.installer_path },
        );
        return 1;
    };

    // Best-effort immediate sweep; the running paramux.com keeps its own
    // image locked as .old until the next invocation sweeps it.
    sweepOldFiles(exe_dir);

    try stdout.print(
        "Updated {s} -> {s}. New windows use the new version; `paramux version` confirms it.\n",
        .{ build_config.version_string, release.version_text },
    );
    return 0;
}

/// Extract the verified portable ZIP over `install_dir`. The archive
/// contains a top-level `paramux/` folder; entries are re-rooted below it.
/// Existing destination files are renamed to `<name>.old` first so files
/// locked for execution (the running `paramux.com`) can still be replaced.
fn applyPortableZip(alloc: Allocator, zip_path: []const u8, install_dir: []const u8) !void {
    // Extract into a fresh staging directory next to the downloaded ZIP.
    const stage_root = try std.fmt.allocPrint(alloc, "{s}.extracted", .{zip_path});
    defer alloc.free(stage_root);
    std.fs.deleteTreeAbsolute(stage_root) catch {};
    try std.fs.cwd().makePath(stage_root);

    {
        var zip_file = try std.fs.openFileAbsolute(zip_path, .{});
        defer zip_file.close();
        var read_buf: [64 * 1024]u8 = undefined;
        var reader = zip_file.reader(&read_buf);
        var stage_dir = try std.fs.openDirAbsolute(stage_root, .{});
        defer stage_dir.close();
        // The packaging pipeline zips with .NET on Windows, whose entry
        // names historically use backslashes; tolerate both.
        try std.zip.extract(stage_dir, &reader, .{ .allow_backslashes = true });
    }

    // The payload root: <stage>/paramux. Fall back to the stage root
    // itself if a future package drops the wrapper folder.
    const payload_root = blk: {
        const wrapped = try std.fs.path.join(alloc, &.{ stage_root, "paramux" });
        errdefer alloc.free(wrapped);
        std.fs.accessAbsolute(wrapped, .{}) catch {
            alloc.free(wrapped);
            break :blk try alloc.dupe(u8, stage_root);
        };
        break :blk wrapped;
    };
    defer alloc.free(payload_root);

    try swapTree(alloc, payload_root, install_dir);

    // Drop the staging tree; the verified ZIP is kept for re-runs.
    std.fs.deleteTreeAbsolute(stage_root) catch {};
}

/// Recursively move every file from `src_root` into `dest_root`,
/// renaming pre-existing destination files to `*.old` before the move.
fn swapTree(alloc: Allocator, src_root: []const u8, dest_root: []const u8) !void {
    var src_dir = try std.fs.openDirAbsolute(src_root, .{ .iterate = true });
    defer src_dir.close();

    var walker = try src_dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const dest_path = try std.fs.path.join(alloc, &.{ dest_root, entry.path });
        defer alloc.free(dest_path);

        switch (entry.kind) {
            .directory => {
                std.fs.cwd().makePath(dest_path) catch |err| return err;
            },
            .file => {
                const src_path = try std.fs.path.join(alloc, &.{ src_root, entry.path });
                defer alloc.free(src_path);

                if (std.fs.path.dirname(dest_path)) |parent| {
                    std.fs.cwd().makePath(parent) catch {};
                }

                // Windows allows renaming a file whose image is executing,
                // but not overwriting it: move the old file aside first.
                if (std.fs.accessAbsolute(dest_path, .{})) |_| {
                    const old_path = try std.fmt.allocPrint(alloc, "{s}.old", .{dest_path});
                    defer alloc.free(old_path);
                    std.fs.deleteFileAbsolute(old_path) catch {};
                    try std.fs.renameAbsolute(dest_path, old_path);
                } else |_| {}

                try std.fs.renameAbsolute(src_path, dest_path);
            },
            else => {},
        }
    }
}

/// Delete `*.old` leftovers from previous self-updates, recursively.
/// Best-effort: files still locked by a running process stay for the
/// next sweep.
/// Restore `<name>.old` files over their current counterparts. The
/// running paramux.com's own image stays locked, so its .old survives
/// for the next invocation - which is fine: the restored EXE pair is
/// what matters. Returns how many files were restored.
fn rollbackOldFiles(install_dir: []const u8) usize {
    var dir = std.fs.openDirAbsolute(install_dir, .{ .iterate = true }) catch return 0;
    defer dir.close();
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var walker = dir.walk(fba.allocator()) catch return 0;
    defer walker.deinit();
    var restored: usize = 0;
    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".old")) continue;
        const current = entry.path[0 .. entry.path.len - ".old".len];
        dir.deleteFile(current) catch {};
        dir.rename(entry.path, current) catch continue;
        restored += 1;
    }
    return restored;
}

fn sweepOldFiles(install_dir: []const u8) void {
    var dir = std.fs.openDirAbsolute(install_dir, .{ .iterate = true }) catch return;
    defer dir.close();
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var walker = dir.walk(fba.allocator()) catch return;
    defer walker.deinit();
    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".old")) continue;
        dir.deleteFile(entry.path) catch {};
    }
}

// ---------------------------------------------------------------------------
// Running-instance detection
// ---------------------------------------------------------------------------

const win = struct {
    const HANDLE = *anyopaque;
    const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));
    const TH32CS_SNAPPROCESS: u32 = 0x2;
    const PROCESS_QUERY_LIMITED_INFORMATION: u32 = 0x1000;

    const PROCESSENTRY32W = extern struct {
        dwSize: u32,
        cntUsage: u32,
        th32ProcessID: u32,
        th32DefaultHeapID: usize,
        th32ModuleID: u32,
        cntThreads: u32,
        th32ParentProcessID: u32,
        pcPriClassBase: i32,
        dwFlags: u32,
        szExeFile: [260]u16,
    };

    extern "kernel32" fn CreateToolhelp32Snapshot(dwFlags: u32, th32ProcessID: u32) callconv(.winapi) HANDLE;
    extern "kernel32" fn Process32FirstW(hSnapshot: HANDLE, lppe: *PROCESSENTRY32W) callconv(.winapi) i32;
    extern "kernel32" fn Process32NextW(hSnapshot: HANDLE, lppe: *PROCESSENTRY32W) callconv(.winapi) i32;
    extern "kernel32" fn OpenProcess(dwDesiredAccess: u32, bInheritHandle: i32, dwProcessId: u32) callconv(.winapi) ?HANDLE;
    extern "kernel32" fn QueryFullProcessImageNameW(hProcess: HANDLE, dwFlags: u32, lpExeName: [*]u16, lpdwSize: *u32) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) i32;
};

/// True when a `paramux.exe` GUI process is running whose image lives in
/// `install_dir`. The CLI's own process (`paramux.com`) is excluded by
/// image name, so `paramux update` can update the folder it runs from.
fn paramuxGuiRunningIn(alloc: Allocator, install_dir: []const u8) bool {
    const snapshot = win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0);
    if (snapshot == win.INVALID_HANDLE_VALUE) return false;
    defer _ = win.CloseHandle(snapshot);

    var entry: win.PROCESSENTRY32W = undefined;
    entry.dwSize = @sizeOf(win.PROCESSENTRY32W);
    if (win.Process32FirstW(snapshot, &entry) == 0) return false;

    const self_pid = std.os.windows.GetCurrentProcessId();
    while (true) {
        blk: {
            if (entry.th32ProcessID == self_pid) break :blk;
            const name = std.mem.sliceTo(&entry.szExeFile, 0);
            if (!utf16EqlAsciiIgnoreCase(name, "paramux.exe")) break :blk;

            const proc = win.OpenProcess(win.PROCESS_QUERY_LIMITED_INFORMATION, 0, entry.th32ProcessID) orelse break :blk;
            defer _ = win.CloseHandle(proc);
            var path_buf: [std.fs.max_path_bytes]u16 = undefined;
            var len: u32 = path_buf.len;
            if (win.QueryFullProcessImageNameW(proc, 0, &path_buf, &len) == 0) break :blk;
            const image_utf8 = std.unicode.utf16LeToUtf8Alloc(alloc, path_buf[0..len]) catch break :blk;
            defer alloc.free(image_utf8);
            const image_dir = std.fs.path.dirname(image_utf8) orelse break :blk;
            if (std.ascii.eqlIgnoreCase(
                std.mem.trimRight(u8, image_dir, "\\/"),
                std.mem.trimRight(u8, install_dir, "\\/"),
            )) return true;
        }
        if (win.Process32NextW(snapshot, &entry) == 0) return false;
    }
}

fn utf16EqlAsciiIgnoreCase(a: []const u16, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |wc, c| {
        if (wc > 0x7F) return false;
        if (std.ascii.toLower(@intCast(wc)) != std.ascii.toLower(c)) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "update: utf16 ascii comparison" {
    const wide = std.unicode.utf8ToUtf16LeStringLiteral("PaRaMuX.exe");
    try std.testing.expect(utf16EqlAsciiIgnoreCase(wide, "paramux.exe"));
    try std.testing.expect(!utf16EqlAsciiIgnoreCase(wide, "paramux.com"));
}

test "update: swapTree moves files aside and in place" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(root);

    const src = try std.fs.path.join(alloc, &.{ root, "src", "sub" });
    defer alloc.free(src);
    const dest = try std.fs.path.join(alloc, &.{ root, "dest" });
    defer alloc.free(dest);
    try std.fs.cwd().makePath(src);
    try std.fs.cwd().makePath(dest);

    // New payload: sub/a.txt = "new"; destination already has sub/a.txt = "old".
    {
        const src_file = try std.fs.path.join(alloc, &.{ src, "a.txt" });
        defer alloc.free(src_file);
        try std.fs.cwd().writeFile(.{ .sub_path = src_file, .data = "new" });
        const dest_sub = try std.fs.path.join(alloc, &.{ dest, "sub" });
        defer alloc.free(dest_sub);
        try std.fs.cwd().makePath(dest_sub);
        const dest_file = try std.fs.path.join(alloc, &.{ dest_sub, "a.txt" });
        defer alloc.free(dest_file);
        try std.fs.cwd().writeFile(.{ .sub_path = dest_file, .data = "old" });
    }

    const src_root = try std.fs.path.join(alloc, &.{ root, "src" });
    defer alloc.free(src_root);
    try swapTree(alloc, src_root, dest);

    // New content in place, old preserved as .old.
    {
        const dest_file = try std.fs.path.join(alloc, &.{ dest, "sub", "a.txt" });
        defer alloc.free(dest_file);
        const contents = try std.fs.cwd().readFileAlloc(alloc, dest_file, 64);
        defer alloc.free(contents);
        try std.testing.expectEqualStrings("new", contents);

        const old_file = try std.fs.path.join(alloc, &.{ dest, "sub", "a.txt.old" });
        defer alloc.free(old_file);
        const old_contents = try std.fs.cwd().readFileAlloc(alloc, old_file, 64);
        defer alloc.free(old_contents);
        try std.testing.expectEqualStrings("old", old_contents);
    }
}
