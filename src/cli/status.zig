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

    /// Re-render the table every 2 seconds until interrupted.
    watch: bool = false,

    /// Seconds between --watch re-renders (1-60, default 2).
    interval: u32 = 2,

    /// Also print each workspace's scratch note (its own line, so the
    /// default table stays machine-countable).
    notes: bool = false,

    /// Print the raw paramux.windows.v2 JSON payload instead of the
    /// table (one verb for humans and scripts alike).
    json: bool = false,

    /// Omit the column-header row (script-friendly output).
    @"no-header": bool = false,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

/// Print the fleet as a table: every workspace and pane with its
/// attention state and reported token total. `--watch` re-renders
/// every 2 seconds. For machine-readable output use
/// `paramux list-windows` (the same data as JSON).
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();

    var stdout_buf: [4096]u8 = undefined;
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
        if (lib.cutPrefix(u8, arg, "--interval=")) |rest| {
            const n = std.fmt.parseInt(u32, rest, 10) catch 0;
            opts.interval = std.math.clamp(n, 1, 60);
            continue;
        }
        if (std.mem.eql(u8, arg, "--notes")) {
            opts.notes = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            opts.json = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--watch")) {
            opts.watch = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-header")) {
            opts.@"no-header" = true;
            continue;
        }
        try stderr.print("unknown option: {s}\n", .{arg});
        return 1;
    }

    const target: apprt.ipc.Target = if (opts.class) |class| .{ .class = class } else .detect;

    if (opts.watch) {
        while (true) {
            // ANSI clear + home keeps the table stable in place.
            try stdout.writeAll("\x1b[2J\x1b[H");
            const code = try renderOnce(alloc, a, target, stdout, stderr, opts.@"no-header", opts.notes, opts.json);
            try stdout.flush();
            if (code != 0) return code;
            std.Thread.sleep(@as(u64, opts.interval) * std.time.ns_per_s);
        }
    }
    return renderOnce(alloc, a, target, stdout, stderr, opts.@"no-header", opts.notes, opts.json);
}

fn renderOnce(
    alloc: Allocator,
    a: Allocator,
    target: apprt.ipc.Target,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    no_header: bool,
    show_notes: bool,
    show_json: bool,
) !u8 {
    const payload = (apprt.App.queryAutomationWindowList(alloc, target) catch |err| {
        try stderr.print("could not reach a running paramux instance (err={})\n", .{err});
        return 1;
    }) orelse {
        try stderr.print("no running paramux instance found\n", .{});
        return 1;
    };
    defer alloc.free(payload);

    if (show_json) {
        try stdout.print("{s}\n", .{payload});
        return 0;
    }

    var parsed = std.json.parseFromSlice(std.json.Value, a, payload, .{}) catch {
        try stderr.print("unexpected list-windows payload\n", .{});
        return 1;
    };
    defer parsed.deinit();

    if (!no_header) {
        try stdout.print("{s:<10} {s:<20} {s:<10} {s:<10} {s}\n", .{ "WORKSPACE", "SURFACE", "STATE", "TOKENS", "FLAGS" });
    }
    const windows = parsed.value.object.get("windows") orelse return 1;
    for (windows.array.items) |win| {
        const tabs = win.object.get("tabs") orelse continue;
        for (tabs.array.items, 0..) |tab, ti| {
            if (show_notes) {
                if (tab.object.get("note")) |note_val| {
                    if (note_val == .string and note_val.string.len > 0) {
                        try stdout.print("# workspace {d} note: {s}\n", .{ ti + 1, note_val.string });
                    }
                }
            }
            const panes = tab.object.get("panes") orelse continue;
            for (panes.array.items) |pane| {
                const obj = pane.object;
                const sid: i64 = if (obj.get("surface_id")) |v| v.integer else 0;
                const state: []const u8 = if (obj.get("attention")) |v| v.string else "none";
                const tokens: i64 = if (obj.get("tokens")) |v| v.integer else 0;
                const focused = if (obj.get("focused")) |v| v.bool else false;
                const active = if (obj.get("active")) |v| v.bool else false;
                const flags: []const u8 = if (active) "active" else if (focused) "focused" else "";
                // Numbers render via bufPrint first: Zig 0.15's numeric
                // alignment specs prepend a sign, strings do not.
                var ws_buf: [16]u8 = undefined;
                var sid_buf: [24]u8 = undefined;
                var tok_buf: [24]u8 = undefined;
                const ws_s = std.fmt.bufPrint(&ws_buf, "{d}", .{ti + 1}) catch "?";
                const sid_s = std.fmt.bufPrint(&sid_buf, "{d}", .{sid}) catch "?";
                const tok_s = std.fmt.bufPrint(&tok_buf, "{d}", .{tokens}) catch "?";
                try stdout.print("{s:<10} {s:<20} {s:<10} {s:<10} {s}\n", .{ ws_s, sid_s, state, tok_s, flags });
            }
        }
    }
    return 0;
}
