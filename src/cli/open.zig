const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const apprt = @import("../apprt.zig");
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");
const run_helpers = @import("run.zig");

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

/// Open a directory as a new workspace in the running paramux instance:
/// `paramux open .` from a project folder creates a workspace whose
/// shell starts there. Prints the new pane's surface id.
///
/// A `.paramux/layout` file in the directory (layouts.json slot format)
/// is installed into slot 5 and applied instead of a plain workspace,
/// so `paramux open .` can start a whole agent formation.
///
/// `--list` prints the five layout slots (pane counts and commands)
/// plus whether the current directory carries a project layout.
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

    var dir_arg: ?[]const u8 = null;
    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return actionpkg.help_error;
        }
        if (lib.cutPrefix(u8, arg, "--class=")) |class| {
            opts.class = try a.dupeZ(u8, class);
            continue;
        }
        if (std.mem.eql(u8, arg, "--list")) {
            return try listLayoutSlots(a, stdout);
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            try stderr.print("unknown option: {s}\n", .{arg});
            return 1;
        }
        if (dir_arg != null) {
            try stderr.print("open takes at most one directory\n", .{});
            return 1;
        }
        dir_arg = try a.dupe(u8, arg);
    }

    // Resolve the directory to an absolute path so the cd works no
    // matter where the pane's shell starts.
    const rel = dir_arg orelse ".";
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs = std.fs.cwd().realpath(rel, &path_buf) catch {
        try stderr.print("directory not found: {s}\n", .{rel});
        return 1;
    };

    const target: apprt.ipc.Target = if (opts.class) |class| .{ .class = class } else .detect;

    const before = run_helpers.collectSurfaceIds(a, target) catch |err| {
        try stderr.print("could not reach a running paramux instance (err={})\n", .{err});
        return 1;
    };

    // Project layout seeding: a .paramux/layout file (the layouts.json
    // slot format) is installed into slot 5 and applied instead of a
    // plain workspace.
    var project_layout = false;
    {
        var layout_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const layout_path = std.fmt.bufPrint(&layout_path_buf, "{s}/.paramux/layout", .{abs}) catch null;
        if (layout_path) |lp| {
            if (std.fs.cwd().readFileAlloc(a, lp, 4 * 1024 * 1024)) |layout_json| {
                if (installProjectLayoutSlot(a, layout_json)) {
                    project_layout = true;
                } else |err| {
                    try stderr.print("warning: .paramux/layout ignored (err={})\n", .{err});
                }
            } else |_| {}
        }
    }

    const spawn_action: []const u8 = if (project_layout) "apply_layout:5" else "new_tab";
    const performed = apprt.App.performAutomationAction(alloc, target, .focused, spawn_action) catch |err| {
        try stderr.print("workspace spawn failed (err={})\n", .{err});
        return 1;
    };
    if (!performed) {
        try stderr.print("workspace spawn was rejected\n", .{});
        return 1;
    }

    var new_id: ?u64 = null;
    var attempts: usize = 0;
    while (attempts < 60) : (attempts += 1) {
        std.Thread.sleep(50 * std.time.ns_per_ms);
        const now_ids = run_helpers.collectSurfaceIds(a, target) catch continue;
        for (now_ids) |id| {
            if (std.mem.indexOfScalar(u64, before, id) == null) {
                new_id = id;
                break;
            }
        }
        if (new_id != null) break;
    }
    const surface_id = new_id orelse {
        try stderr.print("timed out waiting for the new workspace\n", .{});
        return 1;
    };

    std.Thread.sleep(300 * std.time.ns_per_ms);
    const payload = try std.fmt.allocPrint(a, "cd \"{s}\"\r", .{abs});
    _ = apprt.App.performSend(alloc, target, .{ .surface_id = surface_id }, payload) catch {};

    try stdout.print("{d}\n", .{surface_id});
    return 0;
}


/// Validate the project layout JSON as a session Tab and write it into
/// layouts.json slot 5 (the "project slot").
fn installProjectLayoutSlot(alloc: Allocator, layout_json: []const u8) !void {
    const session = @import("../apprt/win32_session_state.zig");
    const parsed = try std.json.parseFromSlice(session.Tab, alloc, layout_json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const local = std.process.getEnvVarOwned(alloc, "LOCALAPPDATA") catch return error.NoLocalAppData;
    defer alloc.free(local);
    const path = try std.fs.path.join(alloc, &.{ local, "paramux", "layouts.json" });
    defer alloc.free(path);

    const Slots = struct { slots: [5]?session.Tab = .{ null, null, null, null, null } };
    var slots: Slots = .{};
    if (std.fs.cwd().readFileAlloc(alloc, path, 16 * 1024 * 1024)) |raw| {
        defer alloc.free(raw);
        if (std.json.parseFromSlice(Slots, alloc, raw, .{ .ignore_unknown_fields = true })) |existing| {
            defer existing.deinit();
            slots = existing.value;
            slots.slots[4] = parsed.value;
            return writeSlots(alloc, path, slots);
        } else |_| {}
    } else |_| {}
    slots.slots[4] = parsed.value;
    return writeSlots(alloc, path, slots);
}

fn writeSlots(alloc: Allocator, path: []const u8, slots: anytype) !void {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    try std.json.Stringify.value(slots, .{}, &out.writer);
    if (std.fs.path.dirname(path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(out.written());
}

/// `open --list`: print the five layout slots (pane and command
/// counts) and whether the current directory carries a
/// `.paramux/layout` project file. Reads layouts.json directly — no
/// running instance required.
fn listLayoutSlots(alloc: Allocator, stdout: *std.Io.Writer) !u8 {
    const session = @import("../apprt/win32_session_state.zig");
    const Slots = struct { slots: [5]?session.Tab = .{ null, null, null, null, null } };

    var slots: Slots = .{};
    var parsed_opt: ?std.json.Parsed(Slots) = null;
    defer if (parsed_opt) |*parsed| parsed.deinit();

    read: {
        const local = std.process.getEnvVarOwned(alloc, "LOCALAPPDATA") catch break :read;
        defer alloc.free(local);
        const path = std.fs.path.join(alloc, &.{ local, "paramux", "layouts.json" }) catch break :read;
        defer alloc.free(path);
        const raw = std.fs.cwd().readFileAlloc(alloc, path, 16 * 1024 * 1024) catch break :read;
        defer alloc.free(raw);
        parsed_opt = std.json.parseFromSlice(Slots, alloc, raw, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch break :read;
        slots = parsed_opt.?.value;
    }

    for (slots.slots, 1..) |slot_opt, n| {
        if (slot_opt) |tab| {
            var panes: usize = 0;
            var commands: usize = 0;
            for (tab.layout.nodes) |node| switch (node) {
                .pane => |pane| {
                    panes += 1;
                    if (pane.command != null) commands += 1;
                },
                .split => {},
            };
            try stdout.print("slot {d}: {d} pane(s)", .{ n, panes });
            if (commands > 0) try stdout.print(", {d} with commands", .{commands});
            try stdout.print("\n", .{});
        } else {
            try stdout.print("slot {d}: <empty>\n", .{n});
        }
    }

    const has_project = if (std.fs.cwd().access(".paramux/layout", .{})) true else |_| false;
    if (has_project) {
        try stdout.print("project layout (.paramux/layout): present — `paramux open .` installs it to slot 5\n", .{});
    } else {
        try stdout.print("project layout (.paramux/layout): none\n", .{});
    }
    return 0;
}
