const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const apprt = @import("../apprt.zig");

pub const Options = struct {
    _arena: ?ArenaAllocator = null,

    /// This must be registered so that it isn't an error to pass `--help`.
    help: bool = false,

    /// With `--fire`, send a live test signal through the real IPC pipeline
    /// to the pane this command runs in, cycling
    /// working -> waiting -> done -> clear so every attention color is
    /// exercised end-to-end. Requires running inside a paramux pane.
    fire: bool = false,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }
};

const Status = enum {
    ok,
    warn,
    fail,

    fn label(self: Status) []const u8 {
        return switch (self) {
            .ok => "[ OK ]",
            .warn => "[WARN]",
            .fail => "[FAIL]",
        };
    }
};

const Report = struct {
    out: *std.Io.Writer,
    fail_count: usize = 0,
    warn_count: usize = 0,

    fn line(self: *Report, status: Status, comptime fmt: []const u8, fmt_args: anytype) !void {
        switch (status) {
            .fail => self.fail_count += 1,
            .warn => self.warn_count += 1,
            .ok => {},
        }
        try self.out.print("{s} " ++ fmt ++ "\n", .{status.label()} ++ fmt_args);
    }
};

/// The `doctor` command diagnoses the agent-hook pipeline: it verifies the
/// install environment (`PARAMUX_HOME`, Node for the Codex/Gemini adapters),
/// that the packaged hook files are configured with real paths, and that
/// each supported AI CLI's config actually references them. Run it inside a
/// paramux pane with `--fire` to also send live test signals through the
/// IPC pipeline and watch the sidebar cycle working/waiting/done/clear.
///
///     paramux doctor
///     paramux doctor --fire
///
/// Exits 0 when nothing failed (warnings are informational: a tool you
/// don't use reporting "not wired" is expected).
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
        var buf: [128]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        const stderr = &stderr_writer.interface;
        try stderr.writeAll("paramux doctor is a Windows lifecycle command.\n");
        try stderr.flush();
        return 1;
    }

    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&out_buf);
    const out = &stdout_writer.interface;
    var report: Report = .{ .out = out };

    // 1. PARAMUX_HOME: the anchor every adapter resolves paramux through.
    const home: ?[]const u8 = std.process.getEnvVarOwned(a, "PARAMUX_HOME") catch null;
    if (home) |h| {
        if (!std.fs.path.isAbsolute(h)) {
            try report.line(.fail, "PARAMUX_HOME is not an absolute path: {s}", .{h});
        } else if (fileExists(a, &.{ h, "paramux.com" })) {
            try report.line(.ok, "PARAMUX_HOME -> {s} (paramux.com present)", .{h});
        } else {
            try report.line(.fail, "PARAMUX_HOME set but paramux.com is missing: {s}", .{h});
        }
    } else {
        try report.line(.fail, "PARAMUX_HOME is not set - run install-paramux.cmd (adapters cannot find paramux)", .{});
    }

    // 2. Node on PATH: required by the Codex and Gemini adapters only.
    if (findOnPath(a, "node.exe") != null) {
        try report.line(.ok, "node.exe found on PATH (required by the Codex/Gemini adapters)", .{});
    } else {
        try report.line(.warn, "node.exe not on PATH - Codex and Gemini hooks will fail until Node is installed", .{});
    }

    // 3. Packaged hook files: present and actually configured (the installer
    //    replaces deliberately non-executable placeholders).
    if (home) |h| {
        try checkPackagedFile(&report, a, h, "agent-hooks\\claude-code.settings.json");
        try checkPackagedFile(&report, a, h, "agent-hooks\\codex\\hooks.json");
        try checkPackagedFile(&report, a, h, "agent-hooks\\codex\\paramux-hook.cjs");
        try checkPackagedFile(&report, a, h, "paramux-codex-hook.cmd");
        try checkPackagedFile(&report, a, h, "agent-hooks\\gemini-paramux\\scripts\\notify.cjs");
        try checkPackagedFile(&report, a, h, "agent-hooks\\opencode\\paramux.js");
    }

    // 4. Per-tool wiring: does each CLI's own config reference our hooks?
    const profile: ?[]const u8 = std.process.getEnvVarOwned(a, "USERPROFILE") catch null;
    if (profile) |up| {
        try checkToolConfig(&report, a, "Claude Code", &.{ up, ".claude", "settings.json" }, "paramux");
        try checkToolConfig(&report, a, "Codex CLI", &.{ up, ".codex", "hooks.json" }, "paramux-codex-hook.cmd");
        if (dirExists(a, &.{ up, ".gemini", "extensions", "paramux-notifications" })) {
            try report.line(.ok, "Gemini CLI: paramux-notifications extension installed", .{});
        } else {
            try report.line(.warn, "Gemini CLI: extension not installed (gemini extensions install <agent-hooks>\\gemini-paramux)", .{});
        }
        if (fileExists(a, &.{ up, ".config", "opencode", "plugins", "paramux.js" })) {
            try report.line(.ok, "OpenCode: global paramux.js plugin installed", .{});
        } else {
            try report.line(.warn, "OpenCode: no global plugin (project-local .opencode\\plugins are not checked)", .{});
        }
    } else {
        try report.line(.warn, "USERPROFILE unset; skipped per-tool config checks", .{});
    }

    // 5. In-pane context: the env paramux injects so notify auto-targets.
    const surface_id: ?u64 = blk: {
        const val = std.process.getEnvVarOwned(a, "PARAMUX_SURFACE_ID") catch break :blk null;
        break :blk std.fmt.parseInt(u64, std.mem.trim(u8, val, &std.ascii.whitespace), 10) catch null;
    };
    if (surface_id != null) {
        try report.line(.ok, "running inside a paramux pane (PARAMUX_SURFACE_ID present)", .{});
    } else {
        try report.line(.warn, "not inside a paramux pane - hooks fired here cannot auto-target; --fire unavailable", .{});
    }

    // 6. IPC health: is an instance listening, and how fast is a
    // round-trip? list-windows is the unauthenticated discovery call.
    {
        var timer = std.time.Timer.start() catch null;
        if (apprt.App.queryAutomationWindowList(alloc, .detect) catch null) |data| {
            defer alloc.free(data);
            if (timer) |*tm| {
                const us = tm.read() / std.time.ns_per_us;
                try report.line(.ok, "IPC round-trip (list-windows): {d}.{d} ms", .{ us / 1000, (us % 1000) / 100 });
            } else {
                try report.line(.ok, "IPC round-trip: instance responded", .{});
            }
        } else {
            try report.line(.warn, "no running paramux instance answered the IPC pipe", .{});
        }
    }

    // 7. Accessibility: UIA core must be loadable for the TextPattern
    // and fleet-summary providers, and "clients listening" says whether
    // a screen reader is attached right now.
    {
        const uiacore = std.os.windows.kernel32.LoadLibraryW(
            std.unicode.utf8ToUtf16LeStringLiteral("uiautomationcore.dll"),
        );
        if (uiacore != null) {
            const listening = blk: {
                const proc = std.os.windows.kernel32.GetProcAddress(
                    uiacore.?,
                    "UiaClientsAreListening",
                ) orelse break :blk false;
                const f: *const fn () callconv(.winapi) i32 = @ptrCast(@alignCast(proc));
                break :blk f() != 0;
            };
            try report.line(.ok, "UI Automation core loadable; screen-reader client listening: {s}", .{
                if (listening) "yes" else "no",
            });
        } else {
            try report.line(.warn, "uiautomationcore.dll not loadable - screen readers cannot read panes", .{});
        }
    }

    // 8. Crash dumps: surface leftovers so opted-in users notice them.
    crash_blk: {
        const local = std.process.getEnvVarOwned(a, "LOCALAPPDATA") catch break :crash_blk;
        const dir_path = std.fs.path.join(a, &.{ local, "paramux", "crash" }) catch break :crash_blk;
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch break :crash_blk;
        defer dir.close();
        var count: usize = 0;
        var it = dir.iterate();
        while (it.next() catch null) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".dmp")) count += 1;
        }
        if (count > 0) {
            try report.line(.warn, "{d} crash dump(s) in the state dir's crash folder - attach to an issue or delete", .{count});
        } else {
            try report.line(.ok, "no crash dumps on disk", .{});
        }
    }

    // 9. Live pipeline test.
    if (opts.fire) {
        if (surface_id) |id| {
            try fireTestSignals(&report, alloc, a, id);
        } else {
            try report.line(.fail, "--fire requires running inside a paramux pane", .{});
        }
    }

    try out.print(
        "\ndoctor: {d} failed, {d} warnings.{s}\n",
        .{
            report.fail_count,
            report.warn_count,
            if (!opts.fire) " Run inside a pane with --fire for a live signal test." else "",
        },
    );
    try out.flush();
    return if (report.fail_count == 0) 0 else 1;
}

fn fireTestSignals(report: *Report, alloc: Allocator, arena: Allocator, id: u64) !void {
    const states = [_][]const u8{ "working", "waiting", "done", "none" };
    for (states) |state| {
        const title = try std.fmt.allocPrint(arena, "paramux.state:{s}", .{state});
        const delivered = apprt.App.performSetNotification(
            alloc,
            .detect,
            .{ .surface_id = id },
            title,
            "paramux doctor test signal",
        ) catch false;
        if (delivered) {
            try report.line(.ok, "fired {s} signal over IPC (watch the sidebar)", .{state});
        } else {
            try report.line(.fail, "IPC delivery failed for {s} signal - is this pane's paramux instance running?", .{state});
        }
        std.Thread.sleep(600 * std.time.ns_per_ms);
    }
}

/// Search the PATH directories for `name`; returns the first hit's full
/// path or null. Mirrors how the Gemini launcher resolves node.exe.
fn findOnPath(alloc: Allocator, name: []const u8) ?[]const u8 {
    const path_env = std.process.getEnvVarOwned(alloc, "PATH") catch return null;
    var it = std.mem.splitScalar(u8, path_env, ';');
    while (it.next()) |raw_dir| {
        const dir = std.mem.trim(u8, raw_dir, " \t\"");
        if (dir.len == 0) continue;
        const candidate = joinPath(alloc, &.{ dir, name }) orelse continue;
        std.fs.cwd().access(candidate, .{}) catch continue;
        return candidate;
    }
    return null;
}

fn joinPath(alloc: Allocator, parts: []const []const u8) ?[]const u8 {
    return std.fs.path.join(alloc, parts) catch null;
}

fn fileExists(alloc: Allocator, parts: []const []const u8) bool {
    const p = joinPath(alloc, parts) orelse return false;
    std.fs.cwd().access(p, .{}) catch return false;
    return true;
}

fn dirExists(alloc: Allocator, parts: []const []const u8) bool {
    const p = joinPath(alloc, parts) orelse return false;
    var dir = std.fs.cwd().openDir(p, .{}) catch return false;
    dir.close();
    return true;
}

fn checkPackagedFile(report: *Report, alloc: Allocator, home: []const u8, rel: []const u8) !void {
    const p = joinPath(alloc, &.{ home, rel }) orelse return;
    const contents = std.fs.cwd().readFileAlloc(alloc, p, 4 * 1024 * 1024) catch {
        try report.line(.fail, "packaged hook file missing: {s}", .{rel});
        return;
    };
    if (std.mem.indexOf(u8, contents, "__PARAMUX") != null) {
        try report.line(.fail, "{s} still contains installer placeholders - rerun install-paramux.cmd", .{rel});
    } else {
        try report.line(.ok, "packaged {s} configured", .{rel});
    }
}

fn checkToolConfig(
    report: *Report,
    alloc: Allocator,
    tool: []const u8,
    parts: []const []const u8,
    needle: []const u8,
) !void {
    const p = joinPath(alloc, parts) orelse return;
    const contents = std.fs.cwd().readFileAlloc(alloc, p, 4 * 1024 * 1024) catch {
        try report.line(.warn, "{s}: config not found ({s})", .{ tool, p });
        return;
    };
    if (std.mem.indexOf(u8, contents, needle) != null) {
        try report.line(.ok, "{s}: hooks wired ({s})", .{ tool, p });
    } else {
        try report.line(.warn, "{s}: config exists but has no paramux hooks ({s})", .{ tool, p });
    }
}

test "doctor status labels are aligned" {
    try std.testing.expectEqualStrings("[ OK ]", Status.ok.label());
    try std.testing.expectEqualStrings("[WARN]", Status.warn.label());
    try std.testing.expectEqualStrings("[FAIL]", Status.fail.label());
}
