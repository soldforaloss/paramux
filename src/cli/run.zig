const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const apprt = @import("../apprt.zig");
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    _arena: ?ArenaAllocator = null,

    /// Target a custom single-instance namespace instead of the default
    /// local paramux instance.
    class: ?[:0]const u8 = null,

    /// Where the command's pane is created: `new` (default) opens a new
    /// workspace; `current` auto-places a pane in the active workspace.
    workspace: [:0]const u8 = "new",

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

/// Spawn a pane in a running paramux instance, type a command into it,
/// and print the new pane's surface id — paramux as a scriptable agent
/// launcher.
///
///   * `paramux run "claude -p \"fix the failing tests\""`
///   * `paramux run --workspace=current "npm test"`
///
/// The command is delivered as keystrokes followed by Enter, exactly as
/// if typed. The printed surface id works with `paramux send`,
/// `paramux read-pane --surface-id=<id>`, and `paramux notify`.
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
    const opts_alloc = opts._arena.?.allocator();

    var command_parts: std.ArrayListUnmanaged([]const u8) = .empty;
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
                opts.class = try opts_alloc.dupeZ(u8, class);
                continue;
            }
            if (lib.cutPrefix(u8, arg, "--workspace=")) |ws| {
                opts.workspace = try opts_alloc.dupeZ(u8, ws);
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--")) {
                try stderr.print("unknown option: {s}\n", .{arg});
                return 1;
            }
        }
        try command_parts.append(opts_alloc, try opts_alloc.dupe(u8, arg));
    }

    if (command_parts.items.len == 0) {
        try stderr.print("usage: paramux run [--workspace=new|current] [--] <command...>\n", .{});
        return 1;
    }
    const spawn_in_new = std.mem.eql(u8, opts.workspace, "new");
    if (!spawn_in_new and !std.mem.eql(u8, opts.workspace, "current")) {
        try stderr.print("--workspace must be `new` or `current`, got {s}\n", .{opts.workspace});
        return 1;
    }

    const command_text = try std.mem.join(opts_alloc, " ", command_parts.items);

    const target: apprt.ipc.Target = if (opts.class) |class|
        .{ .class = class }
    else
        .detect;

    // Snapshot the pane ids that exist before spawning, so the new
    // pane is identifiable no matter which workspace gained it.
    const before = collectSurfaceIds(opts_alloc, target) catch |err| {
        try stderr.print("could not reach a running paramux instance (err={})\n", .{err});
        return 1;
    };

    const spawn_action: []const u8 = if (spawn_in_new) "new_tab" else "new_split:auto";
    const performed = apprt.App.performAutomationAction(alloc, target, .focused, spawn_action) catch |err| {
        try stderr.print("pane spawn failed (err={})\n", .{err});
        return 1;
    };
    if (!performed) {
        try stderr.print("pane spawn was rejected by the running instance\n", .{});
        return 1;
    }

    // Wait for the new pane to appear (surface creation is async).
    var new_id: ?u64 = null;
    var attempts: usize = 0;
    while (attempts < 60) : (attempts += 1) {
        std.Thread.sleep(50 * std.time.ns_per_ms);
        const now_ids = collectSurfaceIds(opts_alloc, target) catch continue;
        for (now_ids) |id| {
            if (std.mem.indexOfScalar(u64, before, id) == null) {
                new_id = id;
                break;
            }
        }
        if (new_id != null) break;
    }
    const surface_id = new_id orelse {
        try stderr.print("timed out waiting for the new pane\n", .{});
        return 1;
    };

    // Small grace so the shell inside the pane is ready for input.
    std.Thread.sleep(300 * std.time.ns_per_ms);

    const payload = try std.fmt.allocPrint(opts_alloc, "{s}\r", .{command_text});
    const sent = apprt.App.performSend(alloc, target, .{ .surface_id = surface_id }, payload) catch |err| {
        try stderr.print("command delivery failed (err={})\n", .{err});
        return 1;
    };
    if (!sent) {
        try stderr.print("command delivery was rejected\n", .{});
        return 1;
    }

    try stdout.print("{d}\n", .{surface_id});
    return 0;
}

/// Every pane surface id in the running instance, in listing order.
pub fn collectSurfaceIds(alloc: Allocator, target: apprt.ipc.Target) ![]u64 {
    const payload = (try apprt.App.queryAutomationWindowList(alloc, target)) orelse
        return error.NoInstance;
    defer alloc.free(payload);

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{});
    defer parsed.deinit();

    var ids: std.ArrayListUnmanaged(u64) = .empty;
    const root = parsed.value;
    const windows = switch (root) {
        .object => |obj| obj.get("windows") orelse return error.BadSchema,
        else => return error.BadSchema,
    };
    switch (windows) {
        .array => |warr| for (warr.items) |win| {
            const tabs = switch (win) {
                .object => |wobj| wobj.get("tabs") orelse continue,
                else => continue,
            };
            switch (tabs) {
                .array => |tarr| for (tarr.items) |tab| {
                    const panes = switch (tab) {
                        .object => |tobj| tobj.get("panes") orelse continue,
                        else => continue,
                    };
                    switch (panes) {
                        .array => |parr| for (parr.items) |pane| {
                            const sid = switch (pane) {
                                .object => |pobj| pobj.get("surface_id") orelse continue,
                                else => continue,
                            };
                            switch (sid) {
                                .integer => |v| try ids.append(alloc, @intCast(v)),
                                else => {},
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        },
        else => return error.BadSchema,
    }
    return try ids.toOwnedSlice(alloc);
}

/// Pane surface ids of the ACTIVE workspace in the focused window.
pub fn collectActiveTabSurfaceIds(alloc: Allocator, target: apprt.ipc.Target) ![]u64 {
    const payload = (try apprt.App.queryAutomationWindowList(alloc, target)) orelse
        return error.NoInstance;
    defer alloc.free(payload);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{});
    defer parsed.deinit();

    var ids: std.ArrayListUnmanaged(u64) = .empty;
    const windows = parsed.value.object.get("windows") orelse return error.BadSchema;
    for (windows.array.items) |win| {
        const focused = if (win.object.get("focused")) |v| v.bool else false;
        if (!focused) continue;
        const tabs = win.object.get("tabs") orelse continue;
        for (tabs.array.items) |tab| {
            const active = if (tab.object.get("active")) |v| v.bool else false;
            if (!active) continue;
            const panes = tab.object.get("panes") orelse continue;
            for (panes.array.items) |pane| {
                if (pane.object.get("surface_id")) |sid| {
                    switch (sid) {
                        .integer => |v| try ids.append(alloc, @intCast(v)),
                        else => {},
                    }
                }
            }
        }
    }
    return try ids.toOwnedSlice(alloc);
}

test "run rejects empty command" {
    const t = std.testing;
    var iter = args.sliceIterator(&.{});
    var out_buf: [64]u8 = undefined;
    var err_buf: [256]u8 = undefined;
    var out = std.Io.Writer.fixed(&out_buf);
    var errw = std.Io.Writer.fixed(&err_buf);
    const code = try runArgs(t.allocator, &iter, &out, &errw);
    try t.expectEqual(@as(u8, 1), code);
}

test "run rejects a bad workspace value" {
    const t = std.testing;
    var iter = args.sliceIterator(&.{ "--workspace=sideways", "echo", "hi" });
    var out_buf: [64]u8 = undefined;
    var err_buf: [256]u8 = undefined;
    var out = std.Io.Writer.fixed(&out_buf);
    var errw = std.Io.Writer.fixed(&err_buf);
    const code = try runArgs(t.allocator, &iter, &out, &errw);
    try t.expectEqual(@as(u8, 1), code);
}
