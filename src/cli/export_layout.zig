const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const actionpkg = @import("action.zig");
const args = @import("args.zig");
const lib = @import("../lib/main.zig");
const session = @import("../apprt/win32_session_state.zig");

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

/// Write a saved layout slot as a standalone `.layout.json` template:
/// `paramux export-layout 2 team.layout.json` (file omitted = stdout);
/// `--name=<slot name>` picks the slot by its saved name instead;
/// `--all=<dir>` writes every occupied slot as `slotN-<name>.layout.json`.
/// The output is exactly the project-layout / gallery format, so it
/// round-trips through `.paramux/layout` and `import-layout`.
pub fn run(alloc: Allocator) !u8 {
    var arena = ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var slot_arg: ?usize = null;
    var name_arg: ?[]const u8 = null;
    var out_arg: ?[]const u8 = null;
    var all_dir: ?[]const u8 = null;
    var iter = try args.argsIterator(alloc);
    defer iter.deinit();
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return actionpkg.help_error;
        }
        if (lib.cutPrefix(u8, arg, "--all=")) |rest| {
            all_dir = try a.dupe(u8, rest);
            continue;
        }
        if (lib.cutPrefix(u8, arg, "--name=")) |rest| {
            name_arg = try a.dupe(u8, rest);
            continue;
        }
        if (slot_arg == null) {
            slot_arg = std.fmt.parseInt(usize, arg, 10) catch null;
            if (slot_arg != null) continue;
        }
        if (out_arg == null) {
            out_arg = try a.dupe(u8, arg);
            continue;
        }
        try stderr.print("unexpected argument: {s}\n", .{arg});
        return 1;
    }
    if (all_dir) |dir_path| return exportAll(a, stdout, stderr, dir_path);

    if (slot_arg == null and name_arg == null) {
        try stderr.print("usage: paramux export-layout <slot 1-5 | --name=...> [file]\n", .{});
        return 1;
    }
    if (slot_arg) |slot| {
        if (slot < 1 or slot > 5) {
            try stderr.print("slot must be 1-5\n", .{});
            return 1;
        }
    }

    const path = layoutsPath(a) catch {
        try stderr.print("could not resolve layouts.json\n", .{});
        return 1;
    };
    const raw = std.fs.cwd().readFileAlloc(a, path, 16 * 1024 * 1024) catch {
        try stderr.print("no layouts.json yet (save a layout first)\n", .{});
        return 1;
    };
    const parsed = std.json.parseFromSlice(Slots, a, stripBom(raw), .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch {
        try stderr.print("layouts.json is unreadable\n", .{});
        return 1;
    };
    defer parsed.deinit();

    // --name resolves against the saved slot names, same rule as
    // `paramux open --name`. An explicit slot number wins.
    const slot = slot_arg orelse blk: {
        const want = name_arg.?;
        for (parsed.value.names, 1..) |slot_name, n| {
            const have = slot_name orelse continue;
            if (std.ascii.eqlIgnoreCase(have, want)) break :blk n;
        }
        try stderr.print("no layout slot named {s} (see paramux open --list)\n", .{want});
        return 1;
    };

    const tab = parsed.value.slots[slot - 1] orelse {
        try stderr.print("slot {d} is empty\n", .{slot});
        return 1;
    };

    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    std.json.Stringify.value(tab, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    }, &out.writer) catch return 1;

    if (out_arg) |file_path| {
        const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
            try stderr.print("could not create {s} (err={})\n", .{ file_path, err });
            return 1;
        };
        defer file.close();
        file.writeAll(out.written()) catch return 1;
        file.writeAll("\n") catch {};
        const name = parsed.value.names[slot - 1] orelse "unnamed";
        try stdout.print("Exported slot {d} ({s}) to {s}\n", .{ slot, name, file_path });
    } else {
        try stdout.print("{s}\n", .{out.written()});
    }
    return 0;
}

fn exportAll(
    a: std.mem.Allocator,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    dir_path: []const u8,
) !u8 {
    const path = layoutsPath(a) catch {
        try stderr.print("could not resolve layouts.json\n", .{});
        return 1;
    };
    const raw = std.fs.cwd().readFileAlloc(a, path, 16 * 1024 * 1024) catch {
        try stderr.print("no layouts.json yet (save a layout first)\n", .{});
        return 1;
    };
    const parsed = std.json.parseFromSlice(Slots, a, stripBom(raw), .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch {
        try stderr.print("layouts.json is unreadable\n", .{});
        return 1;
    };
    defer parsed.deinit();

    std.fs.cwd().makePath(dir_path) catch {};
    var written: usize = 0;
    for (parsed.value.slots, 0..) |slot_opt, i| {
        const tab = slot_opt orelse continue;
        const name = parsed.value.names[i] orelse "unnamed";
        var name_safe_buf: [40]u8 = undefined;
        var n: usize = 0;
        for (name) |c| {
            if (n >= name_safe_buf.len) break;
            const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
                (c >= '0' and c <= '9') or c == '-' or c == '_';
            name_safe_buf[n] = if (ok) c else '-';
            n += 1;
        }
        const file_path = try std.fmt.allocPrint(a, "{s}/slot{d}-{s}.layout.json", .{
            dir_path,
            i + 1,
            name_safe_buf[0..n],
        });
        var out: std.Io.Writer.Allocating = .init(a);
        defer out.deinit();
        std.json.Stringify.value(tab, .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        }, &out.writer) catch continue;
        const file = std.fs.cwd().createFile(file_path, .{}) catch continue;
        defer file.close();
        file.writeAll(out.written()) catch continue;
        written += 1;
        try stdout.print("Exported slot {d} ({s}) to {s}\n", .{ i + 1, name, file_path });
    }
    if (written == 0) {
        try stderr.print("no occupied slots to export\n", .{});
        return 1;
    }
    return 0;
}

/// Hand-edited or PowerShell-written files often carry a UTF-8
/// BOM; std.json refuses it, so strip before parsing.
fn stripBom(raw: []const u8) []const u8 {
    const bom = "\xEF\xBB\xBF";
    return if (std.mem.startsWith(u8, raw, bom)) raw[bom.len..] else raw;
}
