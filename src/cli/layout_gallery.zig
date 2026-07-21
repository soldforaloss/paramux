//! Bundled layout-template gallery. The canonical copies live in
//! docs/paramux/layouts/ (kept byte-identical by the drift test
//! below); embedding them here lets `paramux import-layout <name>`
//! work from an installed package with no docs directory around.
const std = @import("std");

pub const Entry = struct {
    name: []const u8,
    json: []const u8,
};

pub const entries = [_]Entry{
    .{ .name = "agents-with-env", .json =
        \\{
        \\  "note": "workspace env applies to every pane; a pane's own env wins",
        \\  "env": ["FLEET_NAME=demo", "NO_COLOR=1"],
        \\  "selected_leaf": 0,
        \\  "layout": {
        \\    "root": 2,
        \\    "nodes": [
        \\      { "pane": { "command": "claude", "env": ["AGENT_ROLE=implementer"] } },
        \\      { "pane": { "command": "claude", "env": ["AGENT_ROLE=reviewer"] } },
        \\      { "split": { "axis": "vertical", "ratio": 0.5, "first": 0, "second": 1 } }
        \\    ]
        \\  }
        \\}
        ++ "\n" },
    .{ .name = "grid-2x2", .json =
        \\{
        \\  "selected_leaf": 0,
        \\  "layout": {
        \\    "root": 6,
        \\    "nodes": [
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "split": {
        \\          "axis": "vertical",
        \\          "ratio": 0.5,
        \\          "first": 0,
        \\          "second": 1
        \\        }
        \\      },
        \\      {
        \\        "split": {
        \\          "axis": "vertical",
        \\          "ratio": 0.5,
        \\          "first": 2,
        \\          "second": 3
        \\        }
        \\      },
        \\      {
        \\        "split": {
        \\          "axis": "horizontal",
        \\          "ratio": 0.5,
        \\          "first": 4,
        \\          "second": 5
        \\        }
        \\      }
        \\    ]
        \\  }
        \\}
        ++ "\n" },
    .{ .name = "main-plus-side", .json =
        \\{
        \\  "selected_leaf": 0,
        \\  "layout": {
        \\    "root": 4,
        \\    "nodes": [
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "split": {
        \\          "axis": "vertical",
        \\          "ratio": 0.5,
        \\          "first": 1,
        \\          "second": 2
        \\        }
        \\      },
        \\      {
        \\        "split": {
        \\          "axis": "horizontal",
        \\          "ratio": 0.66,
        \\          "first": 0,
        \\          "second": 3
        \\        }
        \\      }
        \\    ]
        \\  }
        \\}
        ++ "\n" },
    .{ .name = "two-column", .json =
        \\{
        \\  "selected_leaf": 0,
        \\  "layout": {
        \\    "root": 2,
        \\    "nodes": [
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "pane": {}
        \\      },
        \\      {
        \\        "split": {
        \\          "axis": "horizontal",
        \\          "ratio": 0.5,
        \\          "first": 0,
        \\          "second": 1
        \\        }
        \\      }
        \\    ]
        \\  }
        \\}
        ++ "\n" },
};

pub fn get(name: []const u8) ?[]const u8 {
    for (entries) |e| {
        if (std.mem.eql(u8, e.name, name)) return e.json;
    }
    return null;
}

test "win32 layout gallery matches the docs templates" {
    const alloc = std.testing.allocator;
    for (entries) |e| {
        var path_buf: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "docs/paramux/layouts/{s}.layout.json", .{e.name});
        const disk = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 20);
        defer alloc.free(disk);
        const normalized = try std.mem.replaceOwned(u8, alloc, disk, "\r", "");
        defer alloc.free(normalized);
        try std.testing.expectEqualStrings(normalized, e.json);
    }
}
