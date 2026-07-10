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

const PerformSendKeyFn = *const fn (
    Allocator,
    apprt.ipc.Target,
    apprt.ipc.AutomationActionTarget,
    apprt.ipc.AutomationKey,
) anyerror!bool;

/// Send one named key to a pane in a running paramux instance.
///
/// The default target is the focused pane. Use `--surface-id=<id>` for exact
/// pane routing. Supported keys are enter, tab, escape, backspace, delete,
/// up/down/left/right (or arrow-*), home, end, page-up, and page-down.
///
///   * `paramux send-key enter`
///   * `paramux send-key --surface-id=42 arrow-up`
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const result = try runArgsWithPerform(alloc, &iter, &stderr_writer.interface, performSendKey);
    try stderr_writer.interface.flush();
    return result;
}

fn performSendKey(
    alloc: Allocator,
    target: apprt.ipc.Target,
    action_target: apprt.ipc.AutomationActionTarget,
    key: apprt.ipc.AutomationKey,
) !bool {
    return try apprt.App.performSendKey(alloc, target, action_target, key);
}

fn runArgsWithPerform(
    alloc: Allocator,
    args_iter: anytype,
    stderr: *std.Io.Writer,
    perform: PerformSendKeyFn,
) !u8 {
    var opts: Options = .{ ._arena = ArenaAllocator.init(alloc) };
    defer opts.deinit();
    const opts_alloc = opts._arena.?.allocator();

    var key_name: ?[]const u8 = null;
    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) return actionpkg.help_error;
        if (lib.cutPrefix(u8, arg, "--class=")) |class| {
            opts.class = try opts_alloc.dupeZ(u8, std.mem.trim(u8, class, &std.ascii.whitespace));
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--surface-id=")) |raw| {
            opts.@"surface-id" = std.fmt.parseInt(u64, std.mem.trim(u8, raw, &std.ascii.whitespace), 10) catch {
                try stderr.print("+send-key: invalid --surface-id value: {s}\n", .{raw});
                return 1;
            };
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.print("Unknown option for +send-key: {s}\n", .{arg});
            return 1;
        }
        if (key_name != null) {
            try stderr.writeAll("+send-key accepts exactly one key.\n");
            return 1;
        }
        key_name = arg;
    }

    const raw_key = key_name orelse {
        try stderr.writeAll("+send-key requires one key.\n");
        return 1;
    };
    const key = apprt.ipc.AutomationKey.parse(raw_key) orelse {
        try stderr.print("+send-key: unknown key: {s}\n", .{raw_key});
        return 1;
    };

    const delivered = perform(
        alloc,
        if (opts.class) |class| .{ .class = class } else .detect,
        if (opts.@"surface-id") |id| .{ .surface_id = id } else .focused,
        key,
    ) catch |err| {
        try stderr.print("Sending terminal key via IPC failed: {}\n", .{err});
        return 1;
    };
    if (delivered) return 0;
    try stderr.writeAll("No matching paramux instance is listening for terminal input.\n");
    return 1;
}

test "automation-send-key-cli parses key and explicit target" {
    const testing = std.testing;
    const Hook = struct {
        fn perform(
            _: Allocator,
            target: apprt.ipc.Target,
            action_target: apprt.ipc.AutomationActionTarget,
            key: apprt.ipc.AutomationKey,
        ) !bool {
            try testing.expect(target == .detect);
            try testing.expectEqual(@as(u64, 42), action_target.surface_id);
            try testing.expectEqual(apprt.ipc.AutomationKey.arrow_up, key);
            return true;
        }
    };

    var iter = try std.process.ArgIteratorGeneral(.{}).init(
        testing.allocator,
        "--surface-id=42 arrow-up",
    );
    defer iter.deinit();
    var stderr = std.Io.Writer.Allocating.init(testing.allocator);
    defer stderr.deinit();

    try testing.expectEqual(
        @as(u8, 0),
        try runArgsWithPerform(testing.allocator, &iter, &stderr.writer, &Hook.perform),
    );
    try testing.expectEqualStrings("", stderr.written());
}

test "automation-send-key-cli defaults to focused target" {
    const testing = std.testing;
    const Hook = struct {
        fn perform(
            _: Allocator,
            _: apprt.ipc.Target,
            action_target: apprt.ipc.AutomationActionTarget,
            key: apprt.ipc.AutomationKey,
        ) !bool {
            try testing.expect(action_target == .focused);
            try testing.expectEqual(apprt.ipc.AutomationKey.enter, key);
            return true;
        }
    };

    var iter = try std.process.ArgIteratorGeneral(.{}).init(testing.allocator, "enter");
    defer iter.deinit();
    var stderr = std.Io.Writer.Allocating.init(testing.allocator);
    defer stderr.deinit();

    try testing.expectEqual(
        @as(u8, 0),
        try runArgsWithPerform(testing.allocator, &iter, &stderr.writer, &Hook.perform),
    );
}

test "automation-send-key-cli rejects unknown keys before ipc" {
    const testing = std.testing;
    const Hook = struct {
        fn perform(
            _: Allocator,
            _: apprt.ipc.Target,
            _: apprt.ipc.AutomationActionTarget,
            _: apprt.ipc.AutomationKey,
        ) !bool {
            return error.UnexpectedIpc;
        }
    };

    var iter = try std.process.ArgIteratorGeneral(.{}).init(testing.allocator, "space");
    defer iter.deinit();
    var stderr = std.Io.Writer.Allocating.init(testing.allocator);
    defer stderr.deinit();

    try testing.expectEqual(
        @as(u8, 1),
        try runArgsWithPerform(testing.allocator, &iter, &stderr.writer, &Hook.perform),
    );
    try testing.expect(std.mem.indexOf(u8, stderr.written(), "unknown key") != null);
}
