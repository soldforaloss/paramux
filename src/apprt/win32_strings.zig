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
    // The quota is shared across every comptime conversion in this
    // struct; grow it as the table grows.
    @setEvalBranchQuota(60_000);
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

    // Accessibility strings (spoken by screen readers).
    uia_localized_control_type: [:0]const u16 = w("terminal window"),

    // Settings rail/section labels (UTF-16 for controls, UTF-8 for
    // the header paint path).
    section_appearance: [:0]const u16 = w("Appearance"),
    section_theme: [:0]const u16 = w("Theme"),
    section_terminal: [:0]const u16 = w("Terminal"),
    section_shell: [:0]const u16 = w("Shell"),
    section_keybindings: [:0]const u16 = w("Keybindings"),
    section_windows: [:0]const u16 = w("Windows"),
    section_agents: [:0]const u16 = w("Agents"),
    section_advanced: [:0]const u16 = w("Advanced"),
    section_appearance_utf8: []const u8 = "Appearance",
    section_theme_utf8: []const u8 = "Theme",
    section_terminal_utf8: []const u8 = "Terminal",
    section_shell_utf8: []const u8 = "Shell",
    section_keybindings_utf8: []const u8 = "Keybindings",
    section_windows_utf8: []const u8 = "Windows",
    section_agents_utf8: []const u8 = "Agents",
    section_advanced_utf8: []const u8 = "Advanced",

    // Context-menu popup titles without accelerator chords.
    menu_workspace_color: [:0]const u16 = w("Workspace Color"),
    menu_save_layout_to: [:0]const u16 = w("Save Layout To"),
    menu_apply_layout_from: [:0]const u16 = w("Apply Layout From"),
    menu_workspaces: [:0]const u16 = w("Workspaces..."),

    // Watch-window fallback title when the pane has none (UTF-8).
    watch_fallback_title: []const u8 = "pane",

    // Overlay title labels (UTF-8 - duped into paint paths).
    overlay_surface_title: []const u8 = "Window title",
    overlay_find_panes: []const u8 = "Find in all panes",
    overlay_worktree_branch: []const u8 = "New workspace from branch",
    overlay_workspace_note: []const u8 = "Workspace note",
    overlay_prompt: []const u8 = "Rename layout slot",
    overlay_tab_title: []const u8 = "Tab title",
    overlay_profile: []const u8 = "Profile",
    overlay_confirm: []const u8 = "Confirm",

    // Pane context menu, first block (UTF-16). The \t chord suffixes
    // ride inside the strings and never translate.
    menu_copy: [:0]const u16 = w("Copy\tCtrl+Shift+C"),
    menu_paste: [:0]const u16 = w("Paste\tCtrl+Shift+V"),
    menu_select_all: [:0]const u16 = w("Select All"),
    menu_find: [:0]const u16 = w("Find...\tCtrl+Shift+F"),
    menu_find_panes: [:0]const u16 = w("Find in All Panes...\tCtrl+Alt+F"),
    menu_scrollback_editor: [:0]const u16 = w("Open Scrollback in Editor"),
    menu_watch_pane: [:0]const u16 = w("Pop Out Watch Window"),
    menu_restart_pane: [:0]const u16 = w("Restart Pane (new shell here)"),
    menu_worktree_seed: [:0]const u16 = w("Type Worktree Command"),

    // Pane context menu, second block: navigation + workspace verbs.
    menu_split_ratio: [:0]const u16 = w("Split Ratio"),
    menu_prompt_prev: [:0]const u16 = w("Previous Command Output"),
    menu_prompt_next: [:0]const u16 = w("Next Command Output"),
    menu_scroll_top: [:0]const u16 = w("Scroll to Top"),
    menu_scroll_bottom: [:0]const u16 = w("Scroll to Bottom"),
    menu_copy_fleet: [:0]const u16 = w("Copy Fleet Status"),
    menu_broadcast: [:0]const u16 = w("Broadcast Input to This Workspace"),
    menu_command_palette: [:0]const u16 = w("Command Palette\tCtrl+Shift+P"),
    menu_new_workspace: [:0]const u16 = w("New Workspace\tCtrl+Shift+T"),
    menu_new_workspace_here: [:0]const u16 = w("New Workspace Here (same folder)"),
    menu_move_ws_up: [:0]const u16 = w("Move Workspace Up"),
    menu_move_ws_down: [:0]const u16 = w("Move Workspace Down"),
    menu_ws_note: [:0]const u16 = w("Workspace Note..."),

    // Pane context menu, third block: splits + window/workspace ops.
    menu_split_right: [:0]const u16 = w("Split Right\tCtrl+Shift+O"),
    menu_split_down: [:0]const u16 = w("Split Down\tCtrl+Shift+E"),
    menu_split_left: [:0]const u16 = w("Split Left"),
    menu_split_up: [:0]const u16 = w("Split Up"),
    menu_equalize: [:0]const u16 = w("Equalize Splits"),
    menu_merge_panes: [:0]const u16 = w("Merge Panes (Close Others)"),
    menu_recent_activity: [:0]const u16 = w("Recent Activity"),
    menu_new_window: [:0]const u16 = w("New Window\tCtrl+Shift+N"),
    menu_settings: [:0]const u16 = w("Settings...\tCtrl+,"),
    menu_rename_pane: [:0]const u16 = w("Rename Pane"),
    menu_rename_workspace: [:0]const u16 = w("Rename Workspace"),
    menu_move_ws_left: [:0]const u16 = w("Move Workspace Left"),
    menu_move_ws_right: [:0]const u16 = w("Move Workspace Right"),
    menu_close_workspace: [:0]const u16 = w("Close Workspace"),

    // Pane context menu, final block: workspace close, empty-state
    // rows, quick terminal, inspector, and the help menu.
    menu_close_other_ws: [:0]const u16 = w("Close Other Workspaces"),
    menu_no_matches: [:0]const u16 = w("No matches in any pane"),
    menu_no_attention: [:0]const u16 = w("No agents need attention"),
    menu_quick_terminal: [:0]const u16 = w("Quick Terminal\tCtrl+Alt+Q"),
    menu_toggle_inspector: [:0]const u16 = w("Toggle Inspector"),
    menu_new_terminal_auto: [:0]const u16 = w("New Terminal in This Workspace\tCtrl+Shift+D"),
    menu_help_getting_started: [:0]const u16 = w("Getting Started"),
    menu_help_shortcuts: [:0]const u16 = w("Keyboard Shortcuts"),
    menu_help_docs: [:0]const u16 = w("Documentation (GitHub)"),
    menu_open_data_dir: [:0]const u16 = w("Open Data Folder (config, logs, crashes)"),
    menu_help_about: [:0]const u16 = w("About Paramux"),

    // Toggle-state menu items and submenu empty states (the earlier
    // sweeps matched only the main-menu handle). Ratio numbers stay
    // untranslated by design.
    menu_broadcast_include: [:0]const u16 = w("Include This Pane in Broadcast"),
    menu_broadcast_exclude: [:0]const u16 = w("Exclude This Pane from Broadcast"),
    menu_pin_pane: [:0]const u16 = w("Pin Pane to Top"),
    menu_unpin_pane: [:0]const u16 = w("Unpin Pane"),
    menu_mute_pane: [:0]const u16 = w("Mute Notifications 30 min"),
    menu_unmute_pane: [:0]const u16 = w("Unmute Notifications"),
    menu_accent_default: [:0]const u16 = w("Default"),
    menu_no_recent_activity: [:0]const u16 = w("(no recent activity)"),

    // Dialog/window titles and the update-banner buttons.
    title_health: [:0]const u16 = w("Paramux Health"),
    title_watch: [:0]const u16 = w("Paramux Watch"),
    button_install: [:0]const u16 = w("Install"),
    button_open_release: [:0]const u16 = w("Open Release"),

    // Hint-strip texts (UTF-16 via w) plus prefix/suffix pieces for
    // the two runtime-formatted hints (bufPrint formats are comptime,
    // so the dynamic parts compose around table strings instead).
    // Chords stay untranslated.
    hint_confirm: [:0]const u16 = w("Enter accept \u{00B7} Esc cancel"),
    hint_drop: [:0]const u16 = w("Drop: edges dock \u{00B7} center swaps"),
    hint_resize: [:0]const u16 = w("Drag to resize"),
    hint_tip1: [:0]const u16 = w("Tip 1/3: the (+) button asks - new workspace, or a pane in this one"),
    hint_tip2: [:0]const u16 = w("Tip 2/3: Ctrl+Alt+I lists every pane that needs you"),
    hint_tip3: [:0]const u16 = w("Tip 3/3: right-click a pane for layouts, colors, and broadcast"),
    hint_broadcast: [:0]const u16 = w("BROADCAST \u{00B7} typing goes to every pane in this workspace"),
    hint_zoomed: [:0]const u16 = w("Zoomed \u{00B7} Ctrl+Shift+Enter restores all panes"),
    hint_default: [:0]const u16 = w("Ctrl+Alt+I inbox \u{00B7} Ctrl+Alt+U attention \u{00B7} Ctrl+Shift+P palette"),
    hint_wave_suffix: []const u8 = " panes need you  \u{00B7}  palette: Clear All Attention",
    hint_git_prefix: []const u8 = "\u{2387} ",
    hint_git_suffix: []const u8 = "  \u{00B7}  Ctrl+Alt+I inbox \u{00B7} Ctrl+Alt+U attention",

    // Banner texts (UTF-8 - setBanner takes []const u8). Chord names
    // inside the text stay untranslated, same rule as tooltips.
    banner_nothing_to_undo: []const u8 = "Nothing to undo.",
    banner_nothing_to_redo: []const u8 = "Nothing to redo.",
    banner_session_saved: []const u8 = "Session saved.",
    banner_all_quiet: []const u8 = "All quiet: no panes need attention.",
    banner_pane_muted: []const u8 = "Pane notifications muted for 30 minutes.",
    banner_pane_unmuted: []const u8 = "Notifications unmuted for this pane.",
    banner_workspace_closed: []const u8 = "Workspace closed. Ctrl+Shift+Z undoes.",
    banner_pane_moved: []const u8 = "Pane moved to this workspace.",
    banner_quick_pins_cleared: []const u8 = "Cleared quick slot pins.",
    banner_qt_frame_reset: []const u8 = "Quick terminal frame reset.",
    banner_install_tip: []const u8 = "Tip: run `paramux install` (or install-paramux.cmd) to add this folder to PATH.",
    banner_tab_closed_undo: []const u8 = "Tab closed. Use undo to restore it.",
    banner_no_profiles: []const u8 = "No supported Windows profiles detected.",
    banner_unknown_profile: []const u8 = "Unknown profile. Try a number or a profile name like pwsh, ubuntu, git, or cmd.",
    banner_export_scrollback_failed: []const u8 = "Could not export scrollback.",
    banner_slot_name_unchanged: []const u8 = "Slot name unchanged.",
    banner_layouts_write_failed: []const u8 = "Could not write layouts.json.",
    banner_layout_capture_failed: []const u8 = "Could not capture this workspace's layout.",
    banner_no_saved_layouts: []const u8 = "No saved layouts yet. Save one first.",
    banner_layouts_unreadable: []const u8 = "layouts.json is unreadable.",
    banner_slot_empty: []const u8 = "That layout slot is empty. Save one first.",
    banner_layout_apply_failed: []const u8 = "Could not apply that layout.",
    banner_branch_unusable: []const u8 = "Branch name has no usable characters.",
    banner_worktree_running: []const u8 = "Worktree command running. When it finishes: right-click > New Workspace Here from the new folder.",
    banner_clipboard_failed: []const u8 = "Could not write the clipboard.",
    banner_fleet_copied: []const u8 = "Fleet status copied as markdown.",
    banner_no_split_resize: []const u8 = "Focused pane has no split to resize.",
    banner_last_pane_move: []const u8 = "A workspace keeps its last pane; move the workspace instead.",
    banner_unknown_action: []const u8 = "Unknown Paramux action. Example: new_tab or toggle_fullscreen",
    banner_numeric_tab: []const u8 = "Enter a numeric tab index.",
    banner_broadcast_pane_excluded: []const u8 = "Pane excluded from broadcast input.",
    banner_broadcast_pane_included: []const u8 = "Pane included in broadcast input.",
    banner_broadcast_on: []const u8 = "Broadcast ON: typing reaches every pane in this workspace.",
    banner_broadcast_off: []const u8 = "Broadcast off.",
    banner_topmost_on: []const u8 = "Window pinned on top. Ctrl+Alt+T releases it.",
    banner_topmost_off: []const u8 = "Window no longer on top.",
};

/// The English table (the field defaults).
pub const english: Strings = .{};

/// de-DE proof-of-concept locale. Accelerator chords stay untranslated
/// (they mirror keybinds, not language).
pub const german: Strings = .{
    .prompt_ok_label = w("OK"),
    .prompt_cancel_label = w("Abbrechen"),
    .search_prev_label = w("Vorheriger Treffer"),
    .search_next_label = w("N\u{00E4}chster Treffer"),
    .search_regex_label = w("Regex"),
    .search_case_label = w("Gro\u{00DF}-/Kleinschreibung"),
    .search_word_label = w("Ganzes Wort"),
    .search_close_label = w("Suche schlie\u{00DF}en"),
    .search_edit_cue = w("Im Verlauf suchen"),
    .tooltip_search_prev = w("Vorheriger Treffer (Shift+Enter)"),
    .tooltip_search_next = w("N\u{00E4}chster Treffer (Enter)"),
    .tooltip_search_regex = w("Regul\u{00E4}rer Ausdruck"),
    .tooltip_search_case = w("Gro\u{00DF}-/Kleinschreibung beachten"),
    .tooltip_search_word = w("Ganzes Wort"),
    .tooltip_search_close = w("Suche schlie\u{00DF}en (Esc)"),
    .host_overlay_command_palette_label = w("Befehl:"),
    .tooltip_new_tab = w("Neuer Arbeitsbereich (Ctrl+Shift+T)\nRechtsklick: neues Fenster \u{00B7} Mittelklick: teilen"),
    .tooltip_split_right = w("Rechts teilen (Ctrl+Shift+O)"),
    .tooltip_split_down = w("Unten teilen (Ctrl+Shift+E)"),
    .tooltip_settings = w("Einstellungen (Ctrl+,)"),
    .tooltip_help = w("Hilfe"),
    .tooltip_more_actions = w("Weitere Aktionen"),
    .uia_localized_control_type = w("Terminalfenster"),
    .section_appearance = w("Darstellung"),
    .section_theme = w("Design"),
    .section_terminal = w("Terminal"),
    .section_shell = w("Shell"),
    .section_keybindings = w("Tastenk\u{00FC}rzel"),
    .section_windows = w("Windows"),
    .section_agents = w("Agenten"),
    .section_advanced = w("Erweitert"),
    .section_appearance_utf8 = "Darstellung",
    .section_theme_utf8 = "Design",
    .section_terminal_utf8 = "Terminal",
    .section_shell_utf8 = "Shell",
    .section_keybindings_utf8 = "Tastenkürzel",
    .section_windows_utf8 = "Windows",
    .section_agents_utf8 = "Agenten",
    .section_advanced_utf8 = "Erweitert",
    .menu_workspace_color = w("Arbeitsbereich-Farbe"),
    .menu_save_layout_to = w("Layout speichern in"),
    .menu_apply_layout_from = w("Layout anwenden aus"),
    .menu_workspaces = w("Arbeitsbereiche..."),
    .watch_fallback_title = "Pane",
    .overlay_surface_title = "Fenstertitel",
    .overlay_find_panes = "In allen Panes suchen",
    .overlay_worktree_branch = "Neuer Arbeitsbereich aus Branch",
    .overlay_workspace_note = "Arbeitsbereich-Notiz",
    .overlay_prompt = "Layout-Slot umbenennen",
    .overlay_tab_title = "Arbeitsbereich-Titel",
    .overlay_profile = "Profil",
    .overlay_confirm = "Bestätigen",
    .menu_copy = w("Kopieren\tCtrl+Shift+C"),
    .menu_paste = w("Einf\u{00FC}gen\tCtrl+Shift+V"),
    .menu_select_all = w("Alles ausw\u{00E4}hlen"),
    .menu_find = w("Suchen...\tCtrl+Shift+F"),
    .menu_find_panes = w("In allen Panes suchen...\tCtrl+Alt+F"),
    .menu_scrollback_editor = w("Scrollback im Editor \u{00F6}ffnen"),
    .menu_watch_pane = w("Beobachtungsfenster abdocken"),
    .menu_restart_pane = w("Pane neu starten (neue Shell hier)"),
    .menu_worktree_seed = w("Worktree-Befehl eintippen"),
    .menu_split_ratio = w("Teilungsverh\u{00E4}ltnis"),
    .menu_prompt_prev = w("Vorherige Befehlsausgabe"),
    .menu_prompt_next = w("N\u{00E4}chste Befehlsausgabe"),
    .menu_scroll_top = w("Nach ganz oben"),
    .menu_scroll_bottom = w("Nach ganz unten"),
    .menu_copy_fleet = w("Flottenstatus kopieren"),
    .menu_broadcast = w("Eingabe an diesen Arbeitsbereich senden"),
    .menu_command_palette = w("Befehlspalette\tCtrl+Shift+P"),
    .menu_new_workspace = w("Neuer Arbeitsbereich\tCtrl+Shift+T"),
    .menu_new_workspace_here = w("Neuer Arbeitsbereich hier (gleicher Ordner)"),
    .menu_move_ws_up = w("Arbeitsbereich nach oben"),
    .menu_move_ws_down = w("Arbeitsbereich nach unten"),
    .menu_ws_note = w("Arbeitsbereich-Notiz..."),
    .menu_split_right = w("Rechts teilen\tCtrl+Shift+O"),
    .menu_split_down = w("Unten teilen\tCtrl+Shift+E"),
    .menu_split_left = w("Links teilen"),
    .menu_split_up = w("Oben teilen"),
    .menu_equalize = w("Teilungen angleichen"),
    .menu_merge_panes = w("Panes zusammenf\u{00FC}hren (andere schlie\u{00DF}en)"),
    .menu_recent_activity = w("Letzte Aktivit\u{00E4}t"),
    .menu_new_window = w("Neues Fenster\tCtrl+Shift+N"),
    .menu_settings = w("Einstellungen...\tCtrl+,"),
    .menu_rename_pane = w("Pane umbenennen"),
    .menu_rename_workspace = w("Arbeitsbereich umbenennen"),
    .menu_move_ws_left = w("Arbeitsbereich nach links"),
    .menu_move_ws_right = w("Arbeitsbereich nach rechts"),
    .menu_close_workspace = w("Arbeitsbereich schlie\u{00DF}en"),
    .menu_close_other_ws = w("Andere Arbeitsbereiche schlie\u{00DF}en"),
    .menu_no_matches = w("Keine Treffer in irgendeinem Pane"),
    .menu_no_attention = w("Keine Agenten brauchen Aufmerksamkeit"),
    .menu_quick_terminal = w("Quick Terminal\tCtrl+Alt+Q"),
    .menu_toggle_inspector = w("Inspector umschalten"),
    .menu_new_terminal_auto = w("Neues Terminal in diesem Arbeitsbereich\tCtrl+Shift+D"),
    .menu_help_getting_started = w("Erste Schritte"),
    .menu_help_shortcuts = w("Tastenk\u{00FC}rzel"),
    .menu_help_docs = w("Dokumentation (GitHub)"),
    .menu_open_data_dir = w("Datenordner \u{00F6}ffnen (Konfiguration, Logs, Abst\u{00FC}rze)"),
    .menu_help_about = w("\u{00DC}ber Paramux"),
    .menu_broadcast_include = w("Dieses Pane in Broadcast einbeziehen"),
    .menu_broadcast_exclude = w("Dieses Pane vom Broadcast ausnehmen"),
    .menu_pin_pane = w("Pane oben anpinnen"),
    .menu_unpin_pane = w("Pane l\u{00F6}sen"),
    .menu_mute_pane = w("Benachrichtigungen 30 Min. stumm"),
    .menu_unmute_pane = w("Stummschaltung aufheben"),
    .menu_accent_default = w("Standard"),
    .menu_no_recent_activity = w("(keine letzte Aktivit\u{00E4}t)"),
    .title_health = w("Paramux-Zustand"),
    .title_watch = w("Paramux-Beobachtung"),
    .button_install = w("Installieren"),
    .button_open_release = w("Release \u{00F6}ffnen"),
    .hint_confirm = w("Enter best\u{00E4}tigen \u{00B7} Esc abbrechen"),
    .hint_drop = w("Ablegen: Kanten docken an \u{00B7} Mitte tauscht"),
    .hint_resize = w("Ziehen zum Anpassen"),
    .hint_tip1 = w("Tipp 1/3: Die (+) Schaltfl\u{00E4}che fragt - neuer Arbeitsbereich oder ein Pane hier"),
    .hint_tip2 = w("Tipp 2/3: Ctrl+Alt+I listet jedes Pane, das dich braucht"),
    .hint_tip3 = w("Tipp 3/3: Rechtsklick auf ein Pane f\u{00FC}r Layouts, Farben und Broadcast"),
    .hint_broadcast = w("BROADCAST \u{00B7} Eingaben gehen an jedes Pane in diesem Arbeitsbereich"),
    .hint_zoomed = w("Zoom \u{00B7} Ctrl+Shift+Enter stellt alle Panes wieder her"),
    .hint_default = w("Ctrl+Alt+I Inbox \u{00B7} Ctrl+Alt+U Aufmerksamkeit \u{00B7} Ctrl+Shift+P Palette"),
    .hint_wave_suffix = " Panes brauchen dich  \u{00B7}  Palette: Clear All Attention",
    .hint_git_prefix = "\u{2387} ",
    .hint_git_suffix = "  \u{00B7}  Ctrl+Alt+I Inbox \u{00B7} Ctrl+Alt+U Aufmerksamkeit",
    .banner_nothing_to_undo = "Nichts r\u{00FC}ckg\u{00E4}ngig zu machen.",
    .banner_nothing_to_redo = "Nichts wiederherzustellen.",
    .banner_session_saved = "Sitzung gespeichert.",
    .banner_all_quiet = "Alles ruhig: kein Pane braucht Aufmerksamkeit.",
    .banner_pane_muted = "Pane-Benachrichtigungen f\u{00FC}r 30 Minuten stumm.",
    .banner_pane_unmuted = "Benachrichtigungen f\u{00FC}r dieses Pane wieder an.",
    .banner_workspace_closed = "Arbeitsbereich geschlossen. Ctrl+Shift+Z macht es r\u{00FC}ckg\u{00E4}ngig.",
    .banner_pane_moved = "Pane in diesen Arbeitsbereich verschoben.",
    .banner_quick_pins_cleared = "Schnellzugriffs-Pins geleert.",
    .banner_qt_frame_reset = "Quick-Terminal-Position zur\u{00FC}ckgesetzt.",
    .banner_install_tip = "Tipp: `paramux install` (oder install-paramux.cmd) f\u{00FC}gt diesen Ordner zu PATH hinzu.",
    .banner_tab_closed_undo = "Tab geschlossen. R\u{00FC}ckg\u{00E4}ngig stellt ihn wieder her.",
    .banner_no_profiles = "Keine unterst\u{00FC}tzten Windows-Profile gefunden.",
    .banner_unknown_profile = "Unbekanntes Profil. Nummer oder Name wie pwsh, ubuntu, git oder cmd.",
    .banner_export_scrollback_failed = "Scrollback konnte nicht exportiert werden.",
    .banner_slot_name_unchanged = "Slot-Name unver\u{00E4}ndert.",
    .banner_layouts_write_failed = "layouts.json konnte nicht geschrieben werden.",
    .banner_layout_capture_failed = "Layout dieses Arbeitsbereichs konnte nicht erfasst werden.",
    .banner_no_saved_layouts = "Noch keine gespeicherten Layouts. Erst eines speichern.",
    .banner_layouts_unreadable = "layouts.json ist nicht lesbar.",
    .banner_slot_empty = "Dieser Layout-Slot ist leer. Erst eines speichern.",
    .banner_layout_apply_failed = "Layout konnte nicht angewendet werden.",
    .banner_branch_unusable = "Branch-Name hat keine verwendbaren Zeichen.",
    .banner_worktree_running = "Worktree-Befehl l\u{00E4}uft. Danach: Rechtsklick > Neuer Arbeitsbereich hier im neuen Ordner.",
    .banner_clipboard_failed = "Zwischenablage konnte nicht beschrieben werden.",
    .banner_fleet_copied = "Flottenstatus als Markdown kopiert.",
    .banner_no_split_resize = "Fokussiertes Pane hat keine Teilung zum Anpassen.",
    .banner_last_pane_move = "Ein Arbeitsbereich beh\u{00E4}lt sein letztes Pane; stattdessen den Arbeitsbereich verschieben.",
    .banner_unknown_action = "Unbekannte Paramux-Aktion. Beispiel: new_tab oder toggle_fullscreen",
    .banner_numeric_tab = "Numerischen Tab-Index eingeben.",
    .banner_broadcast_pane_excluded = "Pane vom Broadcast ausgenommen.",
    .banner_broadcast_pane_included = "Pane in Broadcast einbezogen.",
    .banner_broadcast_on = "Broadcast AN: Eingaben erreichen jedes Pane in diesem Arbeitsbereich.",
    .banner_broadcast_off = "Broadcast aus.",
    .banner_topmost_on = "Fenster oben angepinnt. Ctrl+Alt+T l\u{00F6}st es.",
    .banner_topmost_off = "Fenster nicht mehr oben.",
};

/// The active string table. Selected ONCE at startup, before any
/// window chrome is created — call sites read fields at runtime, so a
/// mid-session swap would work but is deliberately not exposed.
pub var strings: Strings = english;

/// Select the chrome locale from the `ui-language` config value.
pub fn setLocale(tag: []const u8) void {
    strings = if (std.mem.eql(u8, tag, "de")) german else english;
}

test "string table defaults are non-empty" {
    inline for (@typeInfo(Strings).@"struct".fields) |field| {
        const value = @field(strings, field.name);
        try std.testing.expect(value.len > 0);
        if (@TypeOf(value) == [:0]const u16) {
            try std.testing.expect(value[value.len] == 0);
        }
    }
}

test "german table covers every field" {
    inline for (@typeInfo(Strings).@"struct".fields) |field| {
        try std.testing.expect(@field(german, field.name).len > 0);
    }
}

test "win32 setLocale swaps the active table and back" {
    defer strings = english;
    setLocale("de");
    try std.testing.expect(std.mem.eql(u16, strings.uia_localized_control_type, german.uia_localized_control_type));
    setLocale("en");
    try std.testing.expect(std.mem.eql(u16, strings.uia_localized_control_type, english.uia_localized_control_type));
    // Unknown tags fall back to English rather than erroring.
    setLocale("fr");
    try std.testing.expect(std.mem.eql(u16, strings.uia_localized_control_type, english.uia_localized_control_type));
}
