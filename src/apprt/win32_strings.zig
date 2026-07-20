//! User-visible chrome strings — step 1 of docs/paramux/i18n-notes.md.
//!
//! One struct of UTF-16 fields, default-initialized with the English
//! comptime literals. Call sites read `strings.<name>` instead of
//! embedding chrome text inline; a locale later becomes one alternate
//! initializer (or a parsed file), with no call-site churn.
//!
//! What belongs here: text a person reads (labels, tooltips, cues).
//! What must NOT move here: window-class names, control-class names
//! ("BUTTON"), attention-state wire tags, or clipboard-format names —
//! those are protocol, not language. Accelerator chords inside tooltip
//! text ("Ctrl+Shift+T") mirror keybinds and must not localize when a
//! locale lands.

const std = @import("std");

fn w(comptime utf8: []const u8) [:0]const u16 {
    @setEvalBranchQuota(20_000);
    return std.unicode.utf8ToUtf16LeStringLiteral(utf8);
}

pub const Strings = struct {
    // Prompt overlay buttons.
    prompt_ok_label: [:0]const u16 = w("OK"),
    prompt_cancel_label: [:0]const u16 = w("Cancel"),

    // Scrollback search bar.
    search_prev_label: [:0]const u16 = w("Prev match"),
    search_next_label: [:0]const u16 = w("Next match"),
    search_regex_label: [:0]const u16 = w("Regex"),
    search_case_label: [:0]const u16 = w("Case sensitive"),
    search_word_label: [:0]const u16 = w("Whole word"),
    search_close_label: [:0]const u16 = w("Close search"),
    search_edit_cue: [:0]const u16 = w("Find in scrollback"),
    tooltip_search_prev: [:0]const u16 = w("Previous match (Shift+Enter)"),
    tooltip_search_next: [:0]const u16 = w("Next match (Enter)"),
    tooltip_search_regex: [:0]const u16 = w("Regular expression"),
    tooltip_search_case: [:0]const u16 = w("Match case"),
    tooltip_search_word: [:0]const u16 = w("Whole word"),
    tooltip_search_close: [:0]const u16 = w("Close search (Esc)"),

    // Command palette + toolbar chrome.
    host_overlay_command_palette_label: [:0]const u16 = w("Command:"),
    tooltip_new_tab: [:0]const u16 = w("New workspace (Ctrl+Shift+T)\nRight-click: new window \u{00B7} Middle-click: split"),
    tooltip_split_right: [:0]const u16 = w("Split right (Ctrl+Shift+O)"),
    tooltip_split_down: [:0]const u16 = w("Split down (Ctrl+Shift+E)"),
    tooltip_settings: [:0]const u16 = w("Settings (Ctrl+,)"),
    tooltip_help: [:0]const u16 = w("Help"),
    tooltip_more_actions: [:0]const u16 = w("More actions"),
};

/// The active string table. English defaults; a locale swaps this out.
pub const strings: Strings = .{};

test "string table defaults are non-empty UTF-16" {
    inline for (@typeInfo(Strings).@"struct".fields) |field| {
        const value = @field(strings, field.name);
        try std.testing.expect(value.len > 0);
        try std.testing.expect(value[value.len] == 0);
    }
}
