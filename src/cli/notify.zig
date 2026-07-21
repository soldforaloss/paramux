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

    /// Read the hook payload from stdin, sum the token usage recorded in
    /// the agent transcript named by its `transcript_path` (Claude Code
    /// JSONL), and attach the total to the attention signal.
    @"tokens-from-transcript": bool = false,

    /// An optional title for the notification, set with `--title=<title>`.
    /// The title is shown in bold in the desktop toast and is prefixed to the
    /// message in the paramux sidebar row. Ignored when `--state` is set.
    title: [:0]const u8 = "",

    /// An optional agent-attention state, set with `--state=<state>`, one of
    /// `working`, `waiting`, `done`, `error`, or `none`. When set, paramux
    /// colors the pane's sidebar row by this state (working=blue,
    /// waiting=amber, done=green, error=red) instead of treating it as a
    /// plain notification. `none` clears any prior state — agent SessionEnd
    /// hooks use it so a killed or exited CLI can't leave a stale
    /// "working" pane behind.
    state: []const u8 = "",

    /// When set with `--message-from-stdin`, read the hook's JSON payload
    /// from stdin and use its `message` string as the notification message,
    /// falling back to the positional message when the payload has none.
    /// This lets exec-form hook configs (Claude Code's settings.json, which
    /// pipes the event payload to the command) show the REAL permission or
    /// notification text without a wrapper script.
    @"message-from-stdin": bool = false,

    /// Target a specific pane by its `list-windows` id instead of the pane
    /// this command runs in. Normally unset — the pane id is discovered from
    /// the `PARAMUX_SURFACE_ID` environment variable injected into each pane.
    @"surface-id": ?u64 = null,

    /// Target the currently focused pane over IPC. The escape hatch for
    /// scripts running OUTSIDE any pane (no PARAMUX_SURFACE_ID), where
    /// the console fallback cannot reach paramux.
    focused: bool = false,

    /// Set when an explicit `--surface-id=` value failed to parse, so `run` can
    /// error out instead of silently falling back to the env/console target.
    _surface_id_invalid: bool = false,

    /// The notification message, collected from all positional arguments after
    /// `notify`.
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
        if (std.mem.eql(u8, arg, "--tokens-from-transcript")) {
            self.@"tokens-from-transcript" = true;
            return;
        }
        if (lib.cutPrefix(u8, arg, "--title=")) |rest| {
            self.title = try alloc.dupeZ(u8, rest);
            return;
        }
        if (lib.cutPrefix(u8, arg, "--state=")) |rest| {
            self.state = try alloc.dupe(u8, rest);
            return;
        }
        if (std.mem.eql(u8, arg, "--message-from-stdin")) {
            self.@"message-from-stdin" = true;
            return;
        }
        if (std.mem.eql(u8, arg, "--focused")) {
            self.focused = true;
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
/// The message is taken from all arguments after `notify`:
///
///     paramux notify Claude is waiting for your input
///
/// An optional title may be set with `--title=`:
///
///     paramux notify --title=Claude review complete
///
/// For agent hooks, `--state=` colors the pane by attention state, one of
/// `working`, `waiting`, `done`, or `error`:
///
///     paramux notify --state=waiting Claude needs your approval
///
/// Delivery is console-independent when possible: if `PARAMUX_SURFACE_ID` is in
/// the environment (paramux injects it into every pane) or `--surface-id` is
/// given, the notification is sent to that pane over the paramux IPC pipe,
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
        stderr.writeAll("notify: invalid --surface-id value\n") catch {};
        stderr.flush() catch {};
        return 1;
    }

    // Reuse the arena the CLI parser created for our own allocations.
    const arena = opts._arena.?.allocator();

    const fallback_message = try std.mem.join(arena, " ", opts._message.items);

    // Exec-form hooks (Claude Code) pipe the event payload JSON to us on
    // stdin; surface its real `message` text when asked to. Any parse or
    // read failure quietly keeps the positional fallback — a notification
    // with a canned message beats no notification.
    var transcript_tokens: u64 = 0;
    const wants_stdin = opts.@"message-from-stdin" or opts.@"tokens-from-transcript";
    const stdin_bytes: ?[]const u8 = if (wants_stdin)
        (std.fs.File.stdin().readToEndAlloc(arena, 1024 * 1024) catch null)
    else
        null;
    if (opts.@"tokens-from-transcript") {
        if (stdin_bytes) |payload| {
            if (extractTranscriptPath(arena, payload)) |path| {
                transcript_tokens = sumClaudeTranscriptTokens(arena, path) catch 0;
            }
        }
    }
    const message: []const u8 = if (opts.@"message-from-stdin") blk: {
        const payload = stdin_bytes orelse break :blk fallback_message;
        break :blk extractHookMessage(arena, payload) orelse fallback_message;
    } else fallback_message;

    // When a state is given, encode it in the OSC 777 title as the paramux
    // marker `paramux.state:<state>` (parsed by the win32 apprt's
    // `parseAttentionState`). Otherwise the title is the plain human title.
    // Sanitize a human title for the marker rider: strip the rider
    // separators so parsing stays unambiguous.
    var title_rider_buf: [96]u8 = undefined;
    const title_rider: []const u8 = blk: {
        if (opts.title.len == 0) break :blk "";
        var n: usize = 0;
        for (opts.title) |c| {
            if (n >= title_rider_buf.len) break;
            if (c == ';' or c == ':' or c < 0x20) continue;
            title_rider_buf[n] = c;
            n += 1;
        }
        break :blk title_rider_buf[0..n];
    };
    const osc_title: []const u8 = if (opts.state.len > 0) state_blk: {
        var parts: std.ArrayListUnmanaged(u8) = .empty;
        try parts.writer(arena).print("paramux.state:{s}", .{opts.state});
        if (transcript_tokens > 0) try parts.writer(arena).print(";tokens={d}", .{transcript_tokens});
        if (title_rider.len > 0) try parts.writer(arena).print(";title={s}", .{title_rider});
        break :state_blk parts.items;
    } else opts.title;

    // Preferred path: deliver over IPC straight to the addressed pane. This is
    // console-independent, so it works from agent hooks whose console is hidden
    // (Node's default `windowsHide` gives the hook its own console, so a
    // CONOUT$ write would never reach the pane). The surface id comes from
    // `--surface-id` or the `PARAMUX_SURFACE_ID` env var injected per pane. On
    // any failure (no instance listening, surface gone) we fall through to the
    // console path below.
    if (opts.focused) {
        const delivered = apprt.App.performSetNotification(
            alloc,
            .detect,
            .focused,
            osc_title,
            message,
        ) catch false;
        if (delivered) return 0;
        var buf: [128]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        stderr_writer.interface.writeAll("notify --focused: no running instance answered\n") catch {};
        stderr_writer.interface.flush() catch {};
        return 1;
    }

    const target_id = opts.@"surface-id" orelse readSurfaceIdEnv(arena);
    if (target_id) |id| {
        const delivered = apprt.App.performSetNotification(
            alloc,
            .detect,
            .{ .surface_id = id },
            osc_title,
            message,
        ) catch false;
        if (delivered) return 0;
    } else {
        // No pane id anywhere: the console write below reaches whatever
        // terminal is hosting this command, which outside paramux is
        // not a pane at all. Say so instead of no-opping silently.
        var buf: [192]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&buf);
        stderr_writer.interface.writeAll(
            "notify: not inside a paramux pane; use --surface-id=<id> or --focused (writing the console escape anyway)\n",
        ) catch {};
        stderr_writer.interface.flush() catch {};
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
        stderr.print("notify failed to write to the terminal: {}\n", .{err}) catch {};
        stderr.flush() catch {};
        return 1;
    };

    return 0;
}

/// Extract a usable `message` string from a hook payload JSON object.
/// Returns null for anything that isn't an object with a non-empty string
/// `message` — callers fall back to their positional message. Control
/// characters are stripped and the result is truncated so a hostile or
/// giant payload can't distort the sidebar row.
fn extractHookMessage(alloc: Allocator, bytes: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, bytes, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, trimmed, .{}) catch return null;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return null,
    };
    const raw = switch (obj.get("message") orelse return null) {
        .string => |s| s,
        else => return null,
    };

    const max_len = 300;
    var out = std.ArrayList(u8).initCapacity(alloc, @min(raw.len, max_len)) catch return null;
    for (raw) |ch| {
        if (out.items.len >= max_len) break;
        out.append(alloc, if (std.ascii.isControl(ch)) ' ' else ch) catch return null;
    }
    const result = std.mem.trim(u8, out.items, &std.ascii.whitespace);
    if (result.len == 0) return null;
    return alloc.dupe(u8, result) catch null;
}

test "notify extractHookMessage takes payload message and hardens it" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    try testing.expectEqualStrings(
        "Allow Bash to run git push?",
        extractHookMessage(alloc, "{\"hook_event_name\":\"PermissionRequest\",\"message\":\"Allow Bash to run git push?\"}").?,
    );
    // Control characters are flattened.
    try testing.expectEqualStrings(
        "a b",
        extractHookMessage(alloc, "{\"message\":\"a\\nb\"}").?,
    );
    // Non-object, missing, non-string, or empty messages fall back.
    try testing.expect(extractHookMessage(alloc, "[1,2]") == null);
    try testing.expect(extractHookMessage(alloc, "{}") == null);
    try testing.expect(extractHookMessage(alloc, "{\"message\":42}") == null);
    try testing.expect(extractHookMessage(alloc, "{\"message\":\"  \"}") == null);
    try testing.expect(extractHookMessage(alloc, "not json") == null);
    // Oversized messages are truncated, not rejected.
    const big = "{\"message\":\"" ++ "x" ** 500 ++ "\"}";
    try testing.expectEqual(@as(usize, 300), extractHookMessage(alloc, big).?.len);
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
        "notify --title=Done Claude is waiting",
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

/// The hook payload's `transcript_path` value, if present.
fn extractTranscriptPath(alloc: std.mem.Allocator, payload: []const u8) ?[]const u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, payload, .{}) catch return null;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return null,
    };
    const val = obj.get("transcript_path") orelse return null;
    return switch (val) {
        .string => |str| alloc.dupe(u8, str) catch null,
        else => null,
    };
}

/// Sum input+output tokens across a Claude Code JSONL transcript. Each
/// assistant line carries `message.usage.{input_tokens,output_tokens}`;
/// the sum approximates the session's total token traffic. Capped scan.
fn sumClaudeTranscriptTokens(alloc: std.mem.Allocator, path: []const u8) !u64 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(alloc, 64 * 1024 * 1024);
    defer alloc.free(bytes);

    var total: u64 = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "\"usage\"") == null) continue;
        total += extractUsageNumber(line, "\"input_tokens\":");
        total += extractUsageNumber(line, "\"output_tokens\":");
    }
    return total;
}

/// First integer following `key` in `line` (0 when absent) — a targeted
/// scan that avoids full JSON parsing per transcript line.
fn extractUsageNumber(line: []const u8, key: []const u8) u64 {
    const at = std.mem.indexOf(u8, line, key) orelse return 0;
    var i = at + key.len;
    while (i < line.len and (line[i] == ' ')) i += 1;
    var value: u64 = 0;
    var any = false;
    while (i < line.len and line[i] >= '0' and line[i] <= '9') : (i += 1) {
        value = value * 10 + (line[i] - '0');
        any = true;
    }
    return if (any) value else 0;
}

test "extractUsageNumber pulls integers" {
    try std.testing.expectEqual(@as(u64, 128), extractUsageNumber("{\"usage\":{\"input_tokens\": 128}}", "\"input_tokens\":"));
    try std.testing.expectEqual(@as(u64, 0), extractUsageNumber("{}", "\"input_tokens\":"));
}

test "extractTranscriptPath reads hook payload" {
    const t = std.testing;
    const payload = "{\"transcript_path\":\"C:/tmp/session.jsonl\",\"hook_event_name\":\"Stop\"}";
    const path = extractTranscriptPath(t.allocator, payload) orelse return error.TestExpectedPath;
    defer t.allocator.free(path);
    try t.expectEqualStrings("C:/tmp/session.jsonl", path);
}
