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

    /// Re-print the timeline every `--interval` seconds (default 5),
    /// set with `--watch`. Ctrl+C stops.
    watch: bool = false,
    interval: u32 = 5,

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
        if (std.mem.eql(u8, arg, "--watch")) {
            opts.watch = true;
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--interval=")) |rest| {
            const n = std.fmt.parseInt(u32, rest, 10) catch 0;
            opts.interval = std.math.clamp(n, 1, 60);
            continue;
        }
        try stderr.print("unknown option: {s}\n", .{arg});
        return 1;
    }

    const target: apprt.ipc.Target = if (opts.class) |class| .{ .class = class } else .detect;
    if (opts.watch) {
        while (true) {
            try stdout.writeAll("\x1b[2J\x1b[H");
            const code = try printOnce(alloc, target, stdout, stderr);
            try stdout.flush();
            if (code != 0) return code;
            std.Thread.sleep(@as(u64, opts.interval) * std.time.ns_per_s);
        }
    }
    return printOnce(alloc, target, stdout, stderr);
}

fn printOnce(
    alloc: Allocator,
    target: apprt.ipc.Target,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
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
