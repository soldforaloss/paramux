const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const apprt = @import("../apprt.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    /// If set, query a custom single-instance namespace instead of the default
    /// local winghostty instance.
    class: ?[:0]const u8 = null,

    /// Read a specific pane by its `+list-windows` id. Defaults to the focused
    /// pane, or the `PARAMUX_SURFACE_ID` of the pane this command runs in.
    @"surface-id": ?u64 = null,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    /// Enables `-h` and `--help` to work.
    pub fn help(self: Options) !void {
        _ = self;
        return actionpkg.help_error;
    }
};

/// The `read-pane` command prints a pane's current viewport text from a running
/// winghostty instance, over the same IPC channel as `+list-windows`.
///
/// The default target is the focused pane, or — when run inside a pane — the
/// pane identified by the `PARAMUX_SURFACE_ID` environment variable. Use
/// `--surface-id` (a pane id from `winghostty +list-windows`) to read a
/// specific pane.
///
///   * `winghostty +read-pane`
///   * `winghostty +read-pane --surface-id=42`
///
/// This lets a script drive a workspace and read an agent's output back.
///
/// Available since: 1.2.0
pub fn run(alloc: Allocator) !u8 {
    var opts: Options = .{};
    opts._arena = ArenaAllocator.init(alloc);
    defer opts.deinit();
    const opts_alloc = opts._arena.?.allocator();

    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    {
        var iter = try args.argsIterator(alloc);
        defer iter.deinit();
        while (iter.next()) |arg| {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                return actionpkg.help_error;
            }
            if (lib.cutPrefix(u8, arg, "--class=")) |class| {
                opts.class = try opts_alloc.dupeZ(u8, std.mem.trim(u8, class, &std.ascii.whitespace));
                continue;
            }
            if (lib.cutPrefix(u8, arg, "--surface-id=")) |raw| {
                opts.@"surface-id" = std.fmt.parseInt(u64, std.mem.trim(u8, raw, &std.ascii.whitespace), 10) catch {
                    try stderr.print("+read-pane: invalid --surface-id value: {s}\n", .{raw});
                    return 1;
                };
                continue;
            }
            try stderr.print("Unknown option for +read-pane: {s}\n", .{arg});
            return 1;
        }
    }

    // Resolve the target: explicit --surface-id, else the pane's env var, else
    // the focused pane.
    const action_target: apprt.ipc.AutomationActionTarget =
        if (opts.@"surface-id" orelse readSurfaceIdEnv(opts_alloc)) |id|
            .{ .surface_id = id }
        else
            .focused;

    const text = apprt.App.performReadPane(
        alloc,
        if (opts.class) |class| .{ .class = class } else .detect,
        action_target,
    ) catch |err| {
        try stderr.print("Reading the pane via IPC failed: {}\n", .{err});
        return 1;
    } orelse {
        try stderr.print("No matching winghostty instance is listening for automation queries.\n", .{});
        return 1;
    };
    defer alloc.free(text);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(text);
    try stdout.flush();
    return 0;
}

fn readSurfaceIdEnv(alloc: Allocator) ?u64 {
    const val = std.process.getEnvVarOwned(alloc, "PARAMUX_SURFACE_ID") catch return null;
    defer alloc.free(val);
    return std.fmt.parseInt(u64, std.mem.trim(u8, val, &std.ascii.whitespace), 10) catch null;
}
