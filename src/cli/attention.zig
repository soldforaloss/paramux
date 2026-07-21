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

    /// Print the durable transition log instead of the live snapshot,
    /// set with `--log`. No running instance required. `--limit=N`
    /// caps the lines printed (default 50, newest last).
    log: bool = false,
    limit: u32 = 50,

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
        if (std.mem.eql(u8, arg, "--log")) {
            opts.log = true;
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--limit=")) |rest| {
            const n = std.fmt.parseInt(u32, rest, 10) catch 0;
            opts.limit = std.math.clamp(n, 1, 10_000);
            continue;
        }
        try stderr.print("unknown option: {s}\n", .{arg});
        return 1;
    }

    if (opts.log) return printLogTail(a, stdout, stderr, opts.limit);

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

/// Tail of the durable transition log. Reads the .1 generation too
/// when the current file is shorter than the requested limit.
fn printLogTail(
    a: Allocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    limit: u32,
) !u8 {
    const local = std.process.getEnvVarOwned(a, "LOCALAPPDATA") catch {
        try stderr.print("LOCALAPPDATA is not set\n", .{});
        return 1;
    };
    const path = try std.fs.path.join(a, &.{ local, "paramux", "attention-history.jsonl" });

    var lines: std.ArrayListUnmanaged([]const u8) = .empty;
    const old_path = try std.fmt.allocPrint(a, "{s}.1", .{path});
    for ([_][]const u8{ old_path, path }) |p| {
        const raw = std.fs.cwd().readFileAlloc(a, p, 16 * 1024 * 1024) catch continue;
        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            try lines.append(a, line);
        }
    }
    if (lines.items.len == 0) {
        try stderr.print("no attention history yet ({s})\n", .{path});
        return 1;
    }
    const start = lines.items.len -| limit;
    for (lines.items[start..]) |line| try stdout.print("{s}\n", .{line});
    return 0;
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
