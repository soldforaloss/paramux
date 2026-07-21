//! Native Win32 settings window.
//!
//! Singleton top-level HWND owned by `App`. The `open_config` action
//! routes here; the Advanced section keeps the text-editor escape hatch
//! for config keys that do not have native controls. `App` invokes this
//! module via a thin handle so the module doesn't need to know `Host`,
//! `Surface`, or the other win32 apprt internals.
//!
//! Lifecycle:
//!   * `SettingsWindow.open(app)` — creates the HWND if absent,
//!     otherwise `SetForegroundWindow`s the existing one. Idempotent.
//!   * `SettingsWindow.close(self)` — called from WM_CLOSE; hides
//!     the HWND (kept around so reopen is cheap) and nulls `open`.
//!   * `SettingsWindow.destroy(self)` — called from App.terminate;
//!     `DestroyWindow` + free the struct.
//!
//! The editable draft is a shallow-cloned `Config` saved atomically
//! through `AppHandle.saveAndReload`. Per AGENTS.md:49, the clone MUST
//! NOT deinit an inherited `command` override.

const std = @import("std");
const win32_strings = @import("win32_strings.zig");
const windows = std.os.windows;
const Config = @import("../config/Config.zig");
const cli_help = @import("../cli/help.zig");
const win32_types = @import("win32_types.zig");
const win32_explorer_menu = @import("win32_explorer_menu.zig");
const themepkg = @import("../config/theme.zig");

/// Minimal set of Win32 aliases + externs we need here. Shared ABI structs
/// live in `win32_types.zig` so this module stays free of an `*App` type
/// dependency without duplicating layout-sensitive declarations.
const HWND = win32_types.HWND;
const HINSTANCE = win32_types.HINSTANCE;
const HBRUSH = win32_types.HBRUSH;
const HCURSOR = win32_types.HCURSOR;
const HDC = win32_types.HDC;
const HGDIOBJ = win32_types.HGDIOBJ;
const HMENU = win32_types.HMENU;
const LPCWSTR = win32_types.LPCWSTR;
const UINT = win32_types.UINT;
const LRESULT = win32_types.LRESULT;
const WPARAM = win32_types.WPARAM;
const LPARAM = win32_types.LPARAM;
const BOOL = win32_types.BOOL;
const LONG_PTR = win32_types.LONG_PTR;
const ATOM = win32_types.ATOM;
const COLORREF = win32_types.COLORREF;
const RECT = win32_types.RECT;

const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const WS_MAXIMIZEBOX: u32 = 0x00010000;
const WS_EX_APPWINDOW: u32 = 0x00040000;
const SW_HIDE: i32 = 0;
const SW_SHOWNORMAL: i32 = 1;
const SW_RESTORE: i32 = 9;
const GWLP_USERDATA: i32 = -21;
const CS_HREDRAW: u32 = 0x2;
const CS_VREDRAW: u32 = 0x1;
const IDC_ARROW: usize = 32512;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

const WM_CLOSE: UINT = 0x0010;
const WM_NCCREATE: UINT = 0x0081;
const WM_PAINT: UINT = 0x000F;
const WM_ERASEBKGND: UINT = 0x0014;
const WM_NCDESTROY: UINT = 0x0082;
const WM_COMMAND: UINT = 0x0111;
const WM_SIZE: UINT = 0x0005;
const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_TABSTOP: u32 = 0x00010000;
const BS_PUSHBUTTON: u32 = 0x0;
const BS_OWNERDRAW: u32 = 0xB;
const BTN_OPEN_EDITOR: usize = 101;
const BTN_SECTION_APPEARANCE: usize = 201;
const BTN_SECTION_TERMINAL: usize = 202;
const BTN_SECTION_SHELL: usize = 203;
const BTN_SECTION_KEYBINDINGS: usize = 204;
const BTN_SECTION_ADVANCED: usize = 205;
const BTN_SECTION_THEME: usize = 206;
const BTN_SECTION_WINDOWS: usize = 207;
const BTN_SECTION_AGENTS: usize = 208;
const BTN_SAVE: usize = 301;
const BTN_KEYBINDINGS_EDITOR: usize = 302;
const EDIT_SCROLLBACK: usize = 401;
const EDIT_FONT_SIZE: usize = 402;
const COMBO_CONFIRM_CLOSE: usize = 403;
const COMBO_COPY_ON_SELECT: usize = 404;
const COMBO_WINDOW_THEME: usize = 405;
const COMBO_SHELL_INTEG: usize = 406;
const CHK_TRIM_TRAIL: usize = 407;
const EDIT_BG_OPACITY: usize = 408;
const COMBO_CURSOR_STYLE: usize = 409;
const CHK_BG_BLUR: usize = 410;
const COMBO_PAD_BALANCE: usize = 411;
const EDIT_FONT_FAMILY: usize = 412;
const EDIT_THEME: usize = 413;
const EDIT_COMMAND: usize = 414;
const EDIT_PAD_X: usize = 415;
const EDIT_PAD_Y: usize = 416;
const CHK_DESKTOP_NOTIFICATIONS: usize = 417;
const CHK_APP_NOTIFY_CLIPBOARD: usize = 418;
const CHK_APP_NOTIFY_CONFIG: usize = 419;
const COMBO_AUTO_UPDATE: usize = 420;
const COMBO_AUTO_UPDATE_CHANNEL: usize = 421;
const COMBO_CLIPBOARD_READ: usize = 422;
const COMBO_CLIPBOARD_WRITE: usize = 423;
const COMBO_LINK_URL: usize = 424;
const COMBO_LINK_PREVIEWS: usize = 425;
const EDIT_THEME_SEARCH: usize = 426;
const EDIT_SETTINGS_SEARCH: usize = 435;
const LIST_THEMES: usize = 427;
const CHK_EXPLORER_MENU: usize = 428;
const EDIT_DIGEST_MIN: usize = 429;
const EDIT_ALERT_KEYWORDS: usize = 430;
const EDIT_TOKEN_BUDGET: usize = 431;
const EDIT_AUTO_RESTART: usize = 432;
const EDIT_WS_LAYOUT: usize = 433;
const CHK_FOCUS_FOLLOWS: usize = 434;
const ES_NUMBER: u32 = 0x2000;
const ES_AUTOHSCROLL: u32 = 0x80;
const EN_CHANGE: u16 = 0x0300;
const EN_KILLFOCUS: u16 = 0x0200;
const CBN_SELCHANGE: u16 = 0x0001;
const BN_CLICKED: u16 = 0x0000;
const WM_SETTEXT: UINT = 0x000C;
const WM_SETFONT: UINT = 0x0030;
const EM_LIMITTEXT: UINT = 0x00C5;
const BS_AUTOCHECKBOX: u32 = 0x3;
const BM_SETCHECK: UINT = 0x00F1;
const BM_GETCHECK: UINT = 0x00F0;
const BST_CHECKED: usize = 1;
const BST_UNCHECKED: usize = 0;
const CB_ADDSTRING: UINT = 0x0143;
const CB_SETCURSEL: UINT = 0x014E;
const CB_GETCURSEL: UINT = 0x0147;
const CB_RESETCONTENT: UINT = 0x014B;
const CBS_DROPDOWNLIST: u32 = 0x3;
const CBS_HASSTRINGS: u32 = 0x200;

// Listbox (theme picker) styles + messages.
const WS_VSCROLL: u32 = 0x00200000;
const WS_BORDER: u32 = 0x00800000;
const LBS_NOTIFY: u32 = 0x0001;
const LBS_OWNERDRAWFIXED: u32 = 0x0010;
const LBS_HASSTRINGS: u32 = 0x0040;
const LB_ADDSTRING: UINT = 0x0180;
const LB_RESETCONTENT: UINT = 0x0184;
const LB_SETCURSEL: UINT = 0x0186;
const LB_GETCURSEL: UINT = 0x0188;
const LB_GETCOUNT: UINT = 0x018B;
const LB_GETITEMDATA: UINT = 0x0199;
const LB_SETITEMDATA: UINT = 0x019A;
const LB_SETITEMHEIGHT: UINT = 0x01A0;
const LBN_SELCHANGE: u16 = 1;
const LBN_DBLCLK: u16 = 2;
const EM_SETCUEBANNER: UINT = 0x1501;
const WM_DRAWITEM: UINT = 0x002B;
const ODT_LISTBOX: u32 = 2;
const ODS_SELECTED: u32 = 0x0001;
const ODS_FOCUS: u32 = 0x0010;
const theme_list_item_height: i32 = 26;

/// Owner-draw payload for WM_DRAWITEM. Mirrors winuser.h DRAWITEMSTRUCT.
const DRAWITEMSTRUCT = extern struct {
    CtlType: u32,
    CtlID: u32,
    itemID: u32,
    itemAction: u32,
    itemState: u32,
    hwndItem: HWND,
    hDC: HDC,
    rcItem: RECT,
    itemData: usize,
};

/// Sections on the left rail. Section-specific controls (e.g. the
/// "Open in default editor" button in Advanced) are shown / hidden on
/// the active section; non-specific controls stay visible across
/// sections.
pub const Section = enum(u32) {
    appearance,
    theme,
    terminal,
    shell,
    keybindings,
    windows,
    agents,
    advanced,

    fn fromButtonId(id: usize) ?Section {
        return switch (id) {
            BTN_SECTION_APPEARANCE => .appearance,
            BTN_SECTION_THEME => .theme,
            BTN_SECTION_TERMINAL => .terminal,
            BTN_SECTION_SHELL => .shell,
            BTN_SECTION_KEYBINDINGS => .keybindings,
            BTN_SECTION_WINDOWS => .windows,
            BTN_SECTION_AGENTS => .agents,
            BTN_SECTION_ADVANCED => .advanced,
            else => null,
        };
    }

    fn label(self: Section) [*:0]const u16 {
        const table = &win32_strings.strings;
        return switch (self) {
            .appearance => table.section_appearance,
            .theme => table.section_theme,
            .terminal => table.section_terminal,
            .shell => table.section_shell,
            .keybindings => table.section_keybindings,
            .windows => table.section_windows,
            .agents => table.section_agents,
            .advanced => table.section_advanced,
        };
    }

    fn headerText(self: Section) []const u8 {
        const table = &win32_strings.strings;
        return switch (self) {
            .appearance => table.section_appearance_utf8,
            .theme => table.section_theme_utf8,
            .terminal => table.section_terminal_utf8,
            .shell => table.section_shell_utf8,
            .keybindings => table.section_keybindings_utf8,
            .windows => table.section_windows_utf8,
            .agents => table.section_agents_utf8,
            .advanced => table.section_advanced_utf8,
        };
    }

    fn placeholderText(self: Section) []const u8 {
        return switch (self) {
            .appearance => "Font family, size, theme, opacity, cursor, padding, and background blur.",
            .theme => "Click a theme to select it; Save (or double-click) applies it live.",
            .agents => "Attention digest, urgent keywords, token budgets, auto-restart, and workspace layout defaults for agent fleets.",
            .terminal => "Scrollback, close confirmation, clipboard policy, links, and notifications.",
            .shell => "Default shell command and shell integration detection mode.",
            .keybindings => "Open the config file for keybind edits; list defaults, actions, and docs from the CLI.",
            .windows => "Windows shell integration: the Explorer right-click menu entry.",
            .advanced => "Updater defaults and the raw config-file escape hatch.",
        };
    }
};

fn backgroundBlurFromCheckbox(
    current: Config.BackgroundBlur,
    checked: bool,
) Config.BackgroundBlur {
    if (!checked) return .false;

    return switch (current) {
        .radius => |radius| if (radius > 0) current else .true,
        .false, .true => .true,
    };
}

const PaddingAxis = enum { x, y };
const AppNotificationField = enum { clipboard, config };

fn keybindingsHelpText() []const u8 {
    return "Useful commands:\n" ++
        cli_help.keybinding_discovery_hint ++
        "\n" ++
        "Config syntax:\n" ++
        "  keybind = ctrl+shift+c=copy_to_clipboard\n" ++
        "  keybind = ctrl+a>n=new_window\n" ++
        "  keybind = chain=goto_split:left";
}

fn clipboardAccessFromComboIndex(idx: LRESULT) ?Config.ClipboardAccess {
    return switch (idx) {
        0 => .ask,
        1 => .allow,
        2 => .deny,
        else => null,
    };
}

fn comboIndexFromClipboardAccess(value: Config.ClipboardAccess) usize {
    return switch (value) {
        .ask => 0,
        .allow => 1,
        .deny => 2,
    };
}

fn linkUrlFromComboIndex(idx: LRESULT) ?bool {
    return switch (idx) {
        0 => true,
        1 => false,
        else => null,
    };
}

fn comboIndexFromLinkUrl(value: bool) usize {
    return if (value) 0 else 1;
}

fn linkPreviewsFromComboIndex(idx: LRESULT) ?Config.LinkPreviews {
    return switch (idx) {
        0 => .true,
        1 => .osc8,
        2 => .false,
        else => null,
    };
}

fn comboIndexFromLinkPreviews(value: Config.LinkPreviews) usize {
    return switch (value) {
        .true => 0,
        .osc8 => 1,
        .false => 2,
    };
}

extern "user32" fn RegisterClassExW(lpwcx: *const WNDCLASSEXW) callconv(.winapi) ATOM;
extern "user32" fn CreateWindowExW(
    dwExStyle: u32,
    lpClassName: LPCWSTR,
    lpWindowName: LPCWSTR,
    dwStyle: u32,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) ?HWND;
extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.winapi) BOOL;
extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: LPCWSTR) callconv(.winapi) HCURSOR;
extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: LONG_PTR) callconv(.winapi) LONG_PTR;
extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.winapi) LONG_PTR;
extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) HDC;
extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
extern "user32" fn IsWindow(hWnd: ?HWND) callconv(.winapi) BOOL;
extern "user32" fn IsIconic(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn InvalidateRect(hWnd: HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.winapi) BOOL;
extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*]u16, nMaxCount: i32) callconv(.winapi) i32;
extern "user32" fn SendMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "gdi32" fn FillRect(hdc: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.winapi) i32;
extern "gdi32" fn GetStockObject(i: i32) callconv(.winapi) HGDIOBJ;
extern "gdi32" fn SetDCBrushColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
extern "gdi32" fn SetBkColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.winapi) i32;
extern "gdi32" fn SelectObject(hdc: HDC, h: HGDIOBJ) callconv(.winapi) HGDIOBJ;
extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.winapi) BOOL;
extern "gdi32" fn CreateFontW(
    cHeight: i32,
    cWidth: i32,
    cEscapement: i32,
    cOrientation: i32,
    cWeight: i32,
    bItalic: u32,
    bUnderline: u32,
    bStrikeOut: u32,
    iCharSet: u32,
    iOutPrecision: u32,
    iClipPrecision: u32,
    iQuality: u32,
    iPitchAndFamily: u32,
    pszFaceName: LPCWSTR,
) callconv(.winapi) HGDIOBJ;
extern "uxtheme" fn SetWindowTheme(hwnd: HWND, pszSubAppName: ?LPCWSTR, pszSubIdList: ?LPCWSTR) callconv(.winapi) i32;
extern "user32" fn EnumChildWindows(
    hWndParent: HWND,
    lpEnumFunc: *const fn (hwnd: HWND, lParam: LPARAM) callconv(.winapi) BOOL,
    lParam: LPARAM,
) callconv(.winapi) BOOL;
extern "user32" fn GetClassNameW(hWnd: HWND, lpClassName: [*]u16, nMaxCount: i32) callconv(.winapi) i32;

const WM_CTLCOLOREDIT: UINT = 0x0133;
const WM_CTLCOLORLISTBOX: UINT = 0x0134;
const WM_CTLCOLORBTN: UINT = 0x0135;
const WM_CTLCOLORSTATIC: UINT = 0x0138;
const WM_GETMINMAXINFO: UINT = 0x0024;
const FW_NORMAL: i32 = 400;
const FW_SEMIBOLD: i32 = 600;
const CLEARTYPE_QUALITY: u32 = 5;
const ODT_BUTTON_CTL: u32 = 4;

const MINMAXINFO = extern struct {
    ptReserved: POINT,
    ptMaxSize: POINT,
    ptMaxPosition: POINT,
    ptMinTrackSize: POINT,
    ptMaxTrackSize: POINT,
};
const POINT = extern struct { x: i32, y: i32 };

fn makeUiFont(height_px: i32, weight: i32) HGDIOBJ {
    return CreateFontW(
        -height_px,
        0,
        0,
        0,
        weight,
        0,
        0,
        0,
        0, // ANSI_CHARSET default
        0,
        0,
        CLEARTYPE_QUALITY,
        0,
        std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI"),
    );
}
extern "user32" fn DrawTextW(hDC: HDC, lpchText: LPCWSTR, cchText: i32, lprc: *RECT, format: UINT) callconv(.winapi) i32;

const DC_BRUSH: i32 = 18;
const TRANSPARENT: i32 = 1;
const DT_CENTER: UINT = 0x1;
const DT_VCENTER: UINT = 0x4;
const DT_SINGLELINE: UINT = 0x20;
const DT_NOPREFIX: UINT = 0x800;

const PAINTSTRUCT = win32_types.PAINTSTRUCT;
const CREATESTRUCTW = win32_types.CREATESTRUCTW;
const WNDCLASSEXW = win32_types.WNDCLASSEXW;

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("paramux.win32.settings");
const edit_text_max_code_units: usize = 4096;
const edit_text_max_utf8: usize = edit_text_max_code_units * 3;

/// Error set returned from `AppHandle.saveAndReload`. The settings
/// window surfaces these inline so users can re-try without losing
/// edits.
pub const SaveError = error{
    PathResolveFailed,
    TempCreateFailed,
    SerializeFailed,
    ReplaceFailed,
    ReloadFailed,
    OutOfMemory,
    /// Write + reload both succeeded, but at least one GUI-edited
    /// field is masked by a later layer (included `config-file`,
    /// subsequent `--config-file`, `--config-default-files=false`
    /// with no remaining base). The persisted bytes on disk are
    /// correct; the effective runtime value doesn't match. UI
    /// should surface this as a distinct warning, NOT as a
    /// generic write failure.
    SavedButMasked,
};

/// The color set the settings window paints with, snapshotted from the
/// app's resolved chrome theme per query so theme swaps propagate.
pub const UiColors = struct {
    bg: COLORREF,
    rail_bg: COLORREF,
    text: COLORREF,
    text_muted: COLORREF,
    accent: COLORREF,
    field_bg: COLORREF,
    border: COLORREF,
    active_bg: COLORREF,
    is_dark: bool,
};

/// Minimal hook into the apprt `App` so the settings module can fetch
/// the chrome brush colors without pulling in the whole app type.
pub const AppHandle = struct {
    ctx: *anyopaque,
    /// Allocator used for `Config.shallowClone` on the pending draft.
    /// The clone's `_arena` is owned by this allocator; `Config.deinit`
    /// on the clone frees it.
    alloc: std.mem.Allocator,
    /// HINSTANCE used for window class registration + creation.
    hinstance: HINSTANCE,
    /// Theme color snapshot. Queried per paint so theme swaps propagate.
    uiColors: *const fn (ctx: *anyopaque) UiColors,
    /// Apply the app's DWM window decoration (dark titlebar, caption
    /// colors) to the settings HWND. Called once per window creation.
    decorateWindow: *const fn (ctx: *anyopaque, hwnd: HWND) void,
    /// Fire-and-forget shell-out to the OS default text editor with
    /// the resolved `ghostty.conf` path. Used by the Advanced-pane
    /// escape hatch.
    openInEditor: *const fn (ctx: *anyopaque) void,
    /// Snapshot the currently-active Config. The returned pointer is
    /// only valid until the next config reload; the settings window
    /// holds it as `original` for the duration of the pending-clone
    /// session.
    currentConfig: *const fn (ctx: *anyopaque) *const Config,
    /// Serialise `pending` to disk (atomic-rename via `ReplaceFileW`
    /// where supported, falling back to `MoveFileExW`) and refresh
    /// the live app config + all surfaces. `original` is the
    /// snapshot captured when the settings window opened; the save
    /// path diffs pending against it (NOT against `App.config`) so
    /// an external `reload_config` or file edit that fires while the
    /// window is open doesn't get silently reverted by our save.
    /// Caller owns both.
    saveAndReload: *const fn (
        ctx: *anyopaque,
        pending: *const Config,
        original: *const Config,
    ) SaveError!void,
    /// Fire-and-forget success toast for the app-level in-app stack
    /// (e.g. "Settings saved"). Borrowed title + body — caller must
    /// keep them alive only for the duration of the call; the stack
    /// copies internally.
    notifySuccess: *const fn (ctx: *anyopaque, title: []const u8, body: []const u8) void,
    /// Fired after the settings window's HWND is destroyed. Lets the
    /// app re-evaluate its quit-timer policy (the settings HWND
    /// participates in the "has live UI windows" count so closing
    /// the last terminal while settings is open does not auto-quit;
    /// once settings itself closes the timer can kick in).
    onClosed: *const fn (ctx: *anyopaque) void,
};

/// One row of the theme picker: display name, absolute file path, and the
/// lazily-parsed color swatch (tried-once semantics so unreadable files
/// don't re-parse every paint).
const ThemeEntry = struct {
    name: [:0]u8,
    path: [:0]u8,
    swatch: ?ThemeSwatch = null,
    swatch_tried: bool = false,
};

/// Colors extracted from a theme file for the picker's preview chips.
/// Values are 0xRRGGBB (converted to COLORREF at draw time).
pub const ThemeSwatch = struct {
    background: ?u32 = null,
    foreground: ?u32 = null,
    palette: [8]?u32 = .{null} ** 8,
};

pub const SettingsWindow = struct {
    handle: AppHandle,
    hwnd: ?HWND = null,
    btn_open_editor: ?HWND = null,
    btn_section_appearance: ?HWND = null,
    btn_section_theme: ?HWND = null,
    btn_section_terminal: ?HWND = null,
    btn_section_shell: ?HWND = null,
    btn_section_keybindings: ?HWND = null,
    btn_section_windows: ?HWND = null,
    btn_section_advanced: ?HWND = null,
    btn_section_agents: ?HWND = null,
    edit_theme_search: ?HWND = null,
    edit_settings_search: ?HWND = null,
    /// True while the rail search query matches no section; tints the
    /// search box so the miss is visible without a banner.
    settings_search_missed: bool = false,
    list_themes: ?HWND = null,
    chk_explorer_menu: ?HWND = null,
    /// Theme catalogue backing the picker. All entry strings live in
    /// `theme_arena`; loaded once per window open, dropped on close.
    theme_arena: ?std.heap.ArenaAllocator = null,
    themes: []ThemeEntry = &.{},
    /// UI fonts, created with the HWND and deleted with it.
    font_title: HGDIOBJ = null,
    font_body: HGDIOBJ = null,
    font_label: HGDIOBJ = null,
    btn_save: ?HWND = null,
    btn_keybindings_editor: ?HWND = null,
    edit_scrollback: ?HWND = null,
    edit_font_family: ?HWND = null,
    edit_font_size: ?HWND = null,
    edit_theme: ?HWND = null,
    edit_bg_opacity: ?HWND = null,
    edit_command: ?HWND = null,
    edit_pad_x: ?HWND = null,
    edit_pad_y: ?HWND = null,
    combo_confirm_close: ?HWND = null,
    combo_copy_on_select: ?HWND = null,
    combo_window_theme: ?HWND = null,
    combo_shell_integ: ?HWND = null,
    chk_trim_trail: ?HWND = null,
    chk_desktop_notifications: ?HWND = null,
    chk_app_notify_clipboard: ?HWND = null,
    chk_app_notify_config: ?HWND = null,
    combo_clipboard_read: ?HWND = null,
    combo_clipboard_write: ?HWND = null,
    combo_link_url: ?HWND = null,
    combo_link_previews: ?HWND = null,
    combo_cursor_style: ?HWND = null,
    chk_bg_blur: ?HWND = null,
    edit_digest_min: ?HWND = null,
    edit_alert_keywords: ?HWND = null,
    edit_token_budget: ?HWND = null,
    edit_auto_restart: ?HWND = null,
    edit_ws_layout: ?HWND = null,
    chk_focus_follows: ?HWND = null,
    combo_pad_balance: ?HWND = null,
    combo_auto_update: ?HWND = null,
    combo_auto_update_channel: ?HWND = null,
    active_section: Section = .appearance,
    /// Class atom lazily registered the first time `open` runs.
    class_atom: ATOM = 0,

    /// Frozen snapshot of the config at the moment the window last
    /// opened. Owned by this struct via `Config.shallowClone` so an
    /// external `reload_config` that fires while the window is open
    /// does not mutate our diff baseline. Only valid while
    /// `pending != null`.
    original: ?Config = null,
    /// Editable draft owned by `handle.alloc`. Created on open via
    /// `Config.shallowClone(handle.alloc)`; freed on close/save. Per
    /// AGENTS.md:49, we must NOT deinit an inherited `command` field
    /// on this clone — `Config.deinit` already honours that because
    /// the clone owns only its `_arena`, not the inherited pointers.
    pending: ?Config = null,
    /// Guard flag so the EN_CHANGE handler doesn't fire a cascade
    /// when we programmatically set the EDIT text on open.
    suppress_edit_events: bool = false,

    pub fn init(handle: AppHandle) SettingsWindow {
        return .{ .handle = handle };
    }

    pub fn deinit(self: *SettingsWindow) void {
        if (self.hwnd) |h| {
            if (IsWindow(h) != 0) _ = DestroyWindow(h);
        }
        self.hwnd = null;
        self.btn_open_editor = null;
        self.btn_section_appearance = null;
        self.btn_section_theme = null;
        self.btn_section_terminal = null;
        self.btn_section_shell = null;
        self.btn_section_keybindings = null;
        self.btn_section_windows = null;
        self.btn_section_advanced = null;
        self.btn_section_agents = null;
        self.edit_theme_search = null;
        self.list_themes = null;
        self.chk_explorer_menu = null;
        self.clearThemeData();
        self.btn_save = null;
        self.btn_keybindings_editor = null;
        self.edit_scrollback = null;
        self.edit_font_family = null;
        self.edit_font_size = null;
        self.edit_theme = null;
        self.edit_bg_opacity = null;
        self.edit_command = null;
        self.edit_pad_x = null;
        self.edit_pad_y = null;
        self.combo_confirm_close = null;
        self.combo_copy_on_select = null;
        self.combo_window_theme = null;
        self.combo_shell_integ = null;
        self.chk_trim_trail = null;
        self.chk_desktop_notifications = null;
        self.chk_app_notify_clipboard = null;
        self.chk_app_notify_config = null;
        self.combo_clipboard_read = null;
        self.combo_clipboard_write = null;
        self.combo_link_url = null;
        self.combo_link_previews = null;
        self.combo_cursor_style = null;
        self.chk_bg_blur = null;
        self.combo_pad_balance = null;
        self.combo_auto_update = null;
        self.combo_auto_update_channel = null;
        self.clearPending();
    }

    /// Drop the pending draft (if any) and its arena. Safe to call
    /// multiple times. Called from close paths and after Save so the
    /// next `open` starts with a fresh clone of the (possibly just-
    /// reloaded) app config.
    fn clearPending(self: *SettingsWindow) void {
        if (self.pending) |*p| p.deinit();
        self.pending = null;
        if (self.original) |*o| o.deinit();
        self.original = null;
    }

    /// Null out child HWND references + drop pending. Called from
    /// both WM_CLOSE and WM_NCDESTROY so the next `open()` recreates
    /// fresh children and clones.
    fn clearChildRefs(self: *SettingsWindow) void {
        self.clearFonts();
        self.hwnd = null;
        self.btn_open_editor = null;
        self.btn_section_appearance = null;
        self.btn_section_theme = null;
        self.btn_section_terminal = null;
        self.btn_section_shell = null;
        self.btn_section_keybindings = null;
        self.btn_section_windows = null;
        self.btn_section_advanced = null;
        self.btn_section_agents = null;
        self.edit_theme_search = null;
        self.list_themes = null;
        self.chk_explorer_menu = null;
        self.clearThemeData();
        self.btn_save = null;
        self.btn_keybindings_editor = null;
        self.edit_scrollback = null;
        self.edit_font_family = null;
        self.edit_font_size = null;
        self.edit_theme = null;
        self.edit_bg_opacity = null;
        self.edit_command = null;
        self.edit_pad_x = null;
        self.edit_pad_y = null;
        self.combo_confirm_close = null;
        self.combo_copy_on_select = null;
        self.combo_window_theme = null;
        self.combo_shell_integ = null;
        self.chk_trim_trail = null;
        self.chk_desktop_notifications = null;
        self.chk_app_notify_clipboard = null;
        self.chk_app_notify_config = null;
        self.combo_clipboard_read = null;
        self.combo_clipboard_write = null;
        self.combo_link_url = null;
        self.combo_link_previews = null;
        self.combo_cursor_style = null;
        self.chk_bg_blur = null;
        self.combo_pad_balance = null;
        self.combo_auto_update = null;
        self.combo_auto_update_channel = null;
        self.clearPending();
    }

    fn sectionButton(self: *const SettingsWindow, section: Section) ?HWND {
        return switch (section) {
            .appearance => self.btn_section_appearance,
            .theme => self.btn_section_theme,
            .terminal => self.btn_section_terminal,
            .shell => self.btn_section_shell,
            .keybindings => self.btn_section_keybindings,
            .windows => self.btn_section_windows,
            .advanced => self.btn_section_advanced,
            .agents => self.btn_section_agents,
        };
    }

    /// Drop the theme catalogue and its arena. Safe to call repeatedly.
    fn clearThemeData(self: *SettingsWindow) void {
        if (self.theme_arena) |*arena| arena.deinit();
        self.theme_arena = null;
        self.themes = &.{};
    }

    /// Delete the UI fonts. Runs with window teardown, so no control
    /// still references them. Safe to call repeatedly.
    fn clearFonts(self: *SettingsWindow) void {
        if (self.font_title) |f| _ = DeleteObject(f);
        if (self.font_body) |f| _ = DeleteObject(f);
        if (self.font_label) |f| _ = DeleteObject(f);
        self.font_title = null;
        self.font_body = null;
        self.font_label = null;
    }

    fn setActiveSection(self: *SettingsWindow, next: Section) void {
        if (self.active_section == next and self.hwnd != null) return;
        self.active_section = next;
        self.applySectionVisibility();
        if (self.hwnd) |h| _ = InvalidateRect(h, null, 1);
        // Owner-drawn rail buttons repaint from their own DC, so the
        // parent invalidation above doesn't move the active stripe.
        inline for (.{
            self.btn_section_appearance, self.btn_section_theme,
            self.btn_section_terminal,   self.btn_section_shell,
            self.btn_section_keybindings, self.btn_section_windows,
            self.btn_section_advanced,
            self.btn_section_agents,
        }) |maybe_btn| {
            if (maybe_btn) |btn| _ = InvalidateRect(btn, null, 1);
        }
    }

    fn applySectionVisibility(self: *SettingsWindow) void {
        const show_advanced: i32 = if (self.active_section == .advanced) SW_SHOWNORMAL else SW_HIDE;
        const show_terminal: i32 = if (self.active_section == .terminal) SW_SHOWNORMAL else SW_HIDE;
        const show_appearance: i32 = if (self.active_section == .appearance) SW_SHOWNORMAL else SW_HIDE;
        const show_shell: i32 = if (self.active_section == .shell) SW_SHOWNORMAL else SW_HIDE;
        const show_keybindings: i32 = if (self.active_section == .keybindings) SW_SHOWNORMAL else SW_HIDE;
        const show_theme: i32 = if (self.active_section == .theme) SW_SHOWNORMAL else SW_HIDE;
        const show_windows: i32 = if (self.active_section == .windows) SW_SHOWNORMAL else SW_HIDE;
        const show_agents: i32 = if (self.active_section == .agents) SW_SHOWNORMAL else SW_HIDE;

        if (self.edit_theme_search) |e| _ = ShowWindow(e, show_theme);
        if (self.list_themes) |e| _ = ShowWindow(e, show_theme);
        if (self.chk_explorer_menu) |e| _ = ShowWindow(e, show_windows);
        if (self.btn_open_editor) |btn| _ = ShowWindow(btn, show_advanced);
        if (self.btn_keybindings_editor) |btn| _ = ShowWindow(btn, show_keybindings);
        if (self.edit_scrollback) |e| _ = ShowWindow(e, show_terminal);
        if (self.combo_confirm_close) |e| _ = ShowWindow(e, show_terminal);
        if (self.combo_copy_on_select) |e| _ = ShowWindow(e, show_terminal);
        if (self.chk_trim_trail) |e| _ = ShowWindow(e, show_terminal);
        if (self.chk_desktop_notifications) |e| _ = ShowWindow(e, show_terminal);
        if (self.chk_app_notify_clipboard) |e| _ = ShowWindow(e, show_terminal);
        if (self.chk_app_notify_config) |e| _ = ShowWindow(e, show_terminal);
        if (self.combo_clipboard_read) |e| _ = ShowWindow(e, show_terminal);
        if (self.combo_clipboard_write) |e| _ = ShowWindow(e, show_terminal);
        if (self.combo_link_url) |e| _ = ShowWindow(e, show_terminal);
        if (self.combo_link_previews) |e| _ = ShowWindow(e, show_terminal);
        if (self.edit_font_family) |e| _ = ShowWindow(e, show_appearance);
        if (self.edit_font_size) |e| _ = ShowWindow(e, show_appearance);
        if (self.edit_theme) |e| _ = ShowWindow(e, show_appearance);
        if (self.edit_bg_opacity) |e| _ = ShowWindow(e, show_appearance);
        if (self.combo_window_theme) |e| _ = ShowWindow(e, show_appearance);
        if (self.combo_cursor_style) |e| _ = ShowWindow(e, show_appearance);
        if (self.edit_pad_x) |e| _ = ShowWindow(e, show_appearance);
        if (self.edit_pad_y) |e| _ = ShowWindow(e, show_appearance);
        if (self.chk_bg_blur) |e| _ = ShowWindow(e, show_appearance);
        if (self.combo_pad_balance) |e| _ = ShowWindow(e, show_appearance);
        if (self.edit_digest_min) |e| _ = ShowWindow(e, show_agents);
        if (self.edit_alert_keywords) |e| _ = ShowWindow(e, show_agents);
        if (self.edit_token_budget) |e| _ = ShowWindow(e, show_agents);
        if (self.edit_auto_restart) |e| _ = ShowWindow(e, show_agents);
        if (self.edit_ws_layout) |e| _ = ShowWindow(e, show_agents);
        if (self.chk_focus_follows) |e| _ = ShowWindow(e, show_agents);
        if (self.edit_command) |e| _ = ShowWindow(e, show_shell);
        if (self.combo_shell_integ) |e| _ = ShowWindow(e, show_shell);
        if (self.combo_auto_update) |e| _ = ShowWindow(e, show_advanced);
        if (self.combo_auto_update_channel) |e| _ = ShowWindow(e, show_advanced);
    }

    /// Read the current EDIT text and write the parsed integer into
    /// the pending draft. Called from EN_CHANGE. Swallows parse
    /// errors silently — ES_NUMBER style means the text is already
    /// digits-only, but the empty-string case needs to map to 0 (or
    /// be ignored).
    fn syncScrollbackFromEdit(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const edit = self.edit_scrollback orelse return;

        var buf_w: [32]u16 = undefined;
        const n = GetWindowTextW(edit, &buf_w, @intCast(buf_w.len));
        if (n <= 0) return;
        var utf8_buf: [64]u8 = undefined;
        const utf8 = std.unicode.utf16LeToUtf8(&utf8_buf, buf_w[0..@intCast(n)]) catch return;
        const trimmed = std.mem.trim(u8, utf8_buf[0..utf8], " \t");
        if (trimmed.len == 0) return;
        const parsed = std.fmt.parseInt(usize, trimmed, 10) catch return;
        p.*.@"scrollback-limit" = parsed;
    }

    fn displayScrollbackInEdit(self: *SettingsWindow) void {
        const edit = self.edit_scrollback orelse return;
        const p = self.pending orelse return;
        var buf: [32]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d}", .{p.@"scrollback-limit"}) catch return;
        var buf_w: [32]u16 = undefined;
        const w = utf8ToW(&buf_w, text);
        self.suppress_edit_events = true;
        _ = SendMessageW(edit, WM_SETTEXT, 0, @bitCast(@intFromPtr(w)));
        self.suppress_edit_events = false;
    }

    fn syncFontFamilyFromEdit(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const arena = p.*._arena.?.allocator();
        const edit = self.edit_font_family orelse return;
        var text_buf: [edit_text_max_utf8]u8 = undefined;
        const text = readEditUtf8(edit, &text_buf) orelse return;
        p.*.@"font-family" = parseFontFamilyEditText(arena, text) catch return;
    }

    fn displayFontFamilyInEdit(self: *SettingsWindow) void {
        const edit = self.edit_font_family orelse return;
        const p = self.pending orelse return;
        var buf: [edit_text_max_utf8]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        for (p.@"font-family".list.items, 0..) |family, i| {
            if (i != 0) writer.writeAll(", ") catch break;
            writer.writeAll(family) catch break;
        }
        setEditText(edit, writer.buffered(), &self.suppress_edit_events);
    }

    fn syncFontSizeFromEdit(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const edit = self.edit_font_size orelse return;
        var buf_w: [32]u16 = undefined;
        const n = GetWindowTextW(edit, &buf_w, @intCast(buf_w.len));
        if (n <= 0) return;
        var utf8_buf: [64]u8 = undefined;
        const utf8 = std.unicode.utf16LeToUtf8(&utf8_buf, buf_w[0..@intCast(n)]) catch return;
        const trimmed = std.mem.trim(u8, utf8_buf[0..utf8], " \t");
        if (trimmed.len == 0) return;
        const parsed = std.fmt.parseFloat(f32, trimmed) catch return;
        // Range-clamp: Ghostty Config default is 12 pt; our range is
        // the same the GUI spinner catalogue will offer (6..72).
        if (parsed < 6.0 or parsed > 72.0) return;
        p.*.@"font-size" = parsed;
    }

    fn displayFontSizeInEdit(self: *SettingsWindow) void {
        const edit = self.edit_font_size orelse return;
        const p = self.pending orelse return;
        var buf: [32]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d:.1}", .{p.@"font-size"}) catch return;
        var buf_w: [32]u16 = undefined;
        const w = utf8ToW(&buf_w, text);
        self.suppress_edit_events = true;
        _ = SendMessageW(edit, WM_SETTEXT, 0, @bitCast(@intFromPtr(w)));
        self.suppress_edit_events = false;
    }

    fn syncThemeFromEdit(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const arena = p.*._arena.?.allocator();
        const edit = self.edit_theme orelse return;
        var text_buf: [edit_text_max_utf8]u8 = undefined;
        const text = readEditUtf8(edit, &text_buf) orelse return;
        const trimmed = std.mem.trim(u8, text, " \t");
        if (trimmed.len == 0) {
            p.*.theme = null;
            return;
        }
        var theme: Config.Theme = undefined;
        theme.parseCLI(arena, trimmed) catch return;
        p.*.theme = theme;
    }

    fn displayThemeInEdit(self: *SettingsWindow) void {
        const edit = self.edit_theme orelse return;
        const p = self.pending orelse return;
        var buf: [edit_text_max_utf8]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        if (p.theme) |theme| {
            if (std.mem.eql(u8, theme.light, theme.dark)) {
                writer.writeAll(theme.light) catch {};
            } else {
                writer.print("light:{s},dark:{s}", .{ theme.light, theme.dark }) catch {};
            }
        }
        setEditText(edit, writer.buffered(), &self.suppress_edit_events);
    }

    /// Enumerate every theme from the user + resources theme dirs into
    /// `self.themes`, sorted case-insensitively, user dir winning name
    /// collisions (same priority order the config loader uses). Loaded
    /// once per window open; failures leave an empty catalogue (the
    /// picker then just shows nothing — the raw theme edit still works).
    fn loadThemeCatalogue(self: *SettingsWindow) void {
        if (self.theme_arena != null) return;
        var arena = std.heap.ArenaAllocator.init(self.handle.alloc);
        const aa = arena.allocator();

        var entries: std.ArrayListUnmanaged(ThemeEntry) = .{};
        var seen: std.StringHashMapUnmanaged(void) = .{};
        var it = themepkg.LocationIterator{ .arena_alloc = aa };
        while (it.next() catch null) |loc| {
            var dir = std.fs.cwd().openDir(loc.dir, .{ .iterate = true }) catch continue;
            defer dir.close();
            var dir_it = dir.iterate();
            while (dir_it.next() catch null) |dent| {
                if (dent.kind != .file) continue;
                if (seen.contains(dent.name)) continue;
                const name = aa.dupeZ(u8, dent.name) catch continue;
                seen.put(aa, name, {}) catch continue;
                const path = std.fs.path.joinZ(aa, &.{ loc.dir, dent.name }) catch continue;
                entries.append(aa, .{ .name = name, .path = path }) catch continue;
            }
        }
        std.mem.sort(ThemeEntry, entries.items, {}, themeEntryLessThan);
        self.themes = entries.items;
        self.theme_arena = arena;
    }

    /// Refill the theme listbox from the catalogue, filtered by the
    /// search box (case-insensitive substring). Item data carries the
    /// catalogue index so filtering never desyncs selection handling.
    fn rebuildThemeList(self: *SettingsWindow) void {
        const list = self.list_themes orelse return;
        self.loadThemeCatalogue();

        var filter_buf: [128]u8 = undefined;
        const filter: []const u8 = blk: {
            const edit = self.edit_theme_search orelse break :blk "";
            const text = readEditUtf8(edit, &filter_buf) orelse break :blk "";
            break :blk std.mem.trim(u8, text, " \t");
        };

        _ = SendMessageW(list, LB_RESETCONTENT, 0, 0);
        for (self.themes, 0..) |entry, idx| {
            if (filter.len > 0 and std.ascii.indexOfIgnoreCase(entry.name, filter) == null) continue;
            var name_w: [256]u16 = undefined;
            const w = utf8ToW(&name_w, entry.name);
            const item: usize = @bitCast(SendMessageW(list, LB_ADDSTRING, 0, @bitCast(@intFromPtr(w))));
            if (@as(isize, @bitCast(item)) >= 0) {
                _ = SendMessageW(list, LB_SETITEMDATA, item, @bitCast(idx));
            }
        }
        self.selectThemeListCurrent();
    }

    /// Highlight the pending theme in the list when it is a single
    /// (non light/dark-split) name that survived the filter.
    fn selectThemeListCurrent(self: *SettingsWindow) void {
        const list = self.list_themes orelse return;
        const p = self.pending orelse return;
        const theme = p.theme orelse return;
        if (!std.mem.eql(u8, theme.light, theme.dark)) return;

        const count: isize = SendMessageW(list, LB_GETCOUNT, 0, 0);
        if (count <= 0) return;
        var i: usize = 0;
        while (i < @as(usize, @intCast(count))) : (i += 1) {
            const data: isize = SendMessageW(list, LB_GETITEMDATA, i, 0);
            if (data < 0) continue;
            const idx: usize = @intCast(data);
            if (idx >= self.themes.len) continue;
            if (std.mem.eql(u8, self.themes[idx].name, theme.light)) {
                _ = SendMessageW(list, LB_SETCURSEL, i, 0);
                return;
            }
        }
    }

    /// LBN_SELCHANGE: write the selected theme name into the pending
    /// draft and mirror it into the raw theme edit (Appearance section)
    /// so both surfaces agree.
    fn applyThemeSelectionFromList(self: *SettingsWindow) void {
        const list = self.list_themes orelse return;
        const p = &(self.pending orelse return);
        const sel: isize = SendMessageW(list, LB_GETCURSEL, 0, 0);
        if (sel < 0) return;
        const data: isize = SendMessageW(list, LB_GETITEMDATA, @intCast(sel), 0);
        if (data < 0) return;
        const idx: usize = @intCast(data);
        if (idx >= self.themes.len) return;

        const arena = p.*._arena.?.allocator();
        var theme: Config.Theme = undefined;
        theme.parseCLI(arena, self.themes[idx].name) catch return;
        p.*.theme = theme;
        self.displayThemeInEdit();
    }

    /// Parse the swatch colors for one catalogue entry (once).
    fn ensureThemeSwatch(self: *SettingsWindow, idx: usize) ?ThemeSwatch {
        if (idx >= self.themes.len) return null;
        const entry = &self.themes[idx];
        if (entry.swatch_tried) return entry.swatch;
        entry.swatch_tried = true;

        const file = std.fs.cwd().openFile(entry.path, .{}) catch return null;
        defer file.close();
        var buf: [8192]u8 = undefined;
        const n = file.readAll(&buf) catch return null;
        entry.swatch = parseThemeSwatch(buf[0..n]);
        return entry.swatch;
    }

    /// Owner-draw for one theme row: [bg chip with "Aa" in fg] [8 palette
    /// chips] name. Falls back to a plain text row when the theme file
    /// couldn't be parsed.
    fn drawThemeListItem(self: *SettingsWindow, dis: *const DRAWITEMSTRUCT) void {
        const hdc = dis.hDC;
        const brush = GetStockObject(DC_BRUSH);
        const colors = self.handle.uiColors(self.handle.ctx);
        const selected = (dis.itemState & ODS_SELECTED) != 0;
        const row_bg: COLORREF = if (selected) colors.active_bg else colors.field_bg;

        _ = SetDCBrushColor(hdc, row_bg);
        _ = FillRect(hdc, &dis.rcItem, brush);
        if (dis.itemID == 0xFFFFFFFF) return;

        const idx: usize = dis.itemData;
        if (idx >= self.themes.len) return;
        const entry = self.themes[idx];
        const swatch = self.ensureThemeSwatch(idx);

        var x: i32 = dis.rcItem.left + 6;
        const row_h = dis.rcItem.bottom - dis.rcItem.top;

        if (swatch) |sw| {
            // Background chip with "Aa" rendered in the theme foreground.
            const chip_h = row_h - 8;
            const chip_w: i32 = 34;
            var chip = RECT{
                .left = x,
                .top = dis.rcItem.top + 4,
                .right = x + chip_w,
                .bottom = dis.rcItem.top + 4 + chip_h,
            };
            const chip_bg: COLORREF = rgbToColorref(sw.background orelse 0x000000);
            _ = SetDCBrushColor(hdc, chip_bg);
            _ = FillRect(hdc, &chip, brush);
            _ = SetBkMode(hdc, TRANSPARENT);
            _ = SetTextColor(hdc, rgbToColorref(sw.foreground orelse 0xFFFFFF));
            const aa_w = std.unicode.utf8ToUtf16LeStringLiteral("Aa");
            var chip_text = chip;
            _ = DrawTextW(hdc, aa_w, -1, &chip_text, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
            x += chip_w + 8;

            // Palette chips (first 8 ANSI colors).
            const dot: i32 = 8;
            const dot_top = dis.rcItem.top + @divTrunc(row_h - dot, 2);
            for (sw.palette) |maybe_color| {
                const color = maybe_color orelse continue;
                var dot_rect = RECT{
                    .left = x,
                    .top = dot_top,
                    .right = x + dot,
                    .bottom = dot_top + dot,
                };
                _ = SetDCBrushColor(hdc, rgbToColorref(color));
                _ = FillRect(hdc, &dot_rect, brush);
                x += dot + 2;
            }
            x += 8;
        }

        _ = SetBkMode(hdc, TRANSPARENT);
        _ = SetTextColor(hdc, colors.text);
        var name_w: [256]u16 = undefined;
        const w = utf8ToW(&name_w, entry.name);
        var text_rect = RECT{
            .left = x,
            .top = dis.rcItem.top,
            .right = dis.rcItem.right - 4,
            .bottom = dis.rcItem.bottom,
        };
        _ = DrawTextW(hdc, w, -1, &text_rect, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }

    /// Owner-draw for every push button: the section rail (flat rows,
    /// accent stripe + active fill for the current section), the primary
    /// Save button (accent fill), and secondary utility buttons (outline).
    fn drawOwnerButton(self: *SettingsWindow, dis: *const DRAWITEMSTRUCT) void {
        const hdc = dis.hDC;
        const brush = GetStockObject(DC_BRUSH);
        const colors = self.handle.uiColors(self.handle.ctx);
        const pressed = (dis.itemState & ODS_SELECTED) != 0;
        const focused = (dis.itemState & ODS_FOCUS) != 0;

        var label_w: [128]u16 = undefined;
        const label_len = GetWindowTextW(dis.hwndItem, &label_w, label_w.len);
        const label: [*:0]const u16 = blk: {
            label_w[@intCast(@max(0, label_len))] = 0;
            break :blk @ptrCast(&label_w);
        };

        if (Section.fromButtonId(dis.CtlID)) |section| {
            const active = section == self.active_section;
            const bg: COLORREF = if (active)
                colors.active_bg
            else if (pressed)
                colors.field_bg
            else
                colors.rail_bg;
            _ = SetDCBrushColor(hdc, bg);
            _ = FillRect(hdc, &dis.rcItem, brush);
            if (active) {
                var stripe = dis.rcItem;
                stripe.right = stripe.left + 3;
                _ = SetDCBrushColor(hdc, colors.accent);
                _ = FillRect(hdc, &stripe, brush);
            }
            if (focused) strokeRect(hdc, dis.rcItem, colors.accent);
            _ = SetBkMode(hdc, TRANSPARENT);
            _ = SetTextColor(hdc, if (active) colors.text else colors.text_muted);
            if (self.font_body) |font| _ = SelectObject(hdc, font);
            var text_rect = dis.rcItem;
            text_rect.left += 16;
            _ = DrawTextW(hdc, label, -1, &text_rect, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
            return;
        }

        const primary = dis.CtlID == BTN_SAVE;
        const bg: COLORREF = if (primary)
            (if (pressed) colors.active_bg else colors.accent)
        else
            (if (pressed) colors.active_bg else colors.field_bg);
        _ = SetDCBrushColor(hdc, bg);
        _ = FillRect(hdc, &dis.rcItem, brush);
        // 1px outline so secondary buttons read as buttons on flat bg;
        // keyboard focus upgrades it to the accent color.
        strokeRect(
            hdc,
            dis.rcItem,
            if (primary or focused) colors.accent else colors.border,
        );

        _ = SetBkMode(hdc, TRANSPARENT);
        // Accent-filled Save gets contrast-appropriate text.
        _ = SetTextColor(hdc, if (primary and !colors.is_dark) 0x00FFFFFF else colors.text);
        if (self.font_body) |font| _ = SelectObject(hdc, font);
        var text_rect = dis.rcItem;
        _ = DrawTextW(hdc, label, -1, &text_rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }

    /// BN_CLICKED on the Explorer checkbox: apply the registry change
    /// immediately (it is not part of the config file / Save flow),
    /// then re-read the actual status so a failed write can't leave
    /// the checkbox lying.
    fn syncExplorerMenuFromCheckbox(self: *SettingsWindow) void {
        const chk = self.chk_explorer_menu orelse return;
        const checked = SendMessageW(chk, BM_GETCHECK, 0, 0) == @as(LRESULT, @intCast(BST_CHECKED));
        if (checked) {
            win32_explorer_menu.register(self.handle.alloc);
        } else {
            win32_explorer_menu.unregister(self.handle.alloc);
        }
        self.displayExplorerMenuCheckbox();
    }

    fn displayExplorerMenuCheckbox(self: *SettingsWindow) void {
        const chk = self.chk_explorer_menu orelse return;
        const registered = win32_explorer_menu.status(self.handle.alloc) != .not_registered;
        _ = SendMessageW(chk, BM_SETCHECK, if (registered) BST_CHECKED else BST_UNCHECKED, 0);
    }

    fn syncBgOpacityFromEdit(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const edit = self.edit_bg_opacity orelse return;
        var buf_w: [32]u16 = undefined;
        const n = GetWindowTextW(edit, &buf_w, @intCast(buf_w.len));
        if (n <= 0) return;
        var utf8_buf: [64]u8 = undefined;
        const utf8 = std.unicode.utf16LeToUtf8(&utf8_buf, buf_w[0..@intCast(n)]) catch return;
        const trimmed = std.mem.trim(u8, utf8_buf[0..utf8], " \t");
        if (trimmed.len == 0) return;
        const parsed = std.fmt.parseFloat(f64, trimmed) catch return;
        if (parsed < 0.0 or parsed > 1.0) return;
        p.*.@"background-opacity" = parsed;
    }

    fn displayBgOpacityInEdit(self: *SettingsWindow) void {
        const edit = self.edit_bg_opacity orelse return;
        const p = self.pending orelse return;
        var buf: [32]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d:.2}", .{p.@"background-opacity"}) catch return;
        var buf_w: [32]u16 = undefined;
        const w = utf8ToW(&buf_w, text);
        self.suppress_edit_events = true;
        _ = SendMessageW(edit, WM_SETTEXT, 0, @bitCast(@intFromPtr(w)));
        self.suppress_edit_events = false;
    }

    fn syncCommandFromEdit(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const arena = p.*._arena.?.allocator();
        const edit = self.edit_command orelse return;
        var text_buf: [edit_text_max_utf8]u8 = undefined;
        const text = readEditUtf8(edit, &text_buf) orelse return;
        const trimmed = std.mem.trim(u8, text, " \t");
        if (trimmed.len == 0) {
            p.*.command = null;
            return;
        }
        var command: Config.Command = undefined;
        command.parseCLI(arena, trimmed) catch return;
        p.*.command = command;
    }

    fn displayCommandInEdit(self: *SettingsWindow) void {
        const edit = self.edit_command orelse return;
        const p = self.pending orelse return;
        var buf: [edit_text_max_utf8]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        if (p.command) |command| writeCommandForEdit(&writer, command) catch {};
        setEditText(edit, writer.buffered(), &self.suppress_edit_events);
    }

    fn syncPaddingFromEdit(self: *SettingsWindow, axis: PaddingAxis) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const edit = switch (axis) {
            .x => self.edit_pad_x,
            .y => self.edit_pad_y,
        } orelse return;
        var text_buf: [64]u8 = undefined;
        const text = readEditUtf8(edit, &text_buf) orelse return;
        const parsed = Config.WindowPadding.parseCLI(std.mem.trim(u8, text, " \t")) catch return;
        switch (axis) {
            .x => p.*.@"window-padding-x" = parsed,
            .y => p.*.@"window-padding-y" = parsed,
        }
    }

    fn displayPaddingInEdit(self: *SettingsWindow, axis: PaddingAxis) void {
        const edit = switch (axis) {
            .x => self.edit_pad_x,
            .y => self.edit_pad_y,
        } orelse return;
        const p = self.pending orelse return;
        const padding = switch (axis) {
            .x => p.@"window-padding-x",
            .y => p.@"window-padding-y",
        };
        var buf: [64]u8 = undefined;
        const text = if (padding.top_left == padding.bottom_right)
            std.fmt.bufPrint(&buf, "{d}", .{padding.top_left}) catch return
        else
            std.fmt.bufPrint(&buf, "{d},{d}", .{ padding.top_left, padding.bottom_right }) catch return;
        setEditText(edit, text, &self.suppress_edit_events);
    }

    fn syncTrimTrailFromCheckbox(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const chk = self.chk_trim_trail orelse return;
        const state = SendMessageW(chk, BM_GETCHECK, 0, 0);
        p.*.@"clipboard-trim-trailing-spaces" = (state == BST_CHECKED);
    }

    fn displayTrimTrailInCheckbox(self: *SettingsWindow) void {
        const chk = self.chk_trim_trail orelse return;
        const p = self.pending orelse return;
        self.suppress_edit_events = true;
        _ = SendMessageW(
            chk,
            BM_SETCHECK,
            if (p.@"clipboard-trim-trailing-spaces") BST_CHECKED else BST_UNCHECKED,
            0,
        );
        self.suppress_edit_events = false;
    }

    fn syncDesktopNotificationsFromCheckbox(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const chk = self.chk_desktop_notifications orelse return;
        p.*.@"desktop-notifications" = SendMessageW(chk, BM_GETCHECK, 0, 0) == BST_CHECKED;
    }

    fn displayDesktopNotificationsInCheckbox(self: *SettingsWindow) void {
        const chk = self.chk_desktop_notifications orelse return;
        const p = self.pending orelse return;
        self.suppress_edit_events = true;
        _ = SendMessageW(
            chk,
            BM_SETCHECK,
            if (p.@"desktop-notifications") BST_CHECKED else BST_UNCHECKED,
            0,
        );
        self.suppress_edit_events = false;
    }

    fn syncAppNotificationsFromCheckbox(self: *SettingsWindow, field: AppNotificationField) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const chk = switch (field) {
            .clipboard => self.chk_app_notify_clipboard,
            .config => self.chk_app_notify_config,
        } orelse return;
        const enabled = SendMessageW(chk, BM_GETCHECK, 0, 0) == BST_CHECKED;
        switch (field) {
            .clipboard => p.*.@"app-notifications".@"clipboard-copy" = enabled,
            .config => p.*.@"app-notifications".@"config-reload" = enabled,
        }
    }

    fn displayAppNotificationsInCheckbox(self: *SettingsWindow, field: AppNotificationField) void {
        const chk = switch (field) {
            .clipboard => self.chk_app_notify_clipboard,
            .config => self.chk_app_notify_config,
        } orelse return;
        const p = self.pending orelse return;
        const enabled = switch (field) {
            .clipboard => p.@"app-notifications".@"clipboard-copy",
            .config => p.@"app-notifications".@"config-reload",
        };
        self.suppress_edit_events = true;
        _ = SendMessageW(chk, BM_SETCHECK, if (enabled) BST_CHECKED else BST_UNCHECKED, 0);
        self.suppress_edit_events = false;
    }

    /// Enum combo helpers. `fromIndex` maps combobox selection to
    /// config enum value; `toIndex` goes the other direction for
    /// initial display.
    fn syncConfirmCloseFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_confirm_close orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"confirm-close-surface" = switch (idx) {
            0 => .false,
            1 => .true,
            2 => .always,
            else => return,
        };
    }

    fn displayConfirmCloseInCombo(self: *SettingsWindow) void {
        const combo = self.combo_confirm_close orelse return;
        const p = self.pending orelse return;
        const idx: usize = switch (p.@"confirm-close-surface") {
            .false => 0,
            .true => 1,
            .always => 2,
        };
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncCopyOnSelectFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_copy_on_select orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"copy-on-select" = switch (idx) {
            0 => .false,
            1 => .true,
            2 => .clipboard,
            else => return,
        };
    }

    fn displayCopyOnSelectInCombo(self: *SettingsWindow) void {
        const combo = self.combo_copy_on_select orelse return;
        const p = self.pending orelse return;
        const idx: usize = switch (p.@"copy-on-select") {
            .false => 0,
            .true => 1,
            .clipboard => 2,
        };
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncClipboardAccessFromCombo(self: *SettingsWindow, comptime field_name: []const u8, combo_opt: ?HWND) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = combo_opt orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        @field(p.*, field_name) = clipboardAccessFromComboIndex(idx) orelse return;
    }

    fn displayClipboardAccessInCombo(self: *SettingsWindow, comptime field_name: []const u8, combo_opt: ?HWND) void {
        const combo = combo_opt orelse return;
        const p = self.pending orelse return;
        const idx = comboIndexFromClipboardAccess(@field(p, field_name));
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncLinkUrlFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_link_url orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"link-url" = linkUrlFromComboIndex(idx) orelse return;
    }

    fn displayLinkUrlInCombo(self: *SettingsWindow) void {
        const combo = self.combo_link_url orelse return;
        const p = self.pending orelse return;
        const idx = comboIndexFromLinkUrl(p.@"link-url");
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncLinkPreviewsFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_link_previews orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"link-previews" = linkPreviewsFromComboIndex(idx) orelse return;
    }

    fn displayLinkPreviewsInCombo(self: *SettingsWindow) void {
        const combo = self.combo_link_previews orelse return;
        const p = self.pending orelse return;
        const idx = comboIndexFromLinkPreviews(p.@"link-previews");
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncWindowThemeFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_window_theme orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"window-theme" = switch (idx) {
            0 => .auto,
            1 => .system,
            2 => .light,
            3 => .dark,
            4 => .ghostty,
            else => return,
        };
    }

    fn displayWindowThemeInCombo(self: *SettingsWindow) void {
        const combo = self.combo_window_theme orelse return;
        const p = self.pending orelse return;
        const idx: usize = switch (p.@"window-theme") {
            .auto => 0,
            .system => 1,
            .light => 2,
            .dark => 3,
            .ghostty => 4,
        };
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncShellIntegFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_shell_integ orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"shell-integration" = switch (idx) {
            0 => .none,
            1 => .detect,
            2 => .bash,
            3 => .elvish,
            4 => .fish,
            5 => .nushell,
            6 => .zsh,
            else => return,
        };
    }

    fn displayShellIntegInCombo(self: *SettingsWindow) void {
        const combo = self.combo_shell_integ orelse return;
        const p = self.pending orelse return;
        const idx: usize = switch (p.@"shell-integration") {
            .none => 0,
            .detect => 1,
            .bash => 2,
            .elvish => 3,
            .fish => 4,
            .nushell => 5,
            .zsh => 6,
        };
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncCursorStyleFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_cursor_style orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"cursor-style" = switch (idx) {
            0 => .bar,
            1 => .block,
            2 => .underline,
            3 => .block_hollow,
            else => return,
        };
    }

    fn displayCursorStyleInCombo(self: *SettingsWindow) void {
        const combo = self.combo_cursor_style orelse return;
        const p = self.pending orelse return;
        const idx: usize = switch (p.@"cursor-style") {
            .bar => 0,
            .block => 1,
            .underline => 2,
            .block_hollow => 3,
        };
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    /// background-blur is a union (false / true / { radius: u8 }). The
    /// GUI exposes only the boolean path, so keep an existing numeric
    /// radius intact while the checkbox remains enabled.
    fn pendingDigestMinutes(self: *SettingsWindow) u64 {
        const p = self.pending orelse return 0;
        return p.@"digest-after-away-minutes";
    }
    fn pendingTokenBudget(self: *SettingsWindow) u64 {
        const p = self.pending orelse return 0;
        return p.@"token-budget-alert";
    }
    fn pendingAutoRestart(self: *SettingsWindow) u64 {
        const p = self.pending orelse return 0;
        return p.@"pane-auto-restart";
    }
    fn pendingWsLayout(self: *SettingsWindow) u64 {
        const p = self.pending orelse return 0;
        return p.@"new-workspace-layout";
    }

    /// Rail search: activate the first section matching the query.
    fn jumpToSearchedSection(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const edit = self.edit_settings_search orelse return;
        const was_missed = self.settings_search_missed;
        defer if (self.settings_search_missed != was_missed) {
            _ = InvalidateRect(edit, null, 1);
        };
        var buf_w: [64]u16 = undefined;
        const n = GetWindowTextW(edit, &buf_w, @intCast(buf_w.len));
        if (n <= 0) {
            self.settings_search_missed = false;
            return;
        }
        var utf8_buf: [128]u8 = undefined;
        const len = std.unicode.utf16LeToUtf8(&utf8_buf, buf_w[0..@intCast(n)]) catch return;
        const trimmed = std.mem.trim(u8, utf8_buf[0..len], " ");
        if (trimmed.len == 0) {
            self.settings_search_missed = false;
            return;
        }
        const section = sectionMatchingQuery(trimmed) orelse {
            self.settings_search_missed = true;
            return;
        };
        self.settings_search_missed = false;
        if (self.active_section != section) self.setActiveSection(section);
    }

    fn syncAgentNumberFromEdit(self: *SettingsWindow, edit_opt: ?HWND, comptime field: []const u8, comptime T: type) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const edit = edit_opt orelse return;
        var buf_w: [32]u16 = undefined;
        const n = GetWindowTextW(edit, &buf_w, @intCast(buf_w.len));
        var utf8_buf: [64]u8 = undefined;
        const len = if (n > 0) (std.unicode.utf16LeToUtf8(&utf8_buf, buf_w[0..@intCast(n)]) catch return) else 0;
        const trimmed = std.mem.trim(u8, utf8_buf[0..len], " \t");
        const parsed = if (trimmed.len == 0) 0 else std.fmt.parseInt(T, trimmed, 10) catch return;
        @field(p.*, field) = parsed;
    }

    fn displayAgentNumberInEdit(self: *SettingsWindow, edit_opt: ?HWND, value: u64) void {
        const edit = edit_opt orelse return;
        var buf: [32]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{d}", .{value}) catch return;
        var buf_w: [32]u16 = undefined;
        const w = utf8ToW(&buf_w, text);
        self.suppress_edit_events = true;
        _ = SendMessageW(edit, WM_SETTEXT, 0, @bitCast(@intFromPtr(w)));
        self.suppress_edit_events = false;
    }

    fn syncAlertKeywordsFromEdit(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const arena = p.*._arena.?.allocator();
        const edit = self.edit_alert_keywords orelse return;
        var text_buf: [edit_text_max_utf8]u8 = undefined;
        const text = readEditUtf8(edit, &text_buf) orelse return;
        p.*.@"attention-alert-keywords" = arena.dupeZ(u8, std.mem.trim(u8, text, " \t")) catch return;
    }

    fn displayAlertKeywordsInEdit(self: *SettingsWindow) void {
        const edit = self.edit_alert_keywords orelse return;
        const p = self.pending orelse return;
        var buf_w: [512]u16 = undefined;
        const value = p.@"attention-alert-keywords";
        const n = std.unicode.utf8ToUtf16Le(buf_w[0 .. buf_w.len - 1], value) catch return;
        buf_w[n] = 0;
        self.suppress_edit_events = true;
        _ = SendMessageW(edit, WM_SETTEXT, 0, @bitCast(@intFromPtr(@as([*:0]const u16, @ptrCast(&buf_w)))));
        self.suppress_edit_events = false;
    }

    fn syncFocusFollowsFromCheckbox(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const chk = self.chk_focus_follows orelse return;
        p.*.@"focus-follows-attention" = SendMessageW(chk, BM_GETCHECK, 0, 0) == BST_CHECKED;
    }

    fn displayFocusFollowsInCheckbox(self: *SettingsWindow) void {
        const chk = self.chk_focus_follows orelse return;
        const p = self.pending orelse return;
        self.suppress_edit_events = true;
        _ = SendMessageW(chk, BM_SETCHECK, if (p.@"focus-follows-attention") BST_CHECKED else BST_UNCHECKED, 0);
        self.suppress_edit_events = false;
    }

    fn syncBgBlurFromCheckbox(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const chk = self.chk_bg_blur orelse return;
        const state = SendMessageW(chk, BM_GETCHECK, 0, 0);
        p.*.@"background-blur" = backgroundBlurFromCheckbox(
            p.*.@"background-blur",
            state == BST_CHECKED,
        );
    }

    fn displayBgBlurInCheckbox(self: *SettingsWindow) void {
        const chk = self.chk_bg_blur orelse return;
        const p = self.pending orelse return;
        const enabled = p.@"background-blur".win32SystemBackdropEnabled();
        self.suppress_edit_events = true;
        _ = SendMessageW(
            chk,
            BM_SETCHECK,
            if (enabled) BST_CHECKED else BST_UNCHECKED,
            0,
        );
        self.suppress_edit_events = false;
    }

    fn syncPadBalanceFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_pad_balance orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"window-padding-balance" = switch (idx) {
            0 => .false,
            1 => .true,
            2 => .equal,
            else => return,
        };
    }

    fn displayPadBalanceInCombo(self: *SettingsWindow) void {
        const combo = self.combo_pad_balance orelse return;
        const p = self.pending orelse return;
        const idx: usize = switch (p.@"window-padding-balance") {
            .false => 0,
            .true => 1,
            .equal => 2,
        };
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncAutoUpdateFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_auto_update orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"auto-update" = switch (idx) {
            0 => null,
            1 => .off,
            2 => .check,
            3 => .download,
            else => return,
        };
    }

    fn displayAutoUpdateInCombo(self: *SettingsWindow) void {
        const combo = self.combo_auto_update orelse return;
        const p = self.pending orelse return;
        const idx: usize = if (p.@"auto-update") |value| switch (value) {
            .off => 1,
            .check => 2,
            .download => 3,
        } else 0;
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    fn syncAutoUpdateChannelFromCombo(self: *SettingsWindow) void {
        if (self.suppress_edit_events) return;
        const p = &(self.pending orelse return);
        const combo = self.combo_auto_update_channel orelse return;
        const idx = SendMessageW(combo, CB_GETCURSEL, 0, 0);
        if (idx < 0) return;
        p.*.@"auto-update-channel" = switch (idx) {
            0 => null,
            1 => .stable,
            2 => .tip,
            else => return,
        };
    }

    fn displayAutoUpdateChannelInCombo(self: *SettingsWindow) void {
        const combo = self.combo_auto_update_channel orelse return;
        const p = self.pending orelse return;
        const idx: usize = if (p.@"auto-update-channel") |value| switch (value) {
            .stable => 1,
            .tip => 2,
        } else 0;
        self.suppress_edit_events = true;
        _ = SendMessageW(combo, CB_SETCURSEL, idx, 0);
        self.suppress_edit_events = false;
    }

    /// Refresh every control from the pending draft. Called after
    /// `adoptCurrentConfig` and after a successful save.
    fn refreshAllControls(self: *SettingsWindow) void {
        self.displayScrollbackInEdit();
        self.displayAgentNumberInEdit(self.edit_digest_min, self.pendingDigestMinutes());
        self.displayAlertKeywordsInEdit();
        self.displayAgentNumberInEdit(self.edit_token_budget, self.pendingTokenBudget());
        self.displayAgentNumberInEdit(self.edit_auto_restart, self.pendingAutoRestart());
        self.displayAgentNumberInEdit(self.edit_ws_layout, self.pendingWsLayout());
        self.displayFocusFollowsInCheckbox();
        self.displayFontFamilyInEdit();
        self.displayFontSizeInEdit();
        self.displayThemeInEdit();
        self.displayBgOpacityInEdit();
        self.displayCommandInEdit();
        self.displayPaddingInEdit(.x);
        self.displayPaddingInEdit(.y);
        self.displayTrimTrailInCheckbox();
        self.displayDesktopNotificationsInCheckbox();
        self.displayAppNotificationsInCheckbox(.clipboard);
        self.displayAppNotificationsInCheckbox(.config);
        self.displayConfirmCloseInCombo();
        self.displayCopyOnSelectInCombo();
        self.displayClipboardAccessInCombo("clipboard-read", self.combo_clipboard_read);
        self.displayClipboardAccessInCombo("clipboard-write", self.combo_clipboard_write);
        self.displayLinkUrlInCombo();
        self.displayLinkPreviewsInCombo();
        self.displayWindowThemeInCombo();
        self.displayShellIntegInCombo();
        self.displayCursorStyleInCombo();
        self.displayBgBlurInCheckbox();
        self.displayPadBalanceInCombo();
        self.displayAutoUpdateInCombo();
        self.displayAutoUpdateChannelInCombo();
        self.displayExplorerMenuCheckbox();
        self.rebuildThemeList();
    }

    fn save(self: *SettingsWindow) void {
        // Flush kill-focus-synced edits that may not have lost focus yet.
        self.syncCommandFromEdit();
        self.syncThemeFromEdit();
        self.syncFontFamilyFromEdit();
        const p = self.pending orelse return;
        const o = self.original orelse return;
        const result = self.handle.saveAndReload(self.handle.ctx, &p, &o);
        if (result) |_| {
            // Success path: refresh baseline so subsequent edits
            // diff correctly against the new saved state.
            self.clearPending();
            self.adoptCurrentConfig();
            self.refreshAllControls();
            self.handle.notifySuccess(self.handle.ctx, "Settings saved", "");
        } else |err| switch (err) {
            error.SavedButMasked => {
                // Persisted bytes are correct but a later config
                // layer is masking one or more edits. Same baseline
                // refresh as success since the file IS written.
                // The toast copy tells the user the bytes made it
                // to disk but the effective value differs.
                self.clearPending();
                self.adoptCurrentConfig();
                self.refreshAllControls();
                self.handle.notifySuccess(
                    self.handle.ctx,
                    "Settings saved — some values are masked by a later config-file layer",
                    "Check the log for which fields.",
                );
            },
            else => {
                // Write failed. DO NOT discard `pending` — the user's
                // edits are still in memory; losing them on every
                // transient disk error (permission denied, sharing
                // violation when another editor has the file open)
                // would be destructive. Leave `pending` alone so
                // the user can retry Save once the underlying issue
                // is fixed, or close the window to discard.
                std.log.warn("settings: save failed err={}; draft preserved", .{err});
            },
        }
    }

    fn adoptCurrentConfig(self: *SettingsWindow) void {
        const current = self.handle.currentConfig(self.handle.ctx);
        // Two independent shallow clones so each struct has its own
        // arena. The `original` clone is a frozen baseline for the
        // save-path diff; the `pending` clone is the editable draft.
        // Mutations to `pending` go through its arena; `original`
        // stays byte-identical to the config at window-open time
        // even if `App.config` mutates via an external reload.
        self.original = current.shallowClone(self.handle.alloc);
        self.pending = current.shallowClone(self.handle.alloc);
    }

    /// Bring the settings window up. Idempotent: a subsequent open
    /// with a live HWND brings the existing window to the foreground
    /// instead of duplicating it.
    pub fn open(self: *SettingsWindow) !void {
        @setEvalBranchQuota(20_000);
        if (self.hwnd) |h| {
            if (IsWindow(h) != 0) {
                if (IsIconic(h) != 0) _ = ShowWindow(h, SW_RESTORE) else _ = ShowWindow(h, SW_SHOWNORMAL);
                _ = SetForegroundWindow(h);
                return;
            }
            self.hwnd = null;
        }

        // Fresh pending clone of the live config. Discarded on close
        // or refreshed after a successful save.
        self.clearPending();
        self.adoptCurrentConfig();

        if (self.class_atom == 0) {
            const wc: WNDCLASSEXW = .{
                .cbSize = @sizeOf(WNDCLASSEXW),
                .style = CS_HREDRAW | CS_VREDRAW,
                .lpfnWndProc = &wndProc,
                .cbClsExtra = 0,
                .cbWndExtra = 0,
                .hInstance = self.handle.hinstance,
                .hIcon = null,
                .hCursor = LoadCursorW(null, @ptrFromInt(IDC_ARROW)),
                .hbrBackground = null,
                .lpszMenuName = null,
                .lpszClassName = class_name,
                .hIconSm = null,
            };
            self.class_atom = RegisterClassExW(&wc);
            if (self.class_atom == 0) {
                return windows.unexpectedError(windows.kernel32.GetLastError());
            }
        }

        const title = std.unicode.utf8ToUtf16LeStringLiteral("paramux settings");
        const hwnd = CreateWindowExW(
            WS_EX_APPWINDOW,
            class_name,
            title,
            WS_OVERLAPPEDWINDOW & ~WS_MAXIMIZEBOX,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            1000,
            760,
            null,
            null,
            self.handle.hinstance,
            self,
        ) orelse return windows.unexpectedError(windows.kernel32.GetLastError());
        self.hwnd = hwnd;

        // Match the app's DWM decoration (dark titlebar + caption colors)
        // and build the UI font set before any control paints.
        self.handle.decorateWindow(self.handle.ctx, hwnd);
        self.font_title = makeUiFont(26, FW_SEMIBOLD);
        self.font_body = makeUiFont(16, FW_NORMAL);
        self.font_label = makeUiFont(14, FW_NORMAL);

        const btn_class = std.unicode.utf8ToUtf16LeStringLiteral("BUTTON");

        // Left-rail section buttons. Clicks arrive via WM_COMMAND on
        // the parent; the id maps back to a `Section` via
        // `Section.fromButtonId`.
        self.btn_section_appearance = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.appearance);
        self.btn_section_theme = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.theme);
        self.btn_section_terminal = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.terminal);
        self.btn_section_shell = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.shell);
        self.btn_section_keybindings = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.keybindings);
        self.btn_section_windows = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.windows);
        self.btn_section_agents = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.agents);
        self.btn_section_advanced = makeSectionButton(hwnd, self.handle.hinstance, btn_class, Section.advanced);

        // "Open in default editor" button — escape hatch for users
        // who prefer text-editing the config file directly. Lives
        // in the Advanced section; hidden when another section is
        // active.
        const btn_label = std.unicode.utf8ToUtf16LeStringLiteral("Open in default editor");
        self.btn_open_editor = CreateWindowExW(
            0,
            btn_class,
            btn_label,
            WS_CHILD | WS_TABSTOP | BS_OWNERDRAW,
            0,
            0,
            220,
            32,
            hwnd,
            @ptrFromInt(BTN_OPEN_EDITOR),
            self.handle.hinstance,
            null,
        );
        // "Save" button — always visible; writes `pending` to disk
        // and fires a hard reload. Save errors are logged and the draft
        // remains in memory for retry.
        const btn_save_label = std.unicode.utf8ToUtf16LeStringLiteral("Save");
        self.btn_save = CreateWindowExW(
            0,
            btn_class,
            btn_save_label,
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
            0,
            0,
            90,
            32,
            hwnd,
            @ptrFromInt(BTN_SAVE),
            self.handle.hinstance,
            null,
        );

        const btn_keybind_label = std.unicode.utf8ToUtf16LeStringLiteral("Open config for keybinds");
        self.btn_keybindings_editor = CreateWindowExW(
            0,
            btn_class,
            btn_keybind_label,
            WS_CHILD | WS_TABSTOP | BS_OWNERDRAW,
            0,
            0,
            220,
            32,
            hwnd,
            @ptrFromInt(BTN_KEYBINDINGS_EDITOR),
            self.handle.hinstance,
            null,
        );

        // Scrollback limit EDIT. Lives in the Terminal section. Digit-
        // only input via ES_NUMBER; EN_CHANGE syncs into `pending`.
        self.edit_scrollback = makeEdit(hwnd, self.handle.hinstance, EDIT_SCROLLBACK, 200, ES_NUMBER);

        // font-family EDIT. Comma-separated fallback families.
        self.edit_font_family = makeEdit(hwnd, self.handle.hinstance, EDIT_FONT_FAMILY, 300, 0);

        // font-size EDIT. Appearance section. We accept floats via a
        // plain EDIT (not ES_NUMBER — which rejects '.') and validate
        // on EN_CHANGE.
        self.edit_font_size = makeEdit(hwnd, self.handle.hinstance, EDIT_FONT_SIZE, 160, 0);

        // theme EDIT. Accepts a built-in/custom name or light/dark pair.
        self.edit_theme = makeEdit(hwnd, self.handle.hinstance, EDIT_THEME, 300, 0);

        // Theme picker (Theme section): search box + owner-draw list with
        // per-theme color swatches.
        self.edit_theme_search = makeEdit(hwnd, self.handle.hinstance, EDIT_THEME_SEARCH, 420, 0);
        if (self.edit_theme_search) |search| {
            const cue = std.unicode.utf8ToUtf16LeStringLiteral("Search themes...");
            _ = SendMessageW(search, EM_SETCUEBANNER, 1, @bitCast(@intFromPtr(cue)));
        }
        const listbox_class = std.unicode.utf8ToUtf16LeStringLiteral("LISTBOX");
        self.list_themes = CreateWindowExW(
            0,
            listbox_class,
            std.unicode.utf8ToUtf16LeStringLiteral(""),
            WS_CHILD | WS_TABSTOP | WS_VSCROLL | WS_BORDER | LBS_NOTIFY | LBS_OWNERDRAWFIXED | LBS_HASSTRINGS,
            0,
            0,
            420,
            400,
            hwnd,
            @ptrFromInt(LIST_THEMES),
            self.handle.hinstance,
            null,
        );
        if (self.list_themes) |list| {
            _ = SendMessageW(list, LB_SETITEMHEIGHT, 0, theme_list_item_height);
        }

        // Windows-integration section: Explorer context-menu toggle.
        self.chk_explorer_menu = makeCheckbox(
            hwnd,
            self.handle.hinstance,
            CHK_EXPLORER_MENU,
            std.unicode.utf8ToUtf16LeStringLiteral("Add \"Open in Paramux\" to the Explorer right-click menu"),
            420,
        );

        // background-opacity EDIT. Appearance section. 0.0..1.0.
        self.edit_bg_opacity = makeEdit(hwnd, self.handle.hinstance, EDIT_BG_OPACITY, 160, 0);

        self.edit_command = makeEdit(hwnd, self.handle.hinstance, EDIT_COMMAND, 360, 0);

        self.edit_pad_x = makeEdit(hwnd, self.handle.hinstance, EDIT_PAD_X, 160, 0);

        self.edit_pad_y = makeEdit(hwnd, self.handle.hinstance, EDIT_PAD_Y, 160, 0);

        // clipboard-trim-trailing-spaces checkbox. Terminal section.
        self.chk_trim_trail = makeCheckbox(
            hwnd,
            self.handle.hinstance,
            CHK_TRIM_TRAIL,
            std.unicode.utf8ToUtf16LeStringLiteral("Trim trailing spaces on copy"),
            260,
        );

        self.chk_desktop_notifications = makeCheckbox(
            hwnd,
            self.handle.hinstance,
            CHK_DESKTOP_NOTIFICATIONS,
            std.unicode.utf8ToUtf16LeStringLiteral("Allow terminal desktop notifications"),
            320,
        );

        self.chk_app_notify_clipboard = makeCheckbox(
            hwnd,
            self.handle.hinstance,
            CHK_APP_NOTIFY_CLIPBOARD,
            std.unicode.utf8ToUtf16LeStringLiteral("Notify when clipboard copy completes"),
            320,
        );

        self.chk_app_notify_config = makeCheckbox(
            hwnd,
            self.handle.hinstance,
            CHK_APP_NOTIFY_CONFIG,
            std.unicode.utf8ToUtf16LeStringLiteral("Notify after config reload"),
            320,
        );

        // Comboboxes for enum fields.
        self.combo_confirm_close = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_CONFIRM_CLOSE,
            160,
            &.{ "false", "true", "always" },
        );

        self.combo_copy_on_select = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_COPY_ON_SELECT,
            160,
            &.{ "false", "true", "clipboard" },
        );

        self.combo_clipboard_read = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_CLIPBOARD_READ,
            160,
            &.{ "ask", "allow", "deny" },
        );

        self.combo_clipboard_write = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_CLIPBOARD_WRITE,
            160,
            &.{ "ask", "allow", "deny" },
        );

        self.combo_link_url = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_LINK_URL,
            160,
            &.{ "enabled", "disabled" },
        );

        self.combo_link_previews = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_LINK_PREVIEWS,
            160,
            &.{ "all links", "OSC 8 only", "disabled" },
        );

        self.combo_window_theme = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_WINDOW_THEME,
            180,
            &.{ "auto", "system", "light", "dark", "ghostty" },
        );

        self.combo_shell_integ = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_SHELL_INTEG,
            200,
            &.{ "none", "detect", "bash", "elvish", "fish", "nushell", "zsh" },
        );

        self.combo_cursor_style = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_CURSOR_STYLE,
            160,
            &.{ "bar", "block", "underline", "block_hollow" },
        );

        self.edit_settings_search = makeEdit(hwnd, self.handle.hinstance, EDIT_SETTINGS_SEARCH, 160, 0);
        if (self.edit_settings_search) |search| {
            const cue = std.unicode.utf8ToUtf16LeStringLiteral("Search settings...");
            _ = SendMessageW(search, EM_SETCUEBANNER, 1, @bitCast(@intFromPtr(cue)));
        }
        self.edit_digest_min = makeEdit(hwnd, self.handle.hinstance, EDIT_DIGEST_MIN, 120, ES_NUMBER);
        self.edit_alert_keywords = makeEdit(hwnd, self.handle.hinstance, EDIT_ALERT_KEYWORDS, 320, 0);
        self.edit_token_budget = makeEdit(hwnd, self.handle.hinstance, EDIT_TOKEN_BUDGET, 140, ES_NUMBER);
        self.edit_auto_restart = makeEdit(hwnd, self.handle.hinstance, EDIT_AUTO_RESTART, 120, ES_NUMBER);
        self.edit_ws_layout = makeEdit(hwnd, self.handle.hinstance, EDIT_WS_LAYOUT, 120, ES_NUMBER);
        self.chk_focus_follows = makeCheckbox(
            hwnd,
            self.handle.hinstance,
            CHK_FOCUS_FOLLOWS,
            std.unicode.utf8ToUtf16LeStringLiteral("Focus follows attention (only when idle 10s+)"),
            320,
        );
        self.chk_bg_blur = makeCheckbox(
            hwnd,
            self.handle.hinstance,
            CHK_BG_BLUR,
            std.unicode.utf8ToUtf16LeStringLiteral("Enable background blur"),
            260,
        );

        self.combo_pad_balance = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_PAD_BALANCE,
            160,
            &.{ "false", "true", "equal" },
        );

        self.combo_auto_update = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_AUTO_UPDATE,
            160,
            &.{ "default", "off", "check", "download" },
        );

        self.combo_auto_update_channel = makeCombo(
            hwnd,
            self.handle.hinstance,
            COMBO_AUTO_UPDATE_CHANNEL,
            140,
            &.{ "default", "stable", "tip" },
        );

        // Every control exists now: apply the shared UI font and the
        // system dark-mode control themes in one pass.
        self.themeChildControls();

        self.refreshAllControls();

        self.applySectionVisibility();

        _ = ShowWindow(hwnd, SW_SHOWNORMAL);
        layoutChildren(self);
    }

    /// Apply `font_body` and (when the chrome theme is dark) the system
    /// "DarkMode" visual styles to every child control by class. One
    /// EnumChildWindows pass so future controls are covered automatically.
    fn themeChildControls(self: *SettingsWindow) void {
        const hwnd = self.hwnd orelse return;
        const ctx = ThemeChildCtx{
            .font = self.font_body,
            .dark = self.handle.uiColors(self.handle.ctx).is_dark,
        };
        _ = EnumChildWindows(hwnd, &themeChildProc, @bitCast(@intFromPtr(&ctx)));
    }

    const ThemeChildCtx = struct {
        font: HGDIOBJ,
        dark: bool,
    };

    fn themeChildProc(child: HWND, lparam: LPARAM) callconv(.winapi) BOOL {
        const ctx: *const ThemeChildCtx = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (ctx.font) |font| {
            _ = SendMessageW(child, WM_SETFONT, @intFromPtr(font), 1);
        }
        if (ctx.dark) {
            var class_buf: [64]u16 = undefined;
            const n = GetClassNameW(child, &class_buf, class_buf.len);
            const class = class_buf[0..@intCast(@max(0, n))];
            const combo = std.unicode.utf8ToUtf16LeStringLiteral("ComboBox");
            const theme_name = if (std.mem.eql(u16, class, combo))
                std.unicode.utf8ToUtf16LeStringLiteral("DarkMode_CFD")
            else
                std.unicode.utf8ToUtf16LeStringLiteral("DarkMode_Explorer");
            _ = SetWindowTheme(child, theme_name, null);
        }
        return 1;
    }
};

fn populateCombo(combo_opt: ?HWND, items: []const []const u8) void {
    const combo = combo_opt orelse return;
    _ = SendMessageW(combo, CB_RESETCONTENT, 0, 0);
    for (items) |item| {
        var buf_w: [64]u16 = undefined;
        const w = utf8ToW(&buf_w, item);
        _ = SendMessageW(combo, CB_ADDSTRING, 0, @bitCast(@intFromPtr(w)));
    }
}

fn makeEdit(
    parent: HWND,
    hinstance: HINSTANCE,
    id: usize,
    width: i32,
    extra_style: u32,
) ?HWND {
    const edit_class = std.unicode.utf8ToUtf16LeStringLiteral("EDIT");
    const edit = CreateWindowExW(
        0,
        edit_class,
        std.unicode.utf8ToUtf16LeStringLiteral(""),
        WS_CHILD | WS_TABSTOP | ES_AUTOHSCROLL | extra_style,
        0,
        0,
        width,
        28,
        parent,
        @ptrFromInt(id),
        hinstance,
        null,
    );
    if (edit) |e| _ = SendMessageW(e, EM_LIMITTEXT, edit_text_max_code_units - 1, 0);
    return edit;
}

fn makeCheckbox(
    parent: HWND,
    hinstance: HINSTANCE,
    id: usize,
    label: LPCWSTR,
    width: i32,
) ?HWND {
    const btn_class = std.unicode.utf8ToUtf16LeStringLiteral("BUTTON");
    return CreateWindowExW(
        0,
        btn_class,
        label,
        WS_CHILD | WS_TABSTOP | BS_AUTOCHECKBOX,
        0,
        0,
        width,
        24,
        parent,
        @ptrFromInt(id),
        hinstance,
        null,
    );
}

fn makeCombo(
    parent: HWND,
    hinstance: HINSTANCE,
    id: usize,
    height: i32,
    items: []const []const u8,
) ?HWND {
    const combo_class = std.unicode.utf8ToUtf16LeStringLiteral("COMBOBOX");
    const combo = CreateWindowExW(
        0,
        combo_class,
        std.unicode.utf8ToUtf16LeStringLiteral(""),
        WS_CHILD | WS_TABSTOP | CBS_DROPDOWNLIST | CBS_HASSTRINGS,
        0,
        0,
        200,
        height,
        parent,
        @ptrFromInt(id),
        hinstance,
        null,
    );
    populateCombo(combo, items);
    return combo;
}

fn makeSectionButton(
    parent: HWND,
    hinstance: HINSTANCE,
    class: LPCWSTR,
    section: Section,
) ?HWND {
    const id: usize = switch (section) {
        .appearance => BTN_SECTION_APPEARANCE,
        .theme => BTN_SECTION_THEME,
        .terminal => BTN_SECTION_TERMINAL,
        .shell => BTN_SECTION_SHELL,
        .keybindings => BTN_SECTION_KEYBINDINGS,
        .windows => BTN_SECTION_WINDOWS,
        .agents => BTN_SECTION_AGENTS,
        .advanced => BTN_SECTION_ADVANCED,
    };
    return CreateWindowExW(
        0,
        class,
        section.label(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
        0,
        0,
        100,
        36,
        parent,
        @ptrFromInt(id),
        hinstance,
        null,
    );
}

const left_rail_width: i32 = 200;
const section_btn_height: i32 = 36;
const section_btn_top_pad: i32 = 16;
const section_btn_gap: i32 = 4;
const side_pad: i32 = 16;

// Content-pane header block: title, one-line summary, separator.
const header_title_h: i32 = 34;
const header_summary_h: i32 = 20;
const header_sep_gap: i32 = 8;
const header_below_gap: i32 = 17;

fn contentTop() i32 {
    return section_btn_top_pad + header_title_h + header_summary_h +
        header_sep_gap + 1 + header_below_gap;
}

// Field grid. One `SectionRow` per control, in the exact order
// `sectionGridControls` returns handles; `layoutChildren` and `paint`
// both walk the same table through the same cursor, so control
// positions and painted labels can't drift apart.
const grid_label_reserve: i32 = 22;
const grid_row_gap: i32 = 18;
const grid_col_gap: i32 = 28;
const grid_controls_max: usize = 12;

const SectionRow = struct {
    /// Painted above the control; empty for controls that carry
    /// their own text (checkboxes, buttons with captions).
    label: []const u8 = "",
    /// Desired control width; clamped to the column width.
    w: i32 = 280,
    /// Visible control height used for vertical flow.
    h: i32 = 30,
    /// Extra dropdown height (combos) added to the window height
    /// at layout time but not to the flow.
    drop_h: i32 = 0,
    /// Full-width row spanning both columns.
    span: bool = false,
};

const terminal_rows = [_]SectionRow{
    .{ .label = "Scrollback limit (rows, 0 = unlimited)", .w = 220, .h = 28 },
    .{ .label = "Close confirmation", .w = 220, .drop_h = 160 },
    .{ .label = "Copy on select", .w = 220, .drop_h = 160 },
    .{ .label = "Clipboard read (OSC 52)", .w = 220, .drop_h = 160 },
    .{ .label = "Clipboard write (OSC 52)", .w = 220, .drop_h = 160 },
    .{ .label = "Clickable URLs", .w = 220, .drop_h = 160 },
    .{ .label = "Link previews", .w = 220, .drop_h = 160 },
    .{ .w = 300, .h = 24 },
    .{ .w = 340, .h = 24 },
    .{ .w = 340, .h = 24 },
    .{ .w = 340, .h = 24 },
};

const appearance_rows = [_]SectionRow{
    .{ .label = "Font family fallbacks (comma-separated)", .w = 340, .h = 28 },
    .{ .label = "Font size (pt)", .w = 160, .h = 28 },
    .{ .label = "Theme (name, path, or light:X,dark:Y)", .w = 340, .h = 28 },
    .{ .label = "Background opacity (0.0 – 1.0)", .w = 160, .h = 28 },
    .{ .label = "Window theme", .w = 220, .drop_h = 180 },
    .{ .label = "Cursor style", .w = 220, .drop_h = 160 },
    .{ .label = "Window padding X (px)", .w = 160, .h = 28 },
    .{ .label = "Window padding Y (px)", .w = 160, .h = 28 },
    .{ .label = "Padding balance", .w = 220, .drop_h = 160 },
    .{ .w = 300, .h = 24 },
};

const shell_rows = [_]SectionRow{
    .{ .label = "Default command (blank = auto-detect)", .h = 28, .span = true },
    .{ .label = "Shell integration", .w = 220, .drop_h = 200 },
};

const agents_rows = [_]SectionRow{
    .{ .label = "Away digest after (minutes, 0 = off)", .w = 120 },
    .{ .label = "Urgent alert keywords (comma-separated)", .w = 320, .span = true },
    .{ .label = "Token budget alert (tokens, 0 = off)", .w = 140 },
    .{ .label = "Auto-restart crashed panes (max, 0 = off)", .w = 120 },
    .{ .label = "New-workspace layout slot (0 = two columns)", .w = 120 },
    .{ .w = 320, .h = 24 },
};

const advanced_rows = [_]SectionRow{
    .{ .label = "Auto-update mode", .w = 220, .drop_h = 160 },
    .{ .label = "Auto-update channel", .w = 220, .drop_h = 140 },
    .{ .label = "Full config editor", .w = 220, .h = 32 },
};

/// Keywords per section for the rail search box; first section whose
/// name or keywords contain the query becomes active.
/// Mix a COLORREF (0x00BBGGRR) toward an RGB target by `pct` percent.
fn blendTowardRgb(base: u32, r: u32, g: u32, b: u32, pct: u32) u32 {
    const base_r = base & 0xFF;
    const base_g = (base >> 8) & 0xFF;
    const base_b = (base >> 16) & 0xFF;
    const out_r = (base_r * (100 - pct) + r * pct) / 100;
    const out_g = (base_g * (100 - pct) + g * pct) / 100;
    const out_b = (base_b * (100 - pct) + b * pct) / 100;
    return out_r | (out_g << 8) | (out_b << 16);
}

fn sectionSearchBlob(section: Section) []const u8 {
    return switch (section) {
        .appearance => "appearance font family size ligatures theme opacity cursor style padding blur background",
        .theme => "theme colors swatch scheme dark light import url",
        .terminal => "terminal scrollback bell confirm close copy on select clipboard paste link notifications mouse",
        .shell => "shell command integration powershell cmd wsl elevated",
        .keybindings => "keybindings shortcuts chords keys leader tmux prefix",
        .windows => "windows explorer context menu integration jump list startup titlebar",
        .agents => "agents digest keywords token budget restart layout focus attention webhook broadcast quick terminal restore commands language",
        .advanced => "advanced update channel rollback editor diagnostics config file",
    };
}

fn sectionMatchingQuery(query: []const u8) ?Section {
    if (query.len == 0) return null;
    var lower_buf: [64]u8 = undefined;
    if (query.len > lower_buf.len) return null;
    const q = std.ascii.lowerString(&lower_buf, query);
    inline for (@typeInfo(Section).@"enum".fields) |field| {
        const section: Section = @enumFromInt(field.value);
        if (std.mem.indexOf(u8, sectionSearchBlob(section), q) != null) return section;
    }
    return null;
}

fn sectionGridRows(section: Section) []const SectionRow {
    return switch (section) {
        .terminal => &terminal_rows,
        .appearance => &appearance_rows,
        .shell => &shell_rows,
        .advanced => &advanced_rows,
        .agents => &agents_rows,
        else => &[_]SectionRow{},
    };
}

fn sectionGridControls(
    self: *SettingsWindow,
    section: Section,
    buf: *[grid_controls_max]?HWND,
) usize {
    switch (section) {
        .terminal => {
            const list = [_]?HWND{
                self.edit_scrollback,          self.combo_confirm_close,
                self.combo_copy_on_select,     self.combo_clipboard_read,
                self.combo_clipboard_write,    self.combo_link_url,
                self.combo_link_previews,      self.chk_trim_trail,
                self.chk_desktop_notifications, self.chk_app_notify_clipboard,
                self.chk_app_notify_config,
            };
            @memcpy(buf[0..list.len], &list);
            return list.len;
        },
        .appearance => {
            const list = [_]?HWND{
                self.edit_font_family, self.edit_font_size,
                self.edit_theme,       self.edit_bg_opacity,
                self.combo_window_theme, self.combo_cursor_style,
                self.edit_pad_x,       self.edit_pad_y,
                self.combo_pad_balance, self.chk_bg_blur,
            };
            @memcpy(buf[0..list.len], &list);
            return list.len;
        },
        .shell => {
            const list = [_]?HWND{ self.edit_command, self.combo_shell_integ };
            @memcpy(buf[0..list.len], &list);
            return list.len;
        },
        .agents => {
            const list = [_]?HWND{
                self.edit_digest_min,     self.edit_alert_keywords,
                self.edit_token_budget,   self.edit_auto_restart,
                self.edit_ws_layout,      self.chk_focus_follows,
            };
            @memcpy(buf[0..list.len], &list);
            return list.len;
        },
        .advanced => {
            const list = [_]?HWND{
                self.combo_auto_update,
                self.combo_auto_update_channel,
                self.btn_open_editor,
            };
            @memcpy(buf[0..list.len], &list);
            return list.len;
        },
        else => return 0,
    }
}

const RowPlacement = struct {
    control: RECT,
    label_y: i32,
    /// Right edge available for the painted label — the full column
    /// (or pane, for span rows), not just the control width.
    label_right: i32,
};

/// Two-column flow cursor. Every row reserves a label line so control
/// tops stay aligned across columns even when labels are empty.
const GridCursor = struct {
    left: i32,
    right: i32,
    y: i32,
    col: usize = 0,
    row_bottom: i32 = 0,

    fn init(client: RECT) GridCursor {
        return .{
            .left = left_rail_width + side_pad,
            .right = client.right - side_pad,
            .y = contentTop(),
        };
    }

    fn place(self: *GridCursor, row: SectionRow) RowPlacement {
        const cw = @divTrunc(self.right - self.left - grid_col_gap, 2);
        if (row.span and self.col == 1) self.wrap();
        const x = if (self.col == 0) self.left else self.left + cw + grid_col_gap;
        const w = if (row.span) self.right - self.left else @min(row.w, cw);
        const label_y = self.y;
        const control: RECT = .{
            .left = x,
            .top = self.y + grid_label_reserve,
            .right = x + w,
            .bottom = self.y + grid_label_reserve + row.h,
        };
        self.row_bottom = @max(self.row_bottom, control.bottom + grid_row_gap);
        if (row.span or self.col == 1) self.wrap() else self.col = 1;
        return .{
            .control = control,
            .label_y = label_y,
            .label_right = if (row.span) self.right else x + cw,
        };
    }

    fn wrap(self: *GridCursor) void {
        self.y = @max(self.y, self.row_bottom);
        self.row_bottom = self.y;
        self.col = 0;
    }
};

fn layoutChildren(self: *SettingsWindow) void {
    const hwnd = self.hwnd orelse return;
    var rect: RECT = undefined;
    if (GetClientRect(hwnd, &rect) == 0) return;

    // Left rail — stack section buttons top-down.
    const btn_x: i32 = side_pad;
    const btn_w: i32 = left_rail_width - side_pad - side_pad;
    var y: i32 = section_btn_top_pad;
    if (self.edit_settings_search) |search_edit| {
        _ = MoveWindow(search_edit, btn_x, y, btn_w, 26, 1);
        y += 26 + section_btn_gap * 2;
    }
    for ([_]?HWND{
        self.btn_section_appearance,
        self.btn_section_theme,
        self.btn_section_terminal,
        self.btn_section_shell,
        self.btn_section_keybindings,
        self.btn_section_windows,
        self.btn_section_agents,
        self.btn_section_advanced,
    }) |btn_opt| {
        if (btn_opt) |btn| {
            _ = MoveWindow(btn, btn_x, y, btn_w, section_btn_height, 1);
        }
        y += section_btn_height + section_btn_gap;
    }

    const pane_left = left_rail_width + side_pad;

    // Grid-driven sections. Each section is laid out independently
    // from the same origin; `applySectionVisibility` hides everything
    // but the active section's controls.
    for ([_]Section{ .terminal, .appearance, .shell, .advanced }) |sec| {
        const rows = sectionGridRows(sec);
        var buf: [grid_controls_max]?HWND = undefined;
        const n = sectionGridControls(self, sec, &buf);
        var cursor = GridCursor.init(rect);
        for (rows[0..@min(rows.len, n)], buf[0..@min(rows.len, n)]) |row, ctl_opt| {
            const p = cursor.place(row);
            if (ctl_opt) |ctl| _ = MoveWindow(
                ctl,
                p.control.left,
                p.control.top,
                p.control.right - p.control.left,
                (p.control.bottom - p.control.top) + row.drop_h,
                1,
            );
        }
    }

    // Theme section: search box on top, list fills the remaining height
    // above the Save-button strip.
    {
        var ty: i32 = contentTop();
        const picker_w: i32 = @max(320, @min(520, rect.right - pane_left - side_pad));
        if (self.edit_theme_search) |e| {
            _ = MoveWindow(e, pane_left, ty, picker_w, 28, 1);
            ty += 38;
        }
        if (self.list_themes) |e| {
            const list_h: i32 = @max(120, rect.bottom - ty - 72);
            _ = MoveWindow(e, pane_left, ty, picker_w, list_h, 1);
        }
    }

    // Windows-integration section.
    if (self.chk_explorer_menu) |e| {
        _ = MoveWindow(e, pane_left, contentTop(), 420, 24, 1);
    }

    // Keybindings section.
    if (self.btn_keybindings_editor) |btn| {
        _ = MoveWindow(btn, pane_left, contentTop(), 220, 32, 1);
    }

    // Save button — always-visible, bottom-right of window.
    if (self.btn_save) |btn| {
        const w: i32 = 110;
        const h: i32 = 34;
        _ = MoveWindow(
            btn,
            rect.right - w - side_pad,
            rect.bottom - h - side_pad,
            w,
            h,
            1,
        );
    }
}

extern "user32" fn MoveWindow(
    hWnd: HWND,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    bRepaint: BOOL,
) callconv(.winapi) BOOL;

fn wndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT {
    if (msg == WM_NCCREATE) {
        const cs: *const CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lParam)));
        if (cs.lpCreateParams) |ptr| {
            _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @intCast(@intFromPtr(ptr)));
        }
    }

    const owner = recoverOwner(hwnd);
    switch (msg) {
        WM_ERASEBKGND => return 1,
        WM_PAINT => {
            if (owner) |o| paint(hwnd, o);
            return 0;
        },
        // Theme the plain controls: dark (or light) field backgrounds and
        // readable text for edits, list boxes, and checkbox label strips.
        WM_CTLCOLOREDIT, WM_CTLCOLORLISTBOX => {
            if (owner) |o| {
                const colors = o.handle.uiColors(o.handle.ctx);
                const hdc: HDC = @ptrFromInt(wParam);
                var field_bg = colors.field_bg;
                // A missed rail search tints its box toward red so the
                // "no such section" state is visible in place.
                if (o.settings_search_missed and lParam != 0) {
                    const ctl: HWND = @ptrFromInt(@as(usize, @bitCast(lParam)));
                    if (o.edit_settings_search) |search_edit| {
                        if (ctl == search_edit)
                            field_bg = blendTowardRgb(colors.field_bg, 200, 60, 60, 35);
                    }
                }
                _ = SetTextColor(hdc, colors.text);
                _ = SetBkColor(hdc, field_bg);
                _ = SetDCBrushColor(hdc, field_bg);
                return @bitCast(@intFromPtr(GetStockObject(DC_BRUSH)));
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        WM_CTLCOLORSTATIC, WM_CTLCOLORBTN => {
            if (owner) |o| {
                const colors = o.handle.uiColors(o.handle.ctx);
                const hdc: HDC = @ptrFromInt(wParam);
                _ = SetTextColor(hdc, colors.text);
                _ = SetBkColor(hdc, colors.bg);
                _ = SetDCBrushColor(hdc, colors.bg);
                return @bitCast(@intFromPtr(GetStockObject(DC_BRUSH)));
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        WM_GETMINMAXINFO => {
            const info: *MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lParam)));
            info.ptMinTrackSize = .{ .x = 860, .y = 640 };
            return 0;
        },
        WM_DRAWITEM => {
            const dis: *const DRAWITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (dis.CtlType == ODT_LISTBOX and dis.CtlID == LIST_THEMES) {
                if (owner) |o| o.drawThemeListItem(dis);
                return 1;
            }
            if (dis.CtlType == ODT_BUTTON_CTL) {
                if (owner) |o| {
                    o.drawOwnerButton(dis);
                    return 1;
                }
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        WM_SIZE => {
            if (owner) |o| layoutChildren(o);
            return 0;
        },
        WM_COMMAND => {
            const id: usize = wParam & 0xFFFF;
            const notify: u16 = @intCast((wParam >> 16) & 0xFFFF);
            if (id == BTN_OPEN_EDITOR) {
                if (owner) |o| o.handle.openInEditor(o.handle.ctx);
                return 0;
            }
            if (id == BTN_KEYBINDINGS_EDITOR) {
                if (owner) |o| o.handle.openInEditor(o.handle.ctx);
                return 0;
            }
            if (id == BTN_SAVE) {
                if (owner) |o| o.save();
                return 0;
            }
            if (id == EDIT_SETTINGS_SEARCH and notify == EN_CHANGE) {
                if (owner) |o| o.jumpToSearchedSection();
                return 0;
            }
            if (id == EDIT_DIGEST_MIN and notify == EN_CHANGE) {
                if (owner) |o| o.syncAgentNumberFromEdit(o.edit_digest_min, "digest-after-away-minutes", u32);
                return 0;
            }
            if (id == EDIT_ALERT_KEYWORDS and notify == EN_CHANGE) {
                if (owner) |o| o.syncAlertKeywordsFromEdit();
                return 0;
            }
            if (id == EDIT_TOKEN_BUDGET and notify == EN_CHANGE) {
                if (owner) |o| o.syncAgentNumberFromEdit(o.edit_token_budget, "token-budget-alert", u64);
                return 0;
            }
            if (id == EDIT_AUTO_RESTART and notify == EN_CHANGE) {
                if (owner) |o| o.syncAgentNumberFromEdit(o.edit_auto_restart, "pane-auto-restart", u32);
                return 0;
            }
            if (id == EDIT_WS_LAYOUT and notify == EN_CHANGE) {
                if (owner) |o| o.syncAgentNumberFromEdit(o.edit_ws_layout, "new-workspace-layout", u32);
                return 0;
            }
            if (id == EDIT_SCROLLBACK and notify == EN_CHANGE) {
                if (owner) |o| o.syncScrollbackFromEdit();
                return 0;
            }
            // These parse into pending._arena; defer from EN_CHANGE to
            // EN_KILLFOCUS so we don't accumulate per-keystroke allocations.
            if (id == EDIT_FONT_FAMILY and notify == EN_KILLFOCUS) {
                if (owner) |o| o.syncFontFamilyFromEdit();
                return 0;
            }
            if (id == EDIT_FONT_SIZE and notify == EN_CHANGE) {
                if (owner) |o| o.syncFontSizeFromEdit();
                return 0;
            }
            if (id == EDIT_THEME and notify == EN_KILLFOCUS) {
                if (owner) |o| o.syncThemeFromEdit();
                return 0;
            }
            if (id == EDIT_THEME_SEARCH and notify == EN_CHANGE) {
                if (owner) |o| o.rebuildThemeList();
                return 0;
            }
            if (id == LIST_THEMES and notify == LBN_SELCHANGE) {
                if (owner) |o| o.applyThemeSelectionFromList();
                return 0;
            }
            if (id == LIST_THEMES and notify == LBN_DBLCLK) {
                if (owner) |o| {
                    o.applyThemeSelectionFromList();
                    o.save();
                }
                return 0;
            }
            if (id == CHK_EXPLORER_MENU and notify == BN_CLICKED) {
                if (owner) |o| o.syncExplorerMenuFromCheckbox();
                return 0;
            }
            if (id == EDIT_BG_OPACITY and notify == EN_CHANGE) {
                if (owner) |o| o.syncBgOpacityFromEdit();
                return 0;
            }
            if (id == EDIT_COMMAND and notify == EN_KILLFOCUS) {
                if (owner) |o| o.syncCommandFromEdit();
                return 0;
            }
            if (id == EDIT_PAD_X and notify == EN_CHANGE) {
                if (owner) |o| o.syncPaddingFromEdit(.x);
                return 0;
            }
            if (id == EDIT_PAD_Y and notify == EN_CHANGE) {
                if (owner) |o| o.syncPaddingFromEdit(.y);
                return 0;
            }
            if (id == CHK_TRIM_TRAIL and notify == BN_CLICKED) {
                if (owner) |o| o.syncTrimTrailFromCheckbox();
                return 0;
            }
            if (id == CHK_DESKTOP_NOTIFICATIONS and notify == BN_CLICKED) {
                if (owner) |o| o.syncDesktopNotificationsFromCheckbox();
                return 0;
            }
            if (id == CHK_APP_NOTIFY_CLIPBOARD and notify == BN_CLICKED) {
                if (owner) |o| o.syncAppNotificationsFromCheckbox(.clipboard);
                return 0;
            }
            if (id == CHK_APP_NOTIFY_CONFIG and notify == BN_CLICKED) {
                if (owner) |o| o.syncAppNotificationsFromCheckbox(.config);
                return 0;
            }
            if (id == COMBO_CONFIRM_CLOSE and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncConfirmCloseFromCombo();
                return 0;
            }
            if (id == COMBO_COPY_ON_SELECT and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncCopyOnSelectFromCombo();
                return 0;
            }
            if (id == COMBO_CLIPBOARD_READ and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncClipboardAccessFromCombo("clipboard-read", o.combo_clipboard_read);
                return 0;
            }
            if (id == COMBO_CLIPBOARD_WRITE and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncClipboardAccessFromCombo("clipboard-write", o.combo_clipboard_write);
                return 0;
            }
            if (id == COMBO_LINK_URL and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncLinkUrlFromCombo();
                return 0;
            }
            if (id == COMBO_LINK_PREVIEWS and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncLinkPreviewsFromCombo();
                return 0;
            }
            if (id == COMBO_WINDOW_THEME and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncWindowThemeFromCombo();
                return 0;
            }
            if (id == COMBO_SHELL_INTEG and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncShellIntegFromCombo();
                return 0;
            }
            if (id == COMBO_CURSOR_STYLE and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncCursorStyleFromCombo();
                return 0;
            }
            if (id == CHK_FOCUS_FOLLOWS and notify == BN_CLICKED) {
                if (owner) |o| o.syncFocusFollowsFromCheckbox();
                return 0;
            }
            if (id == CHK_BG_BLUR and notify == BN_CLICKED) {
                if (owner) |o| o.syncBgBlurFromCheckbox();
                return 0;
            }
            if (id == COMBO_PAD_BALANCE and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncPadBalanceFromCombo();
                return 0;
            }
            if (id == COMBO_AUTO_UPDATE and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncAutoUpdateFromCombo();
                return 0;
            }
            if (id == COMBO_AUTO_UPDATE_CHANNEL and notify == CBN_SELCHANGE) {
                if (owner) |o| o.syncAutoUpdateChannelFromCombo();
                return 0;
            }
            if (Section.fromButtonId(id)) |section| {
                if (owner) |o| o.setActiveSection(section);
                return 0;
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        WM_CLOSE => {
            _ = ShowWindow(hwnd, SW_HIDE);
            if (owner) |o| {
                o.clearChildRefs();
                // Let the app re-evaluate its quit-timer policy. If
                // we were the last live UI window, the timer kicks in
                // now; otherwise this is a no-op.
                o.handle.onClosed(o.handle.ctx);
            }
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_NCDESTROY => {
            // Clear back-pointer; the settings wndproc will no longer
            // dereference a freed owner even if a late paint slips
            // through. `onClosed` already fired from WM_CLOSE in the
            // user-initiated close path; avoid firing again here so
            // `App.deinit → settings_window.deinit` (which destroys
            // the HWND without the user closing it) doesn't re-enter
            // the quit-timer path during teardown.
            if (owner) |o| o.clearChildRefs();
            _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        else => return DefWindowProcW(hwnd, msg, wParam, lParam),
    }
}

fn recoverOwner(hwnd: HWND) ?*SettingsWindow {
    const raw = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    if (raw == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(raw)));
}

const DT_LEFT: UINT = 0x0;
const DT_WORDBREAK: UINT = 0x10;
const DT_TOP: UINT = 0x0;
const DT_CALCRECT: UINT = 0x400;
const DT_END_ELLIPSIS: UINT = 0x8000;

fn paint(hwnd: HWND, owner: *SettingsWindow) void {
    var ps: PAINTSTRUCT = undefined;
    const hdc = BeginPaint(hwnd, &ps);
    defer _ = EndPaint(hwnd, &ps);

    var rect: RECT = undefined;
    if (GetClientRect(hwnd, &rect) == 0) return;

    const colors = owner.handle.uiColors(owner.handle.ctx);

    const brush = GetStockObject(DC_BRUSH);
    _ = SetDCBrushColor(hdc, colors.bg);
    _ = FillRect(hdc, &rect, brush);

    // Left rail gets its own fill so the section buttons visually
    // separate from the content pane.
    var rail_rect = rect;
    rail_rect.right = left_rail_width;
    _ = SetDCBrushColor(hdc, colors.rail_bg);
    _ = FillRect(hdc, &rail_rect, brush);

    _ = SetBkMode(hdc, TRANSPARENT);

    const pane_left = left_rail_width + side_pad;
    const pane_right = rect.right - side_pad;
    const pane_top = section_btn_top_pad;

    // Header block: section title, one-line muted summary, hairline.
    var header_buf_w: [128]u16 = undefined;
    const header_w = utf8ToW(&header_buf_w, owner.active_section.headerText());
    var header_rect: RECT = .{
        .left = pane_left,
        .top = pane_top,
        .right = pane_right,
        .bottom = pane_top + header_title_h,
    };
    _ = SetTextColor(hdc, colors.text);
    if (owner.font_title) |f| _ = SelectObject(hdc, f);
    _ = DrawTextW(
        hdc,
        header_w,
        -1,
        &header_rect,
        DT_LEFT | DT_TOP | DT_SINGLELINE | DT_NOPREFIX,
    );

    var body_buf_w: [256]u16 = undefined;
    const body_w = utf8ToW(&body_buf_w, owner.active_section.placeholderText());
    var body_rect: RECT = .{
        .left = pane_left,
        .top = pane_top + header_title_h,
        .right = pane_right,
        .bottom = pane_top + header_title_h + header_summary_h,
    };
    _ = SetTextColor(hdc, colors.text_muted);
    if (owner.font_label) |f| _ = SelectObject(hdc, f);
    _ = DrawTextW(
        hdc,
        body_w,
        -1,
        &body_rect,
        DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX,
    );

    var sep_rect: RECT = .{
        .left = pane_left,
        .top = pane_top + header_title_h + header_summary_h + header_sep_gap,
        .right = pane_right,
        .bottom = pane_top + header_title_h + header_summary_h + header_sep_gap + 1,
    };
    _ = SetDCBrushColor(hdc, colors.border);
    _ = FillRect(hdc, &sep_rect, brush);

    // Field labels for grid sections — same table, same cursor as
    // `layoutChildren`, so labels always sit above their controls.
    const rows = sectionGridRows(owner.active_section);
    if (rows.len > 0) {
        _ = SetTextColor(hdc, colors.text_muted);
        var cursor = GridCursor.init(rect);
        for (rows) |row| {
            const p = cursor.place(row);
            if (row.label.len > 0) {
                drawLabel(hdc, p.control.left, p.label_y + 2, p.label_right, row.label);
            }
        }
    }

    // Bespoke sections: contextual help below the anchored control.
    switch (owner.active_section) {
        .keybindings => drawHelpBlock(
            hdc,
            pane_left,
            contentTop() + 32 + 24,
            pane_right,
            keybindingsHelpText(),
        ),
        .windows => drawHelpBlock(
            hdc,
            pane_left,
            contentTop() + 24 + 20,
            pane_right,
            "Adds an \"Open in Paramux\" entry when right-clicking a folder, a folder background, " ++
                "or a drive in Explorer, opening that folder in a new window. Per-user registry only " ++
                "(no admin). On Windows 11 the entry appears under \"Show more options\". " ++
                "Applies immediately; if you move the paramux folder later, the entry re-points " ++
                "itself on the next launch.",
        ),
        else => {},
    }
}

/// 1px rectangle outline via four DC-brush fills.
fn strokeRect(hdc: HDC, rect: RECT, color: COLORREF) void {
    const brush = GetStockObject(DC_BRUSH);
    _ = SetDCBrushColor(hdc, color);
    var line = rect;
    line.bottom = line.top + 1;
    _ = FillRect(hdc, &line, brush);
    line = rect;
    line.top = line.bottom - 1;
    _ = FillRect(hdc, &line, brush);
    line = rect;
    line.right = line.left + 1;
    _ = FillRect(hdc, &line, brush);
    line = rect;
    line.left = line.right - 1;
    _ = FillRect(hdc, &line, brush);
}

fn drawLabel(hdc: ?*anyopaque, x: i32, y: i32, right: i32, text: []const u8) void {
    var buf: [128]u16 = undefined;
    const w = utf8ToW(&buf, text);
    var rect: RECT = .{ .left = x, .top = y, .right = right, .bottom = y + 19 };
    _ = DrawTextW(hdc, w, -1, &rect, DT_LEFT | DT_TOP | DT_SINGLELINE | DT_NOPREFIX);
}

fn drawHelpBlock(hdc: ?*anyopaque, x: i32, y: i32, right: i32, text: []const u8) void {
    var buf: [1024]u16 = undefined;
    const w = utf8ToW(&buf, text);
    const flags = DT_LEFT | DT_TOP | DT_WORDBREAK | DT_NOPREFIX;
    var rect: RECT = .{ .left = x, .top = y, .right = right, .bottom = y };
    _ = DrawTextW(hdc, w, -1, &rect, flags | DT_CALCRECT);
    _ = DrawTextW(hdc, w, -1, &rect, DT_LEFT | DT_TOP | DT_WORDBREAK | DT_NOPREFIX);
}

fn readEditUtf8(edit: HWND, buf: []u8) ?[]const u8 {
    var buf_w: [edit_text_max_code_units]u16 = undefined;
    const n = GetWindowTextW(edit, &buf_w, @intCast(buf_w.len));
    const written = std.unicode.utf16LeToUtf8(buf, buf_w[0..@intCast(n)]) catch return null;
    return buf[0..written];
}

fn setEditText(edit: HWND, text: []const u8, suppress: *bool) void {
    var buf_w: [edit_text_max_code_units]u16 = undefined;
    const w = utf8ToW(&buf_w, text);
    suppress.* = true;
    _ = SendMessageW(edit, WM_SETTEXT, 0, @bitCast(@intFromPtr(w)));
    suppress.* = false;
}

fn parseFontFamilyEditText(alloc: std.mem.Allocator, text: []const u8) !Config.RepeatableString {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return .{};

    var next: Config.RepeatableString = .{};
    var parts = std.mem.splitScalar(u8, trimmed, ',');
    while (parts.next()) |part| {
        const family = std.mem.trim(u8, part, " \t");
        if (family.len == 0) continue;
        try next.parseCLI(alloc, family);
    }
    return next;
}

fn themeEntryLessThan(_: void, a: ThemeEntry, b: ThemeEntry) bool {
    return std.ascii.lessThanIgnoreCase(a.name, b.name);
}

/// 0xRRGGBB → COLORREF (0x00BBGGRR).
fn rgbToColorref(rgb: u32) COLORREF {
    const r = (rgb >> 16) & 0xFF;
    const g = (rgb >> 8) & 0xFF;
    const b = rgb & 0xFF;
    return r | (g << 8) | (b << 16);
}

/// `#RRGGBB` or `RRGGBB` → 0xRRGGBB, else null.
fn parseHexColor(text: []const u8) ?u32 {
    var hex = std.mem.trim(u8, text, " \t\r");
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len != 6) return null;
    return std.fmt.parseInt(u32, hex, 16) catch null;
}

/// Extract the preview colors from raw theme-file text. Tolerant parser:
/// unknown lines are skipped, later duplicates win (same as config load).
pub fn parseThemeSwatch(text: []const u8) ThemeSwatch {
    var swatch: ThemeSwatch = .{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#' or line[0] == ';') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trimRight(u8, line[0..eq], " \t");
        const value = std.mem.trimLeft(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, key, "background")) {
            if (parseHexColor(value)) |c| swatch.background = c;
        } else if (std.mem.eql(u8, key, "foreground")) {
            if (parseHexColor(value)) |c| swatch.foreground = c;
        } else if (std.mem.eql(u8, key, "palette")) {
            // value shape: "N=#RRGGBB"
            const inner_eq = std.mem.indexOfScalar(u8, value, '=') orelse continue;
            const index_text = std.mem.trim(u8, value[0..inner_eq], " \t");
            const color_text = value[inner_eq + 1 ..];
            const index = std.fmt.parseInt(u8, index_text, 10) catch continue;
            if (index >= swatch.palette.len) continue;
            if (parseHexColor(color_text)) |c| swatch.palette[index] = c;
        }
    }
    return swatch;
}

fn writeCommandForEdit(writer: *std.Io.Writer, value: Config.Command) !void {
    switch (value) {
        .shell => |v| try writer.writeAll(v),
        .direct => |v| {
            try writer.writeAll("direct:");
            for (v, 0..) |arg, i| {
                if (i != 0) try writer.writeByte(' ');
                try Config.Command.writeDirectArg(writer, arg);
            }
        },
    }
}

fn utf8ToW(buf: []u16, text: []const u8) [*:0]const u16 {
    const written = std.unicode.utf8ToUtf16Le(buf, text) catch buf.len;
    const n: usize = @min(written, buf.len - 1);
    buf[n] = 0;
    return @ptrCast(buf.ptr);
}

test "settings theme swatch parses colors and palette" {
    const swatch = parseThemeSwatch(
        \\# a comment
        \\palette = 0=#21222c
        \\palette = 1=#ff5555
        \\palette = 15=#ffffff
        \\background = #282a36
        \\foreground = f8f8f2
        \\cursor-color = #f8f8f2
    );
    try std.testing.expectEqual(@as(?u32, 0x282a36), swatch.background);
    try std.testing.expectEqual(@as(?u32, 0xf8f8f2), swatch.foreground);
    try std.testing.expectEqual(@as(?u32, 0x21222c), swatch.palette[0]);
    try std.testing.expectEqual(@as(?u32, 0xff5555), swatch.palette[1]);
    // Index 15 is beyond the 8 preview chips and must be ignored.
    try std.testing.expectEqual(@as(?u32, null), swatch.palette[7]);
}

test "settings theme swatch tolerates malformed input" {
    const swatch = parseThemeSwatch("palette = x=#nothex\nbackground = short\n= no key\n");
    try std.testing.expectEqual(@as(?u32, null), swatch.background);
    try std.testing.expectEqual(@as(?u32, null), swatch.palette[0]);
}

test "settings hex color parser accepts both # and bare forms" {
    try std.testing.expectEqual(@as(?u32, 0xa1b2c3), parseHexColor("#a1b2c3"));
    try std.testing.expectEqual(@as(?u32, 0xa1b2c3), parseHexColor("a1b2c3"));
    try std.testing.expectEqual(@as(?u32, null), parseHexColor("#a1b2"));
    try std.testing.expectEqual(@as(?u32, null), parseHexColor(""));
}

test "settings background blur checkbox preserves enabled radius" {
    try std.testing.expectEqual(
        Config.BackgroundBlur{ .radius = 42 },
        backgroundBlurFromCheckbox(.{ .radius = 42 }, true),
    );
    try std.testing.expectEqual(
        .true,
        backgroundBlurFromCheckbox(.false, true),
    );
    try std.testing.expectEqual(
        .true,
        backgroundBlurFromCheckbox(.{ .radius = 0 }, true),
    );
}

test "settings background blur checkbox can disable any variant" {
    try std.testing.expectEqual(
        .false,
        backgroundBlurFromCheckbox(.true, false),
    );
    try std.testing.expectEqual(
        .false,
        backgroundBlurFromCheckbox(.{ .radius = 42 }, false),
    );
}

test "settings policy combo mappings round trip" {
    try std.testing.expectEqual(Config.ClipboardAccess.ask, clipboardAccessFromComboIndex(0).?);
    try std.testing.expectEqual(Config.ClipboardAccess.allow, clipboardAccessFromComboIndex(1).?);
    try std.testing.expectEqual(Config.ClipboardAccess.deny, clipboardAccessFromComboIndex(2).?);
    try std.testing.expectEqual(@as(?Config.ClipboardAccess, null), clipboardAccessFromComboIndex(3));
    try std.testing.expectEqual(@as(usize, 0), comboIndexFromClipboardAccess(.ask));
    try std.testing.expectEqual(@as(usize, 1), comboIndexFromClipboardAccess(.allow));
    try std.testing.expectEqual(@as(usize, 2), comboIndexFromClipboardAccess(.deny));

    try std.testing.expectEqual(true, linkUrlFromComboIndex(0).?);
    try std.testing.expectEqual(false, linkUrlFromComboIndex(1).?);
    try std.testing.expectEqual(@as(?bool, null), linkUrlFromComboIndex(2));
    try std.testing.expectEqual(@as(usize, 0), comboIndexFromLinkUrl(true));
    try std.testing.expectEqual(@as(usize, 1), comboIndexFromLinkUrl(false));

    try std.testing.expectEqual(Config.LinkPreviews.true, linkPreviewsFromComboIndex(0).?);
    try std.testing.expectEqual(Config.LinkPreviews.osc8, linkPreviewsFromComboIndex(1).?);
    try std.testing.expectEqual(Config.LinkPreviews.false, linkPreviewsFromComboIndex(2).?);
    try std.testing.expectEqual(@as(?Config.LinkPreviews, null), linkPreviewsFromComboIndex(3));
    try std.testing.expectEqual(@as(usize, 0), comboIndexFromLinkPreviews(.true));
    try std.testing.expectEqual(@as(usize, 1), comboIndexFromLinkPreviews(.osc8));
    try std.testing.expectEqual(@as(usize, 2), comboIndexFromLinkPreviews(.false));
}

test "win32_settings: font-family edit text builds repeatable list" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const parsed = try parseFontFamilyEditText(
        arena.allocator(),
        " JetBrains Mono, Cascadia Code , , Symbols Nerd Font ",
    );
    try testing.expectEqual(@as(usize, 3), parsed.list.items.len);
    try testing.expectEqualStrings("JetBrains Mono", parsed.list.items[0]);
    try testing.expectEqualStrings("Cascadia Code", parsed.list.items[1]);
    try testing.expectEqualStrings("Symbols Nerd Font", parsed.list.items[2]);
}

test "win32_settings: direct command edit text quotes argv boundaries" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var source: Config.Command = undefined;
    try source.parseCLI(arena.allocator(), "direct:cmd.exe /c \"echo hello\" \"C:\\Program Files\\paramux\"");

    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try writeCommandForEdit(&writer, source);
    try testing.expectEqualStrings(
        "direct:cmd.exe /c \"echo hello\" \"C:\\Program Files\\paramux\"",
        writer.buffered(),
    );

    var round_trip: Config.Command = undefined;
    try round_trip.parseCLI(arena.allocator(), writer.buffered());
    try testing.expect(round_trip == .direct);
    try testing.expectEqual(@as(usize, 4), round_trip.direct.len);
    try testing.expectEqualStrings("echo hello", round_trip.direct[2]);
    try testing.expectEqualStrings("C:\\Program Files\\paramux", round_trip.direct[3]);
}

test "win32_settings: keybinding help points to discoverability commands" {
    const text = keybindingsHelpText();

    try std.testing.expect(text.len < 1024);
    try std.testing.expect(std.mem.indexOfScalar(u8, text, 0) == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list-keybinds --default") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list-keybinds --docs") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list-actions --docs") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "explain-config --keybind=<action>") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "keybind = ctrl+a>n=new_window") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "keybind = chain=goto_split:left") != null);
}
