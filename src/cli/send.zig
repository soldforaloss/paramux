const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const apprt = @import("../apprt.zig");
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    _arena: ?ArenaAllocator = null,
    class: ?[:0]const u8 = null,
    @"surface-id": ?u64 = null,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

const PerformSendFn = *const fn (
    Allocator,
    apprt.ipc.Target,
    apprt.ipc.AutomationActionTarget,
    []const u8,
) anyerror!bool;

/// Send exact UTF-8 input to a pane in a running paramux instance.
///
/// The default target is the focused pane. Use `--surface-id=<id>` with a pane
/// id from `paramux +list-windows` for exact routing. The payload is one CLI
/// argument, so quote text containing spaces. Unlike clipboard paste, the bytes
/// are delivered exactly as supplied.
///
///   * `paramux +send "echo hello"`
///   * `paramux +send --surface-id=42 "echo hello"`
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const result = try runArgsWithPerform(alloc, &iter, &stderr_writer.interface, performSend);
    try stderr_writer.interface.flush();
    return result;
}

fn performSend(
    alloc: Allocator,
    target: apprt.ipc.Target,
    action_target: apprt.ipc.AutomationActionTarget,
    text: []const u8,
) !bool {
    return try apprt.App.performSend(alloc, target, action_target, text);
}

fn runArgsWithPerform(
    alloc: Allocator,
    args_iter: anytype,
    stderr: *std.Io.Writer,
    perform: PerformSendFn,
) !u8 {
    var opts: Options = .{ ._arena = ArenaAllocator.init(alloc) };
    defer opts.deinit();
    const opts_alloc = opts._arena.?.allocator();

    var payload: ?[]const u8 = null;
    var options_done = false;
    while (args_iter.next()) |arg| {
        if (!options_done and (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help"))) {
            return actionpkg.help_error;
        }
        if (!options_done and std.mem.eql(u8, arg, "--")) {
            options_done = true;
            continue;
        }
        if (!options_done) {
            if (lib.cutPrefix(u8, arg, "--class=")) |class| {
                opts.class = try opts_alloc.dupeZ(u8, std.mem.trim(u8, class, &std.ascii.whitespace));
                continue;
            }
            if (lib.cutPrefix(u8, arg, "--surface-id=")) |raw| {
                opts.@"surface-id" = std.fmt.parseInt(u64, std.mem.trim(u8, raw, &std.ascii.whitespace), 10) catch {
                    try stderr.print("+send: invalid --surface-id value: {s}\n", .{raw});
                    return 1;
                };
                continue;
            }
            if (std.mem.startsWith(u8, arg, "-")) {
                try stderr.print("Unknown option for +send: {s}\n", .{arg});
                return 1;
            }
        }
        if (payload != null) {
            try stderr.writeAll("+send accepts exactly one payload; quote text containing spaces.\n");
            return 1;
        }
        payload = arg;
    }

    const value = payload orelse {
        try stderr.writeAll("+send requires one UTF-8 payload.\n");
        return 1;
    };
    if (value.len == 0) {
        try stderr.writeAll("+send requires a non-empty UTF-8 payload.\n");
        return 1;
    }
    if (value.len > apprt.ipc.automation_input_max_len) {
        try stderr.print(
            "+send payload exceeds the {d}-byte limit.\n",
            .{apprt.ipc.automation_input_max_len},
        );
        return 1;
    }
    if (!std.unicode.utf8ValidateSlice(value)) {
        try stderr.writeAll("+send payload must be valid UTF-8.\n");
        return 1;
    }

    const delivered = perform(
        alloc,
        if (opts.class) |class| .{ .class = class } else .detect,
        if (opts.@"surface-id") |id| .{ .surface_id = id } else .focused,
        value,
    ) catch |err| {
        try stderr.print("Sending terminal input via IPC failed: {}\n", .{err});
        return 1;
    };
    if (delivered) return 0;
    try stderr.writeAll("No matching paramux instance is listening for terminal input.\n");
    return 1;
}

test "automation-send-cli preserves exact utf8 and explicit target" {
    const testing = std.testing;
    const Hook = struct {
        var class: ?[]u8 = null;
        var surface_id: ?u64 = null;
        var text: ?[]u8 = null;

        fn perform(
            _: Allocator,
            target: apprt.ipc.Target,
            action_target: apprt.ipc.AutomationActionTarget,
            value: []const u8,
        ) !bool {
            class = switch (target) {
                .class => |v| try testing.allocator.dupe(u8, v),
                .detect => return error.UnexpectedTarget,
            };
            surface_id = switch (action_target) {
                .surface_id => |id| id,
                .focused => return error.UnexpectedTarget,
            };
            text = try testing.allocator.dupe(u8, value);
            return true;
        }
    };
    defer if (Hook.class) |value| testing.allocator.free(value);
    defer if (Hook.text) |value| testing.allocator.free(value);

    var iter = try std.process.ArgIteratorGeneral(.{}).init(
        testing.allocator,
        "--class=lane9 --surface-id=42 \"snowman ☃ and spaces\"",
    );
    defer iter.deinit();
    var stderr = std.Io.Writer.Allocating.init(testing.allocator);
    defer stderr.deinit();

    try testing.expectEqual(
        @as(u8, 0),
        try runArgsWithPerform(testing.allocator, &iter, &stderr.writer, &Hook.perform),
    );
    try testing.expectEqualStrings("", stderr.written());
    try testing.expectEqualStrings("lane9", Hook.class.?);
    try testing.expectEqual(@as(?u64, 42), Hook.surface_id);
    try testing.expectEqualStrings("snowman ☃ and spaces", Hook.text.?);
}

test "automation-send-cli defaults to focused target" {
    const testing = std.testing;
    const Hook = struct {
        fn perform(
            _: Allocator,
            target: apprt.ipc.Target,
            action_target: apprt.ipc.AutomationActionTarget,
            value: []const u8,
        ) !bool {
            try testing.expect(target == .detect);
            try testing.expect(action_target == .focused);
            try testing.expectEqualStrings("hello", value);
            return true;
        }
    };

    var iter = try std.process.ArgIteratorGeneral(.{}).init(testing.allocator, "hello");
    defer iter.deinit();
    var stderr = std.Io.Writer.Allocating.init(testing.allocator);
    defer stderr.deinit();

    try testing.expectEqual(
        @as(u8, 0),
        try runArgsWithPerform(testing.allocator, &iter, &stderr.writer, &Hook.perform),
    );
}

test "automation-send-cli permits send as the exact payload" {
    const testing = std.testing;
    const Hook = struct {
        fn perform(
            _: Allocator,
            _: apprt.ipc.Target,
            _: apprt.ipc.AutomationActionTarget,
            value: []const u8,
        ) !bool {
            try testing.expectEqualStrings("send", value);
            return true;
        }
    };

    var iter = try std.process.ArgIteratorGeneral(.{}).init(testing.allocator, "send");
    defer iter.deinit();
    var stderr = std.Io.Writer.Allocating.init(testing.allocator);
    defer stderr.deinit();
    try testing.expectEqual(
        @as(u8, 0),
        try runArgsWithPerform(testing.allocator, &iter, &stderr.writer, &Hook.perform),
    );
}

test "automation-send-cli rejects oversized payload before ipc" {
    const testing = std.testing;
    const Hook = struct {
        fn perform(
            _: Allocator,
            _: apprt.ipc.Target,
            _: apprt.ipc.AutomationActionTarget,
            _: []const u8,
        ) !bool {
            return error.UnexpectedIpc;
        }
    };

    const payload = try testing.allocator.alloc(u8, apprt.ipc.automation_input_max_len + 1);
    defer testing.allocator.free(payload);
    @memset(payload, 'x');
    var iter = try std.process.ArgIteratorGeneral(.{}).init(testing.allocator, payload);
    defer iter.deinit();
    var stderr = std.Io.Writer.Allocating.init(testing.allocator);
    defer stderr.deinit();

    try testing.expectEqual(
        @as(u8, 1),
        try runArgsWithPerform(testing.allocator, &iter, &stderr.writer, &Hook.perform),
    );
    try testing.expect(std.mem.indexOf(u8, stderr.written(), "payload exceeds") != null);
}
