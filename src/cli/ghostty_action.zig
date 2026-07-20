const std = @import("std");
const actionpkg = @import("action.zig");
const SpecialCase = actionpkg.SpecialCase;

/// Special commands that can be invoked via CLI flags. These are all
/// invoked by using `+<action>` as a CLI flag. The only exception is
/// "version" which can be invoked additionally with `--version`.
pub const Action = enum {
    /// Output the version and exit
    version,

    /// Output help information for the CLI or configuration
    help,

    /// List available fonts
    @"list-fonts",

    /// List available keybinds
    @"list-keybinds",

    /// List available themes
    @"list-themes",

    /// List named RGB colors
    @"list-colors",

    /// List keybind actions
    @"list-actions",

    /// Print a deterministic VT capability summary for diagnostics
    @"vt-probe",

    /// Manage SSH terminfo cache for automatic remote host setup
    @"ssh-cache",

    /// Edit the config file in the configured terminal editor.
    @"edit-config",

    /// Dump the config to stdout
    @"show-config",

    /// Explain a single config option
    @"explain-config",

    // Validate passed config file
    @"validate-config",

    // Show which font face Ghostty loads a codepoint from.
    @"show-face",

    // List local crash reports.
    @"crash-report",

    // Boo!
    boo,

    // Use IPC to tell the running Ghostty to open a new window.
    @"new-window",

    // List read-only automation state for the running paramux instance.
    @"list-windows",

    // Forward a safe keybinding action to the running paramux instance.
    @"perform-action",

    // Emit a desktop-notification escape sequence to flag the current pane
    // for attention (used by AI-agent hooks).
    notify,

    // Read a pane's current viewport text from the running instance.
    @"read-pane",

    // Send exact UTF-8 input to a pane in the running instance.
    send,

    // Send one named key to a pane in the running instance.
    @"send-key",

    // Convert a Windows Terminal color scheme into a paramux theme.
    @"import-theme",

    // Wire this folder into the user environment (PATH, PARAMUX_HOME,
    // Explorer context menu, agent hooks).
    install,

    // Reverse +install for this folder; --purge also deletes the
    // per-user data directory.
    uninstall,

    // Update this portable install in place from the newest GitHub
    // release (checksum-verified).
    update,

    // Diagnose the agent-hook pipeline: env, packaged hook files,
    // per-tool wiring, and (with --fire) a live attention signal test.
    doctor,

    // Spawn a pane in the running instance, type a command into it,
    // and print the new pane's surface id.
    run,

    // Print every workspace and pane with attention state and token
    // totals as a table.
    status,

    // Open a directory as a new workspace in the running instance.
    open,

    pub fn detectSpecialCase(arg: []const u8) ?SpecialCase(Action) {
        // If we see a "-e" and we haven't seen a command yet, then
        // we are done looking for commands. This special case enables
        // `ghostty -e ghostty +command`. If we've seen a command we
        // still want to keep looking because
        // `ghostty +command -e +command` is invalid.
        if (std.mem.eql(u8, arg, "-e")) return .abort_if_no_action;

        // Special case, --version always outputs the version no
        // matter what, no matter what other args exist.
        if (std.mem.eql(u8, arg, "--version")) {
            return .{ .action = .version };
        }

        // --help matches "help" but if a subcommand is specified
        // then we match the subcommand.
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return .{ .fallback = .help };
        }

        return null;
    }

    /// This should be returned by actions that want to print the help text.
    pub const help_error = actionpkg.help_error;

    /// Returns the filename associated with an action. This is a relative
    /// path from the root src/ directory.
    pub fn file(comptime self: Action) []const u8 {
        comptime {
            const filename = filename: {
                const tag = @tagName(self);
                var filename: [tag.len]u8 = undefined;
                _ = std.mem.replace(u8, tag, "-", "_", &filename);
                break :filename &filename;
            };

            return "cli/" ++ filename ++ ".zig";
        }
    }
};
