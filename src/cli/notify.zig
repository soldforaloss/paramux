const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    /// An optional title for the notification, set with `--title=<title>`.
    /// The title is shown in bold in the desktop toast and is prefixed to the
    /// message in the paramux sidebar row.
    title: [:0]const u8 = "",

    /// The notification message, collected from all positional arguments after
    /// `+notify`.
    _message: std.ArrayList([]const u8) = .empty,

    /// Collect the `--title` flag and all positional arguments as the message.
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
/// On Windows the sequence is written directly to the console (`CONOUT$`)
/// rather than to stdout, so it still reaches the terminal even when the
/// calling process has had its stdout redirected, as agent hooks do.
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

    // Reuse the arena the CLI parser created for our own allocations.
    const arena = opts._arena.?.allocator();

    const message = try std.mem.join(arena, " ", opts._message.items);

    // Build the OSC 777 desktop-notification sequence:
    //   ESC ] 777 ; notify ; <title> ; <body> BEL
    //
    // OSC 777 is used instead of the iTerm2-style OSC 9 because its body may
    // safely contain any characters, including the leading digits and
    // semicolons that OSC 9 would otherwise mis-parse as ConEmu subcommands.
    const seq = try std.fmt.allocPrint(
        arena,
        "\x1b]777;notify;{s};{s}\x07",
        .{ opts.title, message },
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
