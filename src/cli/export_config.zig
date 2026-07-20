const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    _arena: ?ArenaAllocator = null,

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

/// Copy this machine's paramux setup — the config file, saved layout
/// slots, session states, and any custom themes — into a folder you
/// can back up or carry to another machine. Restoring is the reverse:
/// copy the files back into `%LOCALAPPDATA%\paramux`.
///
///   * `paramux export-config C:\backup\paramux-setup`
pub fn run(alloc: Allocator) !u8 {
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();

    var stdout_buf: [2048]u8 = undefined;
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

    var dest_arg: ?[]const u8 = null;
    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return actionpkg.help_error;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            try stderr.print("unknown option: {s}\n", .{arg});
            return 1;
        }
        if (dest_arg != null) {
            try stderr.print("export-config takes exactly one destination folder\n", .{});
            return 1;
        }
        dest_arg = try a.dupe(u8, arg);
    }
    const dest = dest_arg orelse {
        try stderr.print("usage: paramux export-config <destination-folder>\n", .{});
        return 1;
    };

    const local = std.process.getEnvVarOwned(a, "LOCALAPPDATA") catch {
        try stderr.print("LOCALAPPDATA is not set\n", .{});
        return 1;
    };
    const src_root = try std.fs.path.join(a, &.{ local, "paramux" });

    std.fs.cwd().makePath(dest) catch |err| {
        try stderr.print("could not create {s} (err={})\n", .{ dest, err });
        return 1;
    };
    var dest_dir = std.fs.cwd().openDir(dest, .{}) catch |err| {
        try stderr.print("could not open {s} (err={})\n", .{ dest, err });
        return 1;
    };
    defer dest_dir.close();
    var src_dir = std.fs.openDirAbsolute(src_root, .{ .iterate = true }) catch |err| {
        try stderr.print("no paramux data folder at {s} (err={})\n", .{ src_root, err });
        return 1;
    };
    defer src_dir.close();

    // The setup set: config, layouts, session states, custom themes.
    // Never the IPC token, crash dumps, logs, or update staging.
    var copied: usize = 0;
    var it = src_dir.iterate();
    while (try it.next()) |entry| {
        const want = switch (entry.kind) {
            .file => std.mem.eql(u8, entry.name, "config.ghostty") or
                std.mem.eql(u8, entry.name, "layouts.json") or
                std.mem.startsWith(u8, entry.name, "session-state"),
            .directory => std.mem.eql(u8, entry.name, "themes"),
            else => false,
        };
        if (!want) continue;
        switch (entry.kind) {
            .file => {
                src_dir.copyFile(entry.name, dest_dir, entry.name, .{}) catch |err| {
                    try stderr.print("skip {s} (err={})\n", .{ entry.name, err });
                    continue;
                };
                copied += 1;
                try stdout.print("copied {s}\n", .{entry.name});
            },
            .directory => {
                dest_dir.makePath(entry.name) catch continue;
                var sub_src = src_dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                defer sub_src.close();
                var sub_dest = dest_dir.openDir(entry.name, .{}) catch continue;
                defer sub_dest.close();
                var sub_it = sub_src.iterate();
                while (try sub_it.next()) |sub| {
                    if (sub.kind != .file) continue;
                    sub_src.copyFile(sub.name, sub_dest, sub.name, .{}) catch continue;
                    copied += 1;
                }
                try stdout.print("copied {s}/\n", .{entry.name});
            },
            else => {},
        }
    }

    if (copied == 0) {
        try stdout.print("Nothing to export yet ({s} has no config/layouts/sessions/themes).\n", .{src_root});
        return 0;
    }
    try stdout.print("Exported {d} file(s) to {s}. Restore by copying them back into %LOCALAPPDATA%\\paramux.\n", .{ copied, dest });
    return 0;
}
