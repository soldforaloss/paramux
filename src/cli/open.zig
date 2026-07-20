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
/// (A `.paramux/layout` project file is planned to seed the workspace's
/// split layout; today the workspace opens with the standard defaults.)
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

    const performed = apprt.App.performAutomationAction(alloc, target, .focused, "new_tab") catch |err| {
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
