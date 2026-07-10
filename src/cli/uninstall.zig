const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const internal_os = @import("../os/main.zig");
const build_config = @import("../build_config.zig");
const user_env = @import("../os/windows_user_env.zig");
const explorer_menu = @import("../apprt/win32_explorer_menu.zig");

pub const Options = struct {
    /// Also delete the per-user data directory (config, themes, update
    /// state, IPC token, first-run marker) under `%LOCALAPPDATA%\paramux`.
    purge: bool = false,

    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return actionpkg.help_error;
    }
};

/// The `uninstall` command reverses `paramux install` for the folder
/// containing this executable:
///
///   * removes the folder from the user `PATH`
///   * clears `PARAMUX_HOME` when it points at this folder
///   * removes the Explorer "Open in Paramux" context menu when it points
///     at this executable (a registration owned by a different install is
///     left alone)
///
/// With `--purge` it also deletes the per-user data directory
/// (`%LOCALAPPDATA%\paramux`): configuration, update state, and the IPC
/// token. Without `--purge` your configuration survives a reinstall.
///
/// The install folder itself is left on disk (a running executable cannot
/// delete itself); delete the folder afterwards to finish. Agent-side hook
/// references (for example in Claude Code settings) point into this folder
/// and stop working once it is deleted — remove them from the agent's own
/// settings if you no longer want them listed.
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
        std.debug.print("+uninstall is a Windows lifecycle command.\n", .{});
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

    try stdout.print("Uninstalling paramux from: {s}\n", .{exe_dir});

    var failures: u8 = 0;

    // PATH entry.
    if (removeUserPath(alloc, exe_dir)) |removed| {
        try stdout.print("  PATH          {s}\n", .{if (removed) "removed" else "was not present"});
    } else |err| {
        try stdout.print("  PATH          FAILED ({s})\n", .{@errorName(err)});
        failures += 1;
    }

    // PARAMUX_HOME, only when it points here.
    if (user_env.readUserEnv(alloc, "PARAMUX_HOME")) |maybe_home| {
        if (maybe_home) |home| {
            defer alloc.free(home);
            if (std.ascii.eqlIgnoreCase(std.mem.trimRight(u8, home, "\\/"), std.mem.trimRight(u8, exe_dir, "\\/"))) {
                if (user_env.deleteUserEnv(alloc, "PARAMUX_HOME")) {
                    try stdout.print("  PARAMUX_HOME  cleared\n", .{});
                } else |err| {
                    try stdout.print("  PARAMUX_HOME  FAILED ({s})\n", .{@errorName(err)});
                    failures += 1;
                }
            } else {
                try stdout.print("  PARAMUX_HOME  preserved (points elsewhere: {s})\n", .{home});
            }
        } else {
            try stdout.print("  PARAMUX_HOME  was not set\n", .{});
        }
    } else |err| {
        try stdout.print("  PARAMUX_HOME  FAILED ({s})\n", .{@errorName(err)});
        failures += 1;
    }
    user_env.broadcastEnvironmentChange();

    // Explorer context menu, only when it points at this executable.
    switch (explorer_menu.status(alloc)) {
        .registered => {
            explorer_menu.unregister(alloc);
            try stdout.print("  Explorer menu removed\n", .{});
        },
        .stale => try stdout.print("  Explorer menu preserved (registered to a different install)\n", .{}),
        .not_registered => try stdout.print("  Explorer menu was not registered\n", .{}),
    }

    // Optional data purge.
    if (opts.purge) {
        if (dataDirPath(alloc)) |maybe_dir| {
            if (maybe_dir) |data_dir| {
                defer alloc.free(data_dir);
                std.fs.deleteTreeAbsolute(data_dir) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => {
                        try stdout.print("  Data dir      FAILED to delete {s} ({s})\n", .{ data_dir, @errorName(err) });
                        failures += 1;
                    },
                };
                try stdout.print("  Data dir      deleted ({s})\n", .{data_dir});
            }
        } else |err| {
            try stdout.print("  Data dir      FAILED to resolve ({s})\n", .{@errorName(err)});
            failures += 1;
        }
    } else {
        try stdout.print("  Data dir      kept (config survives; use --purge to delete)\n", .{});
    }

    try stdout.print(
        "\nDone. Close any running paramux windows, then delete the folder itself:\n  {s}\n",
        .{exe_dir},
    );
    if (failures > 0) {
        try stdout.print("Finished with {d} failed step(s); see above.\n", .{failures});
        return 1;
    }
    return 0;
}

fn removeUserPath(alloc: Allocator, dir: []const u8) !bool {
    const current = (try user_env.readUserEnv(alloc, "Path")) orelse return false;
    defer alloc.free(current);
    if (!user_env.pathContains(current, dir)) return false;
    const next = try user_env.pathWithoutDir(alloc, current, dir);
    defer alloc.free(next);
    try user_env.writeUserEnv(alloc, "Path", next);
    return true;
}

/// `%LOCALAPPDATA%\paramux`, resolved the same way the config system
/// resolves it (LOCALAPPDATA env, then known-folder fallback).
fn dataDirPath(alloc: Allocator) !?[]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const local = (try internal_os.windows.knownFolderPathUtf8(
        &internal_os.windows.FOLDERID_LocalAppData,
        &buf,
    )) orelse return null;
    return try std.fs.path.join(alloc, &.{ local, build_config.data_dir_name });
}
