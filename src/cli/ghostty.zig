const std = @import("std");
const Allocator = std.mem.Allocator;
const help_strings = @import("help_strings");
const actionpkg = @import("action.zig");

const list_fonts = @import("list_fonts.zig");
const help = @import("help.zig");
const version = @import("version.zig");
const list_keybinds = @import("list_keybinds.zig");
const list_themes = @import("list_themes.zig");
const list_colors = @import("list_colors.zig");
const list_actions = @import("list_actions.zig");
const vt_probe = @import("vt_probe.zig");
const ssh_cache = @import("ssh_cache.zig");
const edit_config = @import("edit_config.zig");
const show_config = @import("show_config.zig");
const explain_config = @import("explain_config.zig");
const validate_config = @import("validate_config.zig");
const crash_report = @import("crash_report.zig");
const show_face = @import("show_face.zig");
const boo = @import("boo.zig");
const new_window = @import("new_window.zig");
const list_windows = @import("list_windows.zig");
const perform_action = @import("perform_action.zig");
const notify = @import("notify.zig");
const read_pane = @import("read_pane.zig");
const send = @import("send.zig");
const send_key = @import("send_key.zig");
const import_theme = @import("import_theme.zig");
const install = @import("install.zig");
const uninstall = @import("uninstall.zig");
const update = @import("update.zig");
const doctor = @import("doctor.zig");
const run_cmd = @import("run.zig");
const status_cmd = @import("status.zig");
const attention_cmd = @import("attention.zig");
const open_cmd = @import("open.zig");
const export_config_cmd = @import("export_config.zig");
const export_layout_cmd = @import("export_layout.zig");
const import_layout_cmd = @import("import_layout.zig");
const record_cmd = @import("record.zig");
const serve_cmd = @import("serve.zig");

pub const Action = @import("ghostty_action.zig").Action;

pub fn requiresTerminalUi(self: Action) bool {
    return self == .boo;
}

/// Run the action. This returns the exit code to exit with.
pub fn run(self: Action, alloc: Allocator) !u8 {
    return runMain(self, alloc) catch |err| switch (err) {
        // If help is requested, then we use some comptime trickery
        // to find this action in the help strings and output that.
        Action.help_error => printActionHelp(self),
        else => err,
    };
}

fn printActionHelp(self: Action) !u8 {
    inline for (@typeInfo(Action).@"enum".fields) |field| {
        // All action help text is emitted through this shared path.
        if (self == @field(Action, field.name)) {
            var buffer: [1024]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&buffer);
            const stdout = &stdout_writer.interface;
            const text = @field(help_strings.Action, field.name) ++ "\n";
            stdout.writeAll(text) catch return error.ActionHelpOutputUnavailable;
            stdout.flush() catch return error.ActionHelpOutputUnavailable;
            return 0;
        }
    }

    unreachable;
}

fn runMain(self: Action, alloc: Allocator) !u8 {
    return switch (self) {
        .version => try version.run(alloc),
        .help => try help.run(alloc),
        .@"list-fonts" => try list_fonts.run(alloc),
        .@"list-keybinds" => try list_keybinds.run(alloc),
        .@"list-themes" => try list_themes.run(alloc),
        .@"list-colors" => try list_colors.run(alloc),
        .@"list-actions" => try list_actions.run(alloc),
        .@"vt-probe" => try vt_probe.run(alloc),
        .@"ssh-cache" => try ssh_cache.run(alloc),
        .@"edit-config" => try edit_config.run(alloc),
        .@"show-config" => try show_config.run(alloc),
        .@"explain-config" => try explain_config.run(alloc),
        .@"validate-config" => try validate_config.run(alloc),
        .@"crash-report" => try crash_report.run(alloc),
        .@"show-face" => try show_face.run(alloc),
        .boo => try boo.run(alloc),
        .@"new-window" => try new_window.run(alloc),
        .@"list-windows" => try list_windows.run(alloc),
        .@"perform-action" => try perform_action.run(alloc),
        .notify => try notify.run(alloc),
        .@"read-pane" => try read_pane.run(alloc),
        .send => try send.run(alloc),
        .@"send-key" => try send_key.run(alloc),
        .@"import-theme" => try import_theme.run(alloc),
        .install => try install.run(alloc),
        .uninstall => try uninstall.run(alloc),
        .update => try update.run(alloc),
        .doctor => try doctor.run(alloc),
        .run => try run_cmd.run(alloc),
        .status => try status_cmd.run(alloc),
        .attention => try attention_cmd.run(alloc),
        .open => try open_cmd.run(alloc),
        .@"export-config" => try export_config_cmd.run(alloc),
        .@"export-layout" => try export_layout_cmd.run(alloc),
        .@"import-layout" => try import_layout_cmd.run(alloc),
        .record => try record_cmd.run(alloc),
        .serve => try serve_cmd.run(alloc),
    };
}

/// Returns the options of action. Supports generating shell completions
/// without duplicating the mapping from Action to relevant Option
/// @import(..) declaration.
pub fn options(comptime self: Action) type {
    comptime {
        return switch (self) {
            .version => version.Options,
            .help => help.Options,
            .@"list-fonts" => list_fonts.Options,
            .@"list-keybinds" => list_keybinds.Options,
            .@"list-themes" => list_themes.Options,
            .@"list-colors" => list_colors.Options,
            .@"list-actions" => list_actions.Options,
            .@"vt-probe" => vt_probe.options,
            .@"ssh-cache" => ssh_cache.Options,
            .@"edit-config" => edit_config.Options,
            .@"show-config" => show_config.Options,
            .@"explain-config" => explain_config.Options,
            .@"validate-config" => validate_config.Options,
            .@"crash-report" => crash_report.Options,
            .@"show-face" => show_face.Options,
            .boo => boo.Options,
            .@"new-window" => new_window.Options,
            .@"list-windows" => list_windows.Options,
            .@"perform-action" => perform_action.Options,
            .notify => notify.Options,
            .@"read-pane" => read_pane.Options,
            .send => send.Options,
            .@"send-key" => send_key.Options,
            .@"import-theme" => import_theme.Options,
            .install => install.Options,
            .uninstall => uninstall.Options,
            .update => update.Options,
            .doctor => doctor.Options,
            .run => run_cmd.Options,
            .status => status_cmd.Options,
            .attention => attention_cmd.Options,
            .open => open_cmd.Options,
            .@"export-config" => export_config_cmd.Options,
            .@"export-layout" => export_layout_cmd.Options,
            .@"import-layout" => import_layout_cmd.Options,
            .record => record_cmd.Options,
            .serve => serve_cmd.Options,
        };
    }
}

test "parse action none" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var iter = try std.process.ArgIteratorGeneral(.{}).init(
        alloc,
        "--a=42 --b --b-f=false",
    );
    defer iter.deinit();
    const action = try actionpkg.detectIter(Action, &iter);
    try testing.expect(action == null);
}

test "parse action version" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--a=42 --b --b-f=false --version",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--c=84 --d --version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }
}

test "control-action-dispatch recognizes dedicated send operations" {
    const testing = std.testing;

    inline for (.{
        .{ "+send hello", "send" },
        .{ "+send-key enter", "send-key" },
    }) |case| {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            testing.allocator,
            case[0],
        );
        defer iter.deinit();

        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action != null);
        try testing.expectEqualStrings(case[1], @tagName(action.?));
    }
}

test {
    _ = @import("send.zig");
    _ = @import("send_key.zig");
}

test "parse action plus" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--a=42 --b --b-f=false +version",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "+version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--c=84 --d +version --a=42 --b --b-f=false",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action.? == .version);
    }
}

test "parse action plus ignores -e" {
    const testing = std.testing;
    const alloc = testing.allocator;

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "--a=42 -e +version",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action == null);
    }

    {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "+list-fonts --a=42 -e +version",
        );
        defer iter.deinit();
        try testing.expectError(
            actionpkg.DetectError.MultipleActions,
            actionpkg.detectIter(Action, &iter),
        );
    }
}

test "terminal UI actions are classified separately" {
    const testing = std.testing;

    try testing.expect(requiresTerminalUi(.boo));

    try testing.expect(!requiresTerminalUi(.@"list-keybinds"));
    try testing.expect(!requiresTerminalUi(.@"list-themes"));
    try testing.expect(!requiresTerminalUi(.@"list-colors"));
    try testing.expect(!requiresTerminalUi(.help));
    try testing.expect(!requiresTerminalUi(.version));
    try testing.expect(!requiresTerminalUi(.@"show-config"));
    try testing.expect(!requiresTerminalUi(.@"crash-report"));
}

test "vt-probe action is registered" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const probe = std.meta.stringToEnum(Action, "vt-probe");
    try testing.expect(probe != null);
    try testing.expect(@hasDecl(help_strings.Action, "vt-probe"));

    if (probe) |expected| {
        var iter = try std.process.ArgIteratorGeneral(.{}).init(
            alloc,
            "+vt-probe",
        );
        defer iter.deinit();
        const action = try actionpkg.detectIter(Action, &iter);
        try testing.expect(action != null);
        try testing.expectEqual(expected, action.?);
    }
}
