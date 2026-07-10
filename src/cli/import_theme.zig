const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");

pub const Options = struct {
    /// This is set by the CLI parser for deinit.
    _arena: ?ArenaAllocator = null,

    /// The scheme name to import, when the input file contains multiple schemes
    /// (a Windows Terminal `settings.json`). Set with `--scheme=<name>`.
    scheme: ?[]const u8 = null,

    /// The input file path (a Windows Terminal `settings.json` or a single
    /// color-scheme JSON object). Collected as the positional argument.
    _file: ?[]const u8 = null,

    pub fn parseManuallyHook(
        self: *Options,
        alloc: Allocator,
        arg: []const u8,
        iter: anytype,
    ) Allocator.Error!bool {
        try self.consume(alloc, arg);
        while (iter.next()) |param| try self.consume(alloc, param);
        return false;
    }

    fn consume(self: *Options, alloc: Allocator, arg: []const u8) Allocator.Error!void {
        if (lib.cutPrefix(u8, arg, "--scheme=")) |rest| {
            self.scheme = try alloc.dupe(u8, rest);
            return;
        }
        if (self._file == null) self._file = try alloc.dupe(u8, arg);
    }

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return actionpkg.help_error;
    }
};

/// Windows Terminal scheme key -> paramux config line. Ordered: the ANSI
/// palette (0-15) then the surface colors.
const AnsiKey = struct { key: []const u8, index: u8 };
const ansi_keys = [_]AnsiKey{
    .{ .key = "black", .index = 0 },
    .{ .key = "red", .index = 1 },
    .{ .key = "green", .index = 2 },
    .{ .key = "yellow", .index = 3 },
    .{ .key = "blue", .index = 4 },
    .{ .key = "purple", .index = 5 },
    .{ .key = "cyan", .index = 6 },
    .{ .key = "white", .index = 7 },
    .{ .key = "brightBlack", .index = 8 },
    .{ .key = "brightRed", .index = 9 },
    .{ .key = "brightGreen", .index = 10 },
    .{ .key = "brightYellow", .index = 11 },
    .{ .key = "brightBlue", .index = 12 },
    .{ .key = "brightPurple", .index = 13 },
    .{ .key = "brightCyan", .index = 14 },
    .{ .key = "brightWhite", .index = 15 },
};

/// The `import-theme` command converts a Windows Terminal color scheme into a
/// paramux theme (which is just a config file: `palette`, `background`,
/// `foreground`, etc.). Print it and redirect it into a theme file, e.g.:
///
///     paramux import-theme settings.json --scheme="One Half Dark" > OneHalfDark
///
/// The input may be a Windows Terminal `settings.json` (which has a top-level
/// `schemes` array — use `--scheme` to pick one, or omit it if there is exactly
/// one) or a single scheme JSON object.
///
/// Drop the output into `themes/` under your config directory, then set
/// `theme = <name>` in your config.
///
/// Available since: 1.2.0
pub fn run(alloc: Allocator) !u8 {
    var opts: Options = .{};
    defer opts.deinit();

    {
        var iter = try args.argsIterator(alloc);
        defer iter.deinit();
        try args.parse(Options, alloc, &opts, &iter);
    }

    var arena_state = ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    const file = opts._file orelse {
        try stderr.writeAll("+import-theme requires a Windows Terminal settings.json or scheme file.\n");
        return 1;
    };

    const data = std.fs.cwd().readFileAlloc(arena, file, 8 * 1024 * 1024) catch |err| {
        try stderr.print("Could not read {s}: {}\n", .{ file, err });
        return 1;
    };

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, data, .{}) catch |err| {
        try stderr.print("Could not parse JSON from {s}: {}\n", .{ file, err });
        return 1;
    };

    const scheme = (selectScheme(parsed, opts.scheme, stderr) catch return 1) orelse {
        try stderr.print("{s} does not contain a Windows Terminal color scheme.\n", .{file});
        return 1;
    };

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&out_buf);
    const out = &stdout_writer.interface;

    if (scheme.object.get("name")) |name| {
        if (name == .string) try out.print("# Imported from Windows Terminal scheme \"{s}\"\n", .{name.string});
    }
    try writeColor(out, scheme, "background", "background");
    try writeColor(out, scheme, "foreground", "foreground");
    try writeColor(out, scheme, "cursorColor", "cursor-color");
    try writeColor(out, scheme, "selectionBackground", "selection-background");
    for (ansi_keys) |ak| {
        if (getHex(scheme, ak.key)) |hex| {
            try out.print("palette = {d}={s}\n", .{ ak.index, hex });
        }
    }
    try out.flush();
    return 0;
}

/// Pick the scheme object: a top-level `schemes` array (matched by `--scheme`,
/// or the sole entry), else the value itself if it looks like a scheme.
fn selectScheme(value: std.json.Value, want: ?[]const u8, stderr: *std.Io.Writer) !?std.json.Value {
    if (value == .object) {
        if (value.object.get("schemes")) |schemes_val| {
            if (schemes_val != .array) return null;
            const schemes = schemes_val.array.items;
            if (want) |name| {
                for (schemes) |s| {
                    if (s == .object) if (s.object.get("name")) |n| {
                        if (n == .string and std.mem.eql(u8, n.string, name)) return s;
                    };
                }
                try stderr.print("No scheme named \"{s}\" in the file.\n", .{name});
                return error.NotFound;
            }
            if (schemes.len == 1) return schemes[0];
            try stderr.writeAll("The file has multiple schemes; pick one with --scheme=<name>:\n");
            for (schemes) |s| {
                if (s == .object) if (s.object.get("name")) |n| {
                    if (n == .string) try stderr.print("  {s}\n", .{n.string});
                };
            }
            return error.Ambiguous;
        }
        // A bare scheme object (has color keys directly).
        return value;
    }
    return null;
}

fn getHex(scheme: std.json.Value, key: []const u8) ?[]const u8 {
    const v = scheme.object.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

fn writeColor(out: *std.Io.Writer, scheme: std.json.Value, wt_key: []const u8, cfg_key: []const u8) !void {
    if (getHex(scheme, wt_key)) |hex| try out.print("{s} = {s}\n", .{ cfg_key, hex });
}
