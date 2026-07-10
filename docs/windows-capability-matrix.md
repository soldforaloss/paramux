# Windows capability matrix

This matrix maps official Ghostty documentation surfaces to current Paramux
behavior on Windows. Paramux descends from Winghostty and retains Ghostty's
terminal core, config grammar, resource formats, and `libghostty-vt`; its native
Windows host and agent workflow are Paramux-specific.

Last reviewed: 2026-07-10, against the public x64 portable prerelease
`v0.1.0-paramux.7`.

## Status legend

- `supported` - the current Windows build matches the upstream behavior closely
  enough to use the Ghostty documentation.
- `partial` - the shared surface exists, but Windows behavior or current
  distribution is narrower.
- `windows-specific` - Paramux adds or materially changes the behavior, so the
  upstream Ghostty documentation is not the complete source.

## Supported

| Ghostty documentation surface | Paramux note |
| --- | --- |
| [Configuration](https://ghostty.org/docs/config) and [option reference](https://ghostty.org/docs/config/reference) | Paramux retains the Ghostty `key=value` grammar and generated option docs. The normal Windows config path is `%LOCALAPPDATA%\paramux\config.ghostty`; reload with `Ctrl+Shift+,`. |
| [Custom keybindings](https://ghostty.org/docs/config/keybind) | The `keybind = trigger=action` grammar and `+list-keybinds` command are shared. Paramux supplies Windows-safe defaults for tabs and splits. |
| [Color themes](https://ghostty.org/docs/features/theme) | Built-in themes, separate light/dark themes, custom themes, and `paramux +list-themes` are available. Paramux also provides `+import-theme` for Windows Terminal color schemes. |
| [Configuration: `background-opacity`](https://ghostty.org/docs/config/reference) | Transparent terminal backgrounds work on Windows and can be changed through config reload. |
| [Terminal API (VT)](https://ghostty.org/docs/vt) and [VT reference](https://ghostty.org/docs/vt/reference) | The shared Ghostty terminal core carries the documented VT, OSC, and Kitty protocol surfaces used by terminal applications. |

## Partial

| Ghostty documentation surface | Paramux note |
| --- | --- |
| [Shell integration](https://ghostty.org/docs/features/shell-integration) | Automatic integration applies to supported Unix-like shells launched on Windows. Paramux also integrates Windows PowerShell and PowerShell 7, with a manual fallback under `%LOCALAPPDATA%\paramux\shell-integration\powershell\integration.ps1`. PowerShell emits cwd and prompt metadata used by the sidebar. `cmd.exe` remains a plain fallback. |
| [Action reference](https://ghostty.org/docs/config/keybind/reference) | The shared action grammar remains, but some upstream actions are platform-specific. For effective Windows truth, use `paramux +show-config --default --docs` and `paramux +list-keybinds`. |
| [Action reference: `toggle_secure_input`](https://ghostty.org/docs/config/keybind/reference) | Windows provides a local sensitive-input indicator and cursor/status/title state. It does not implement macOS Secure Keyboard Entry or block system-wide keyboard hooks. |
| [Configuration: `window-save-state`](https://ghostty.org/docs/config/reference) | Paramux persists practical session shape under `%LOCALAPPDATA%\paramux\session-state.json`: windows, tabs, splits, selected profiles, working directories, and explicit titles. Terminal contents and child process state are not restored. |
| [Configuration: `background-blur`](https://ghostty.org/docs/config/reference) | On supported Windows 11 builds, a transparent background plus enabled blur requests a DWM system backdrop. Older Windows versions accept the option without the same backdrop. Numeric radii act as enabled/disabled rather than tunable blur strength. |
| [Features overview](https://ghostty.org/docs/features) | Accessibility is partial: the Win32 host exposes a UI Automation root provider and the command palette exposes a list provider, but terminal scrollback is not yet available through `ITextProvider`. |
| OSC 52 clipboard selectors | Windows has one native clipboard. Writes using `c`, `s`, or `p` target that clipboard; read replies preserve the requested selector for client correlation. |
| [Configuration: `auto-update`](https://ghostty.org/docs/config/reference) | The codebase has a future signed-installer check/download path. The current prerelease is unsigned and portable-only, so it must be updated manually; `auto-update = download` is not a current distribution path. |

## Windows-specific

| Surface | Paramux note |
| --- | --- |
| Native Windows app | Paramux ships a native Win32 app for Windows 10/11. The current release artifact is x64 only; ARM64 release support is planned and not yet published. |
| GPU rendering | Paramux renders through WGL with OpenGL 4.3+. It has no DirectX or ANGLE fallback. |
| Windows paths and identity | App state lives under `%LOCALAPPDATA%\paramux\...`; the app identity is `io.github.soldforaloss.paramux`. |
| Tabs and splits | Native tabs, horizontal/vertical splits, tab drag reorder, a visible split button, menu/context split actions, mouse divider resize, and Windows-safe focus/resize keybindings ship today. |
| Agent workspace | A per-pane sidebar shows available cwd/Git/port/notification metadata. `working`, `waiting`, `done`, and `error` states drive sidebar, pane, tab, toast, and taskbar attention. |
| Local automation | `paramux +list-windows` reports `paramux.windows.v2` structural JSON. `+perform-action`, `+notify`, `+read-pane`, `+send`, and `+send-key` are token-gated; `PARAMUX_SURFACE_ID` targets panes and `PARAMUX_TOKEN` authenticates in-pane clients. The generic `+perform-action` allowlist rejects terminal-input, arbitrary-file helper, and crash actions; the dedicated `+send`/`+send-key` methods are the bounded terminal-input path. |
| Windows UX | DWM dark-title-bar integration, high-contrast palette switching, IME, file drag-and-drop, native context menus, profile selection, taskbar progress, and WinRT toast attempts are implemented in the Win32 host. |
| Current distribution | The public `v0.1.0-paramux.7` release contains one unsigned x64 portable ZIP, `SHA256SUMS-windows-x64.txt`, and the `install-paramux.cmd` PATH helper. Signed installer, WinGet, Scoop, ARM64, and public stable channels are planned. |

## Maintenance anchors

- `src/config/Config.zig` - config docs, keybindings, and updater option text.
- `src/termio/shell_integration.zig` and `src/config/windows_shell.zig` - shell
  integration and Windows shell detection.
- `src/apprt/win32.zig`, `src/apprt/ipc.zig`, and `src/apprt/win32_*` - native
  host, automation, agent sidebar, attention, chrome, and accessibility.
- `src/cli/notify.zig`, `src/cli/read_pane.zig`, and
  `src/cli/list_windows.zig` - Paramux control-surface commands.
- [status.md](status.md), [getting-started.md](getting-started.md), and
  [windows.md](windows.md) - user-facing summaries that should stay aligned
  with this matrix.
