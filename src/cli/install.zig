const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const user_env = @import("../os/windows_user_env.zig");
const explorer_menu = @import("../apprt/win32_explorer_menu.zig");

pub const Options = struct {
    /// Skip adding this folder to the user PATH.
    @"no-path": bool = false,

    /// Skip registering the Explorer "Open in Paramux" context menu.
    @"no-context-menu": bool = false,

    /// Skip wiring the packaged agent-hook adapters.
    @"no-hooks": bool = false,

    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return actionpkg.help_error;
    }
};

/// The `install` command wires this Paramux folder into the current user's
/// environment — the native equivalent of `install-paramux.cmd`:
///
///   * adds the folder containing this executable to the user `PATH`
///   * sets `PARAMUX_HOME` to that folder
///   * registers the Explorer "Open in Paramux" context menu (folders,
///     folder backgrounds, and drives; per-user registry, no admin)
///   * wires the packaged agent-hook adapters when
///     `configure-paramux-hooks.ps1` is present next to the executable
///
/// Everything is per-user and idempotent; run it again after moving the
/// folder. Undo with `paramux +uninstall`.
///
/// Flags: `--no-path`, `--no-context-menu`, `--no-hooks` skip the
/// corresponding step.
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
        std.debug.print("+install is a Windows lifecycle command.\n", .{});
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

    try stdout.print("Installing paramux from: {s}\n", .{exe_dir});

    var failures: u8 = 0;

    if (!opts.@"no-path") {
        if (addUserPath(alloc, exe_dir)) |added| {
            if (added) {
                try stdout.print("  PATH          added\n", .{});
            } else {
                try stdout.print("  PATH          already present\n", .{});
            }
        } else |err| {
            try stdout.print("  PATH          FAILED ({s})\n", .{@errorName(err)});
            failures += 1;
        }
        if (user_env.writeUserEnv(alloc, "PARAMUX_HOME", exe_dir)) {
            try stdout.print("  PARAMUX_HOME  set\n", .{});
        } else |err| {
            try stdout.print("  PARAMUX_HOME  FAILED ({s})\n", .{@errorName(err)});
            failures += 1;
        }
        user_env.broadcastEnvironmentChange();
    } else {
        try stdout.print("  PATH          skipped (--no-path)\n", .{});
    }

    if (!opts.@"no-context-menu") {
        explorer_menu.register(alloc);
        switch (explorer_menu.status(alloc)) {
            .registered => try stdout.print("  Explorer menu registered (\"Open in Paramux\")\n", .{}),
            else => {
                try stdout.print("  Explorer menu FAILED (verify registry access)\n", .{});
                failures += 1;
            },
        }
    } else {
        try stdout.print("  Explorer menu skipped (--no-context-menu)\n", .{});
    }

    if (!opts.@"no-hooks") {
        switch (try wireAgentHooks(alloc, exe_dir)) {
            .wired => try stdout.print("  Agent hooks   wired (Claude Code, Codex, Gemini, OpenCode)\n", .{}),
            .missing => try stdout.print("  Agent hooks   skipped (configure-paramux-hooks.ps1 not packaged here)\n", .{}),
            .failed => {
                try stdout.print("  Agent hooks   FAILED (run configure-paramux-hooks.ps1 manually)\n", .{});
                failures += 1;
            },
        }
    } else {
        try stdout.print("  Agent hooks   skipped (--no-hooks)\n", .{});
    }

    if (failures == 0) {
        try stdout.print("\nDone. Open a NEW terminal, then run: paramux\n", .{});
        return 0;
    }
    try stdout.print("\nFinished with {d} failed step(s); see above.\n", .{failures});
    return 1;
}

fn addUserPath(alloc: Allocator, dir: []const u8) !bool {
    const current = (try user_env.readUserEnv(alloc, "Path")) orelse try alloc.dupe(u8, "");
    defer alloc.free(current);
    if (user_env.pathContains(current, dir)) return false;
    const next = try user_env.pathWithDir(alloc, current, dir);
    defer alloc.free(next);
    try user_env.writeUserEnv(alloc, "Path", next);
    return true;
}

const HookResult = enum { wired, missing, failed };

/// Run the packaged hook configurator when present. It rewrites the
/// packaged agent hook files with absolute paths into this folder; the
/// script is contract-tested, so we shell out rather than reimplement it.
fn wireAgentHooks(alloc: Allocator, exe_dir: []const u8) !HookResult {
    const script = try std.fs.path.join(alloc, &.{ exe_dir, "configure-paramux-hooks.ps1" });
    defer alloc.free(script);
    std.fs.accessAbsolute(script, .{}) catch return .missing;

    var child = std.process.Child.init(&.{
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script,
    }, alloc);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = child.spawnAndWait() catch return .failed;
    return switch (term) {
        .Exited => |code| if (code == 0) .wired else .failed,
        else => .failed,
    };
}
