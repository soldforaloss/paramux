const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const apprt = @import("../apprt.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    _arena: ?ArenaAllocator = null,
    class: ?[:0]const u8 = null,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

/// Print every pane's attention timeline as JSON — the CLI twin of
/// `GET /attention` on `paramux serve`, over the same token-gated
/// IPC method. Timelines hold each pane's 8 most recent transitions.
///
///   paramux attention | jq ".panes[].events"
///
/// Available since: 1.4.0
pub fn run(alloc: Allocator) !u8 {
    var opts: Options = .{ ._arena = ArenaAllocator.init(alloc) };
    defer opts.deinit();
    const a = opts._arena.?.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var iter = try args.argsIterator(alloc);
    defer iter.deinit();
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return actionpkg.help_error;
        }
        if (lib.cutPrefix(u8, arg, "--class=")) |class| {
            opts.class = try a.dupeZ(u8, class);
            continue;
        }
        try stderr.print("unknown option: {s}\n", .{arg});
        return 1;
    }

    const target: apprt.ipc.Target = if (opts.class) |class| .{ .class = class } else .detect;
    const json = (apprt.App.performReadAttention(alloc, target) catch |err| {
        try stderr.print("could not reach a running paramux instance (err={})\n", .{err});
        return 1;
    }) orelse {
        try stderr.print("no running paramux instance found\n", .{});
        return 1;
    };
    defer alloc.free(json);
    try stdout.print("{s}\n", .{json});
    return 0;
}
