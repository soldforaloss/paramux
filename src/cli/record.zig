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

    /// The pane to record; defaults to `PARAMUX_SURFACE_ID` when run
    /// inside a pane.
    @"surface-id": ?u64 = null,

    /// Output .cast path (asciinema v2). Defaults to a timestamped
    /// `paramux-<unix>.cast` so back-to-back recordings never clobber
    /// each other silently.
    out: ?[:0]const u8 = null,

    /// Seconds to record (0 = until Ctrl+C, max 3600).
    seconds: u32 = 30,

    /// Cap idle gaps in the cast at this many seconds (asciinema's
    /// `idle_time_limit`; 0 = keep real gaps). Long quiet stretches
    /// between agent bursts play back at this pace instead.
    @"idle-limit": u32 = 0,

    /// Suppress the summary line (scripts that only want the exit code).
    quiet: bool = false,

    /// Header canvas size for players (the capture itself is plain
    /// text). Defaults match a comfortable 120x30.
    width: u16 = 120,
    height: u16 = 30,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

/// Record a pane's visible text into an asciinema v2 `.cast` file by
/// sampling twice a second. Each sample paints the full screen
/// (clear + text), so playback shows the pane exactly as it evolved —
/// an honest, dependency-free way to capture an agent run.
///
///   * `paramux record --surface-id=42 --out=run.cast --seconds=60`
///   * inside a pane: `paramux record --out=me.cast`
///   * `--idle-limit=2` caps quiet stretches at 2s on playback
///
/// Play with `asciinema play run.cast` or any web player.
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const result = runArgs(alloc, &iter, &stdout_writer.interface, &stderr_writer.interface);
    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    return result;
}

fn runArgs(
    alloc: Allocator,
    args_iter: anytype,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var opts: Options = .{ ._arena = ArenaAllocator.init(alloc) };
    defer opts.deinit();
    const a = opts._arena.?.allocator();

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return actionpkg.help_error;
        }
        if (lib.cutPrefix(u8, arg, "--class=")) |class| {
            opts.class = try a.dupeZ(u8, class);
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--surface-id=")) |rest| {
            opts.@"surface-id" = std.fmt.parseInt(u64, rest, 10) catch {
                try stderr.print("bad --surface-id value: {s}\n", .{rest});
                return 1;
            };
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--out=")) |rest| {
            opts.out = try a.dupeZ(u8, rest);
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--seconds=")) |rest| {
            opts.seconds = std.fmt.parseInt(u32, rest, 10) catch {
                try stderr.print("bad --seconds value: {s}\n", .{rest});
                return 1;
            };
            continue;
        }
        if (std.mem.eql(u8, arg, "--quiet")) {
            opts.quiet = true;
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--width=")) |rest| {
            opts.width = std.fmt.parseInt(u16, rest, 10) catch opts.width;
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--height=")) |rest| {
            opts.height = std.fmt.parseInt(u16, rest, 10) catch opts.height;
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--idle-limit=")) |rest| {
            opts.@"idle-limit" = std.fmt.parseInt(u32, rest, 10) catch {
                try stderr.print("bad --idle-limit value: {s}\n", .{rest});
                return 1;
            };
            continue;
        }
        try stderr.print("unknown option: {s}\n", .{arg});
        return 1;
    }

    const surface_id: u64 = opts.@"surface-id" orelse blk: {
        const val = std.process.getEnvVarOwned(a, "PARAMUX_SURFACE_ID") catch {
            try stderr.print("no --surface-id and not inside a paramux pane\n", .{});
            return 1;
        };
        break :blk std.fmt.parseInt(u64, std.mem.trim(u8, val, &std.ascii.whitespace), 10) catch {
            try stderr.print("PARAMUX_SURFACE_ID is unreadable\n", .{});
            return 1;
        };
    };
    const seconds = @min(if (opts.seconds == 0) 3600 else opts.seconds, 3600);
    const out_path: [:0]const u8 = opts.out orelse
        try std.fmt.allocPrintSentinel(a, "paramux-{d}.cast", .{std.time.timestamp()}, 0);
    const target: apprt.ipc.Target = if (opts.class) |class| .{ .class = class } else .detect;

    const file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
        try stderr.print("could not create {s} (err={})\n", .{ out_path, err });
        return 1;
    };
    defer file.close();
    var fbuf: [8192]u8 = undefined;
    var fw = file.writer(&fbuf);
    const w = &fw.interface;

    // asciinema v2 header. 120x30 is a truthful-enough canvas for
    // paramux's read-pane text; players reflow.
    if (opts.@"idle-limit" > 0) {
        try w.print(
            "{{\"version\": 2, \"width\": {d}, \"height\": {d}, \"idle_time_limit\": {d}, \"title\": \"paramux pane\"}}\n",
            .{ opts.width, opts.height, opts.@"idle-limit" },
        );
    } else {
        try w.print(
            "{{\"version\": 2, \"width\": {d}, \"height\": {d}, \"title\": \"paramux pane\"}}\n",
            .{ opts.width, opts.height },
        );
    }

    var timer = try std.time.Timer.start();
    var last: []u8 = try a.dupe(u8, "");
    var frames: usize = 0;
    const interval_ns = 500 * std.time.ns_per_ms;
    const budget_ns = @as(u64, seconds) * std.time.ns_per_s;
    while (timer.read() < budget_ns) {
        const text = apprt.App.performReadPane(alloc, target, .{ .surface_id = surface_id }) catch null;
        if (text) |data| {
            defer alloc.free(data);
            if (!std.mem.eql(u8, data, last)) {
                a.free(last);
                last = try a.dupe(u8, data);
                const ts_ms = timer.read() / std.time.ns_per_ms;
                // Full repaint per changed sample: clear, home, text.
                const painted = try std.fmt.allocPrint(alloc, "\x1b[2J\x1b[H{s}", .{data});
                defer alloc.free(painted);
                try w.print("[{d}.{d:0>3}, \"o\", ", .{ ts_ms / 1000, ts_ms % 1000 });
                try std.json.Stringify.value(painted, .{}, w);
                try w.writeAll("]\n");
                frames += 1;
            }
        }
        std.Thread.sleep(interval_ns);
    }
    try w.flush();
    if (!opts.quiet) {
        try stdout.print("Wrote {s} ({d} frames, {d}s).\n", .{ out_path, frames, seconds });
    }
    return 0;
}
