const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");
const session = @import("../apprt/win32_session_state.zig");
const gallery = @import("layout_gallery.zig");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    pub fn help(_: Options) !void {
        return actionpkg.help_error;
    }
};

const Slots = struct {
    slots: [5]?session.Tab = .{ null, null, null, null, null },
    names: [5]?[]const u8 = .{ null, null, null, null, null },
};

fn layoutsPath(alloc: Allocator) ![]u8 {
    const local = std.process.getEnvVarOwned(alloc, "LOCALAPPDATA") catch
        return error.NoLocalAppData;
    defer alloc.free(local);
    return try std.fs.path.join(alloc, &.{ local, "paramux", "layouts.json" });
}

/// Install a `.layout.json` template into a slot:
/// `paramux import-layout 2 team.layout.json [--name=api-fleet]`.
/// With no slot number the first empty slot is used (error when all
/// five are occupied). Validates the template (same rules as session
/// restore) before touching layouts.json; other slots and their
/// names are preserved.
pub fn run(alloc: Allocator) !u8 {
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var slot_arg: ?usize = null;
    var in_arg: ?[]const u8 = null;
    var name_arg: ?[]const u8 = null;
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return actionpkg.help_error;
        }
        if (lib.cutPrefix(u8, arg, "--name=")) |rest| {
            name_arg = try a.dupe(u8, rest);
            continue;
        }
        if (slot_arg == null) {
            slot_arg = std.fmt.parseInt(usize, arg, 10) catch null;
            if (slot_arg != null) continue;
        }
        if (in_arg == null) {
            in_arg = try a.dupe(u8, arg);
            continue;
        }
        try stderr.print("unexpected argument: {s}\n", .{arg});
        return 1;
    }
    const file_path = in_arg orelse {
        try stderr.print("usage: paramux import-layout [slot 1-5] <file> [--name=...]\n", .{});
        return 1;
    };
    if (slot_arg) |slot| {
        if (slot < 1 or slot > 5) {
            try stderr.print("slot must be 1-5\n", .{});
            return 1;
        }
    }

    // A bare name that isn't a readable file resolves against the
    // bundled gallery, so installed users get the docs templates too.
    const template = std.fs.cwd().readFileAlloc(a, file_path, 4 * 1024 * 1024) catch |err| blk: {
        if (gallery.get(file_path)) |embedded| break :blk try a.dupe(u8, embedded);
        try stderr.print("could not read {s} (err={})\n", .{ file_path, err });
        try stderr.print("bundled gallery names:", .{});
        for (gallery.entries) |e| try stderr.print(" {s}", .{e.name});
        try stderr.print("\n", .{});
        return 1;
    };
    const tab_parsed = std.json.parseFromSlice(session.Tab, a, stripBom(template), .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch {
        try stderr.print("{s} is not a valid layout template\n", .{file_path});
        return 1;
    };
    defer tab_parsed.deinit();
    // The same structural validation session restore applies.
    session.validateAlloc(a, .{
        .windows = &.{.{
            .selected_tab = 0,
            .tabs = &.{tab_parsed.value},
        }},
    }) catch |err| {
        try stderr.print("template rejected ({s})\n", .{@errorName(err)});
        return 1;
    };

    const path = layoutsPath(a) catch {
        try stderr.print("could not resolve layouts.json\n", .{});
        return 1;
    };
    var slots: Slots = .{};
    var existing_parsed: ?std.json.Parsed(Slots) = null;
    defer if (existing_parsed) |*parsed| parsed.deinit();
    if (std.fs.cwd().readFileAlloc(a, path, 16 * 1024 * 1024)) |raw| {
        existing_parsed = std.json.parseFromSlice(Slots, a, stripBom(raw), .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch null;
        if (existing_parsed) |parsed| slots = parsed.value;
    } else |_| {}

    // No slot given: take the first empty one instead of clobbering.
    const slot = slot_arg orelse blk: {
        for (slots.slots, 1..) |slot_opt, n| {
            if (slot_opt == null) break :blk n;
        }
        try stderr.print("all five slots are occupied; pass a slot number to overwrite one (see paramux open --list)\n", .{});
        return 1;
    };

    slots.slots[slot - 1] = tab_parsed.value;
    if (name_arg) |name| {
        slots.names[slot - 1] = name;
    } else if (slots.names[slot - 1] == null) {
        slots.names[slot - 1] = std.fs.path.stem(file_path);
    }

    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    std.json.Stringify.value(slots, .{}, &out.writer) catch return 1;
    if (std.fs.path.dirname(path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const file = std.fs.cwd().createFile(path, .{}) catch {
        try stderr.print("could not write layouts.json\n", .{});
        return 1;
    };
    defer file.close();
    file.writeAll(out.written()) catch return 1;

    try stdout.print("Imported {s} into slot {d} ({s}).\n", .{
        file_path,
        slot,
        slots.names[slot - 1] orelse "unnamed",
    });
    return 0;
}

/// Hand-edited or PowerShell-written files often carry a UTF-8
/// BOM; std.json refuses it, so strip before parsing.
fn stripBom(raw: []const u8) []const u8 {
    const bom = "\xEF\xBB\xBF";
    return if (std.mem.startsWith(u8, raw, bom)) raw[bom.len..] else raw;
}
