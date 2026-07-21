# Paramux on Windows

This page collects Windows-specific behavior, paths, identity, and
troubleshooting. Paramux uses the Ghostty terminal core through its Winghostty
lineage, so upstream Ghostty documentation remains useful for shared terminal
and config behavior. See
[windows-capability-matrix.md](windows-capability-matrix.md) for the exact
mapping.

## Current system requirements

- Windows 10 or Windows 11 on x64.
- A GPU and driver that expose OpenGL 4.3 or newer through WGL.
- The public `soldforaloss/paramux` repository to download the
  current prerelease.

The current user artifact is the unsigned x64 portable prerelease
`v0.1.16`. ARM64 artifacts, signed installers, WinGet, Scoop, and a
public stable channel are planned rather than current.

Paramux is a native Win32 application. This repository does not ship macOS,
Linux, GTK, Wayland, or X11 app runtimes. `libghostty-vt` remains portable as a
retained library surface.

## Current install mode

Download these two release assets:

- `paramux-0.1.16-windows-x64-portable.zip`
- `SHA256SUMS-windows-x64.txt`

Verify the checksum, extract the ZIP, and keep the full resource tree together.
Then double-click `install-paramux.cmd` to unblock that extracted tree and add
its folder to the current user's `PATH`. Open a new terminal and run `paramux`.

The helper is not a system installer: it does not copy Paramux to Program
Files, add an uninstaller, or establish Authenticode publisher trust. Run it
only after verifying the unsigned ZIP came from the official Paramux release.

## Paths

Normal runtime state lives under:

```text
%LOCALAPPDATA%\paramux\
```

Shared XDG helpers still honor `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, and
`XDG_CACHE_HOME` when those variables are explicitly set. `%LOCALAPPDATA%` is
the normal Windows fallback.

Important files and directories:

| Path | Purpose |
| --- | --- |
| `%LOCALAPPDATA%\paramux\config.ghostty` | User config. The extension and grammar are retained from Ghostty. |
| `%LOCALAPPDATA%\paramux\session-state.json` | Window, tab, split, profile, cwd, and title restore state when enabled. |
| `%LOCALAPPDATA%\paramux\paramux-ipc-token` | Current local IPC token used by external Paramux CLI clients. Treat it as user-private runtime state. |
| `%LOCALAPPDATA%\paramux\crash\` | Local crash dumps. Nothing here is uploaded automatically. |
| `%LOCALAPPDATA%\paramux\shell-integration\` | Installed shell-integration payloads and manual fallbacks. |

The portable ZIP carries bundled resources next to the executable. Do not move
only `paramux.exe` out of the extracted tree; it relies on the packaged `share`
tree for themes, terminfo, shell integration, and related data.

## Shells

The profile picker detects common Windows shells:

- Windows PowerShell (`powershell.exe`)
- PowerShell 7+ (`pwsh.exe`)
- Command Prompt (`cmd.exe`)
- Git Bash
- WSL when explicitly configured

PowerShell and supported Unix-like shells can use automatic shell integration.
PowerShell integration emits working-directory and prompt metadata that drives
the Paramux sidebar. `cmd.exe` remains a plain fallback without automatic cwd,
prompt, or command-finish metadata.

WSL is supported as an explicitly launched shell:

```ini
command = wsl.exe
```

Paramux does not select WSL implicitly because `wsl.exe --status` can look
healthy even when no distribution can start.

## App identity

The Paramux application identity is:

```text
io.github.soldforaloss.paramux
```

It is used for instance naming and Windows app identity. The current portable
build does not have installer-created Start menu shortcuts, so taskbar grouping
and Action Center activation can be less stable than they will be in a future
signed installed build.

If Windows shows a stale icon after replacing an extracted build, confirm the
running executable path first. Restart Explorer or clear the icon cache before
treating a persistent stale icon as a packaging regression.

## Agent sidebar and attention

Paramux adds a native sidebar with one row per pane. Rows can display terminal
title, cwd, Git branch/dirty state, listening ports, and the latest
notification. The four attention states are `working`, `waiting`, `done`, and
`error`.

Agent hooks call:

```powershell
paramux notify --state=waiting "Agent needs input"
paramux notify --state=done "Agent finished"
```

The state is reflected in sidebar, pane, and tab cues. Paramux also requests a
Windows toast and taskbar attention when appropriate. Windows notification
policy, Focus Assist, app identity, or runtime availability can suppress a
toast; the in-app state remains the primary signal.

Terminal progress reports are mapped to Windows taskbar progress for the active
surface in each host window.

## Windows, tabs, and splits

The native Win32 host provides:

- tab overflow and drag reorder
- horizontal and vertical splits
- an always-visible one-click split button plus menu/context split actions
- mouse-drag split-divider resize
- Windows-safe split focus and resize keybindings
- per-monitor DPI handling
- DWM dark-title-bar integration
- high-contrast palette switching
- IME support
- drag-and-drop into the terminal
- native context menus

Session restore persists practical shape: windows, tabs, split layout, selected
profiles, working directories, and explicit titles. It does not restore
terminal contents or child process state.

## Quick terminal and global hotkeys

The quick terminal uses the `toggle_quick_terminal` action and
`quick-terminal-*` config family where those settings map to Windows. Global
keybindings use Win32 `RegisterHotKey` while Paramux is running. Windows or
another application may reserve a hotkey first.

`quick-terminal-keyboard-interactivity = exclusive` maps to focused input on
Windows. Paramux does not implement global keyboard capture.

## Local automation

The local control surface uses the Paramux Win32 IPC path:

```powershell
paramux list-windows
paramux perform-action new_tab
paramux perform-action --surface-id=<surface_id> toggle_fullscreen
paramux read-pane --surface-id=<surface_id>
paramux send --surface-id=<surface_id> "npm test"
paramux send-key --surface-id=<surface_id> enter
paramux notify --surface-id=<surface_id> --state=waiting "Needs input"
```

The full verb map (status, attention, run, layouts, doctor, serve,
record, update) lives in
[docs/paramux/fleet-cli.md](paramux/fleet-cli.md).

`list-windows` reports the `paramux.windows.v2` JSON schema. It exposes local
window/tab/pane IDs and structural state without terminal text. `read-pane`
is the explicit, token-gated viewport-text operation.

`perform-action`, `notify`, `read-pane`, `send`, and `send-key` require the
current instance token. Paramux injects `PARAMUX_TOKEN` and
`PARAMUX_SURFACE_ID` into panes; external Paramux CLI clients read the token
from the local state directory. `send` accepts one non-empty, valid UTF-8
payload up to 16 KiB; `send-key` uses the pane's current terminal keyboard
modes. The generic action allowlist still rejects terminal-write,
arbitrary-file helper, and crash actions, and new action variants remain
disabled until reviewed.

## Troubleshooting

### Unsigned portable build

The current executable is not Authenticode-signed. Verify the downloaded ZIP
against `SHA256SUMS-windows-x64.txt` before running `install-paramux.cmd` or any
binary. The helper removes Mark-of-the-Web from the extracted files, so perform
the verification first.

### OpenGL driver failures

Paramux needs OpenGL 4.3 or newer through WGL and has no DirectX or ANGLE
fallback. Update or reinstall the graphics driver if the app exits during
renderer initialization.

`LoadLibrary failed with error 126` or `ERROR_MOD_NOT_FOUND` during WGL startup
usually means Windows could not load a graphics-driver DLL or one of its
dependencies. On hybrid-GPU laptops, update the OEM integrated-GPU driver and
the discrete-GPU driver, then try assigning `paramux.exe` to a specific GPU in
Windows Graphics settings.

### Missing themes or resources

If theme listing or startup reports missing resources, confirm that
`paramux.exe` is still beside the extracted package's `share` tree. Re-extract
the complete ZIP instead of copying individual binaries.

### Notifications do not appear

Check Windows notification settings and Focus Assist. The current portable
build lacks installer-created Start menu identity, so toast behavior can vary;
sidebar and pane attention state should still update.

### Global hotkey conflicts

Pick a different trigger if Windows or another app already owns the configured
global hotkey, then reload the config.

### WSL launch failures

Set WSL explicitly with `command = wsl.exe`. If launch still fails, verify the
target distribution starts from a normal PowerShell session.

### Stale Paramux build on `PATH`

Use these commands to see which launcher is being selected:

```powershell
Get-Command paramux -All
where.exe paramux
```

Remove an old extracted folder from the user `PATH` or run its
`install-paramux.ps1 -Remove` helper. Windows normally resolves `paramux.com`
before `paramux.exe` for command-line invocations; both should come from the
same extracted build.

### Updating the prerelease

Run `paramux update` (or `paramux update --check` to only look). It
downloads the newest release's portable ZIP, verifies its SHA-256 against
the published checksum file, and swaps the files in place; close paramux
windows first, and configuration is never touched. The manual path —
download the next ZIP, verify its checksum, extract, rerun the PATH
helper — still works.
