const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const apprt = @import("../apprt.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    /// An optional title for the notification, set with `--title=<title>`.
    /// The title is shown in bold in the desktop toast and is prefixed to the
    /// message in the paramux sidebar row. Ignored when `--state` is set.
    title: [:0]const u8 = "",

    /// An optional agent-attention state, set with `--state=<state>`, one of
    /// `working`, `waiting`, `done`, or `error`. When set, paramux colors the
    /// pane's sidebar row by this state (working=blue, waiting=amber,
    /// done=green, error=red) instead of treating it as a plain notification.
    state: []const u8 = "",

    /// Target a specific pane by its `+list-windows` id instead of the pane
    /// this command runs in. Normally unset — the pane id is discovered from
    /// the `PARAMUX_SURFACE_ID` environment variable injected into each pane.
    @"surface-id": ?u64 = null,

    /// Set when an explicit `--surface-id=` value failed to parse, so `run` can
    /// error out instead of silently falling back to the env/console target.
    _surface_id_invalid: bool = false,

    /// The notification message, collected from all positional arguments after
    /// `+notify`.
    _message: std.ArrayList([]const u8) = .empty,

    /// Collect the `--title`/`--state` flags and all positional arguments as
    /// the message.
    pub fn parseManuallyHook(
        self: *Options,
        alloc: Allocator,
        arg: []const u8,
        iter: anytype,
    ) Allocator.Error!bool {
        try self.consume(alloc, arg);
        while (iter.next()) |param| try self.consume(alloc, param);

        // We consumed everything, so don't continue normal parsing.
        return false;
    }

    fn consume(self: *Options, alloc: Allocator, arg: []const u8) Allocator.Error!void {
        if (lib.cutPrefix(u8, arg, "--title=")) |rest| {
            self.title = try alloc.dupeZ(u8, rest);
            return;
        }
        if (lib.cutPrefix(u8, arg, "--state=")) |rest| {
            self.state = try alloc.dupe(u8, rest);
            return;
        }
        if (lib.cutPrefix(u8, arg, "--surface-id=")) |rest| {
            self.@"surface-id" = std.fmt.parseInt(u64, std.mem.trim(u8, rest, &std.ascii.whitespace), 10) catch blk: {
                self._surface_id_invalid = true;
                break :blk null;
            };
            return;
        }
        try self._message.append(alloc, try alloc.dupe(u8, arg));
    }

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return actionpkg.help_error;
    }
};

/// The `notify` command emits a desktop-notification escape sequence on the
/// terminal it is run in, lighting up the paramux attention indicator for that
/// pane (sidebar dot + taskbar flash + toast).
///
/// It is designed to be called from AI-agent hooks (for example Claude Code's
/// Stop and Notification hooks) so that an agent which has finished or is
/// waiting for input flags its own pane for attention. Because the escape
/// sequence travels down the pane's own PTY, it automatically targets the
/// correct pane with no window or surface id required.
///
/// The message is taken from all arguments after `+notify`:
///
///     winghostty +notify Claude is waiting for your input
///
/// An optional title may be set with `--title=`:
///
///     winghostty +notify --title=Claude review complete
///
/// For agent hooks, `--state=` colors the pane by attention state, one of
/// `working`, `waiting`, `done`, or `error`:
///
///     winghostty +notify --state=waiting Claude needs your approval
///
/// Delivery is console-independent when possible: if `PARAMUX_SURFACE_ID` is in
/// the environment (paramux injects it into every pane) or `--surface-id` is
/// given, the notification is sent to that pane over the winghostty IPC pipe,
/// which works even when the caller's console is hidden (as it is for agent
/// hooks spawned with `windowsHide`). If no instance is listening, it falls
/// back to writing the OSC 777 sequence to the pane's console (`CONOUT$`),
/// which reaches the terminal even when stdout has been redirected.
///
/// Available since: 1.2.0
pub fn run(alloc: Allocator) !u8 {
    var opts: Options = .{};
    defer opts.deinit();

    {
        var iter = try args.argsIterator(alloc);
        defer iter.deinit();
        try args.parse(Options, alloc, &opts, &iter);
    }

    // A malformed explicit --surface-id must not silently fall back to the
    // env/console target — that would misroute the notification to a different
    // pane with a success exit code.
    if (opts._surface_id_invalid) {
        var buf: [128]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        const stderr = &stderr_writer.interface;
        stderr.writeAll("+notify: invalid --surface-id value\n") catch {};
        stderr.flush() catch {};
        return 1;
    }

    // Reuse the arena the CLI parser created for our own allocations.
    const arena = opts._arena.?.allocator();

    const message = try std.mem.join(arena, " ", opts._message.items);

    // When a state is given, encode it in the OSC 777 title as the paramux
    // marker `paramux.state:<state>` (parsed by the win32 apprt's
    // `parseAttentionState`). Otherwise the title is the plain human title.
    const osc_title: []const u8 = if (opts.state.len > 0)
        try std.fmt.allocPrint(arena, "paramux.state:{s}", .{opts.state})
    else
        opts.title;

    // Preferred path: deliver over IPC straight to the addressed pane. This is
    // console-independent, so it works from agent hooks whose console is hidden
    // (Node's default `windowsHide` gives the hook its own console, so a
    // CONOUT$ write would never reach the pane). The surface id comes from
    // `--surface-id` or the `PARAMUX_SURFACE_ID` env var injected per pane. On
    // any failure (no instance listening, surface gone) we fall through to the
    // console path below.
    if (opts.@"surface-id" orelse readSurfaceIdEnv(arena)) |id| {
        const delivered = apprt.App.performSetNotification(
            alloc,
            .detect,
            .{ .surface_id = id },
            osc_title,
            message,
        ) catch false;
        if (delivered) return 0;
    }

    // Fallback: write the OSC 777 desktop-notification sequence to the pane's
    // own console:
    //   ESC ] 777 ; notify ; <title> ; <body> BEL
    //
    // OSC 777 is used instead of the iTerm2-style OSC 9 because its body may
    // safely contain any characters, including the leading digits and
    // semicolons that OSC 9 would otherwise mis-parse as ConEmu subcommands.
    const seq = try std.fmt.allocPrint(
        arena,
        "\x1b]777;notify;{s};{s}\x07",
        .{ osc_title, message },
    );

    writeToTerminal(seq) catch |err| {
        var buf: [256]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        const stderr = &stderr_writer.interface;
        stderr.print("+notify failed to write to the terminal: {}\n", .{err}) catch {};
        stderr.flush() catch {};
        return 1;
    };

    return 0;
}

/// Read the `PARAMUX_SURFACE_ID` env var (decimal) injected into every pane, if
/// present and valid. Returns null when unset or unparseable.
fn readSurfaceIdEnv(alloc: Allocator) ?u64 {
    const val = std.process.getEnvVarOwned(alloc, "PARAMUX_SURFACE_ID") catch return null;
    defer alloc.free(val);
    return std.fmt.parseInt(u64, std.mem.trim(u8, val, &std.ascii.whitespace), 10) catch null;
}

/// Write the notification sequence to the controlling terminal.
fn writeToTerminal(bytes: []const u8) !void {
    switch (builtin.os.tag) {
        // Open the console output directly so we bypass any stdout redirection
        // in the calling process (agent hooks capture stdout, but CONOUT$ is a
        // fresh handle straight to the pane's console).
        .windows => try writeToConsole(bytes),
        else => try std.fs.File.stdout().writeAll(bytes),
    }
}

const w = std.os.windows;

extern "kernel32" fn WriteFile(
    hFile: w.HANDLE,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: w.DWORD,
    lpNumberOfBytesWritten: ?*w.DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) w.BOOL;

fn writeToConsole(bytes: []const u8) !void {
    const path = std.unicode.utf8ToUtf16LeStringLiteral("CONOUT$");
    const handle = w.kernel32.CreateFileW(
        path,
        w.GENERIC_WRITE,
        w.FILE_SHARE_READ | w.FILE_SHARE_WRITE,
        null,
        w.OPEN_EXISTING,
        w.FILE_ATTRIBUTE_NORMAL,
        null,
    );
    if (handle == w.INVALID_HANDLE_VALUE) {
        return w.unexpectedError(w.kernel32.GetLastError());
    }
    defer w.CloseHandle(handle);

    var index: usize = 0;
    while (index < bytes.len) {
        var written: w.DWORD = 0;
        const remaining = bytes[index..];
        const to_write: w.DWORD = @intCast(@min(remaining.len, std.math.maxInt(w.DWORD)));
        if (WriteFile(handle, remaining.ptr, to_write, &written, null) == 0) {
            return w.unexpectedError(w.kernel32.GetLastError());
        }
        if (written == 0) return error.WriteFailed;
        index += written;
    }
}

test "notify collects message and title" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var opts: Options = .{};
    defer opts.deinit();

    const child = try std.process.ArgIteratorGeneral(.{}).init(
        alloc,
        "+notify --title=Done Claude is waiting",
    );
    const ArgsIter = args.ArgsIterator(@TypeOf(child));
    var iter: ArgsIter = .{ .iterator = child };
    defer iter.deinit();

    try args.parse(Options, alloc, &opts, &iter);

    try testing.expectEqualStrings("Done", opts.title);
    try testing.expectEqual(@as(usize, 3), opts._message.items.len);
    try testing.expectEqualStrings("Claude", opts._message.items[0]);
    try testing.expectEqualStrings("is", opts._message.items[1]);
    try testing.expectEqualStrings("waiting", opts._message.items[2]);
}
