# Getting started with Paramux

This guide covers the current private Windows prerelease: download, verify,
extract, add Paramux to `PATH`, launch agent panes, configure the terminal, and
uninstall it.

## 1. Get the private x64 prerelease

The current build is
[`v0.1.0-paramux.6`](https://github.com/soldforaloss/paramux/releases/tag/v0.1.0-paramux.6)
in the private `soldforaloss/paramux` repository. You must be signed in to an
account with repository access.

Download both assets:

- `paramux-0.1.0-paramux.6-windows-x64-portable.zip`
- `SHA256SUMS-windows-x64.txt`

This is an **unsigned x64 portable prerelease**. There is no current Paramux
installer, WinGet package, Scoop package, ARM64 release, or public stable
download.

This build is feature- and branding-complete and adds the UI/UX overhaul:
the five-button toolbar with hover tooltips, drag-and-drop pane
rearrangement from the sidebar, the settings theme picker, merge/zoom/
equalize actions, first-run hints, and the optional Explorer "Open in
Paramux" entry — on top of the agent-hook adapters, the `+send`/`+send-key`
commands (section 9), the packaged tmux-prefix preset (section 7), and
fully populated Paramux VERSIONINFO. The earlier `v0.1.0-paramux.4` build
is a superseded legacy test artifact.

Paramux requires Windows 10 or Windows 11 and a GPU/driver that exposes OpenGL
4.3 or newer through WGL.

## 2. Verify the download

From the folder containing both downloaded files:

```powershell
Get-FileHash `
  .\paramux-0.1.0-paramux.6-windows-x64-portable.zip `
  -Algorithm SHA256
Get-Content .\SHA256SUMS-windows-x64.txt
```

Confirm the two SHA-256 values match before running the unsigned build.

## 3. Extract and add Paramux to `PATH`

1. Extract the ZIP into a permanent parent folder, for example `C:\Tools\`.
   The archive contains a top-level `paramux` folder, so the tree lands at
   `C:\Tools\paramux\`.
2. Keep the entire extracted tree together. Paramux needs its packaged `share`
   resources; do not copy only `paramux.exe` elsewhere.
3. Double-click `install-paramux.cmd` inside the extracted `paramux` folder.
4. Open a **new** terminal so the updated user `PATH` is visible.

`install-paramux.cmd` runs the adjacent PowerShell helper. It removes the
download mark from files in that extracted folder and adds the folder to the
current user's `PATH`; it does not copy files to Program Files and does not
require administrator access.

You can skip the helper and run `paramux.exe` directly from the extracted
folder if you do not want to change `PATH`.

## 4. Launch Paramux

From a new PowerShell or Command Prompt window:

```powershell
paramux
```

Launch directly into a coding agent or another command:

```powershell
paramux -e claude
paramux -e pwsh
```

Windows command lookup normally selects `paramux.com` for the CLI command; the
console launcher starts the adjacent `paramux.exe` application.

## 5. Create tabs and split panes

The tab strip exposes an always-visible split button (`◫`) between the new-tab
button and the menu. Clicking it creates a split to the right. The menu and
right-click context menu also expose split directions.

Useful defaults:

| Action | Binding |
| --- | --- |
| New tab | `Ctrl+Shift+T` |
| Close the focused surface | `Ctrl+Shift+W` |
| Next / previous tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| Split right / down | `Ctrl+Shift+O` / `Ctrl+Shift+E` |
| Focus split by direction | `Ctrl+Alt+Arrow` |
| Focus previous / next split | `Ctrl+Alt+[` / `Ctrl+Alt+]` |
| Resize the focused split | `Ctrl+Alt+Shift+Arrow` |
| Start search | `Ctrl+Shift+F` |
| Reload config | `Ctrl+Shift+,` |

You can also drag a split divider with the mouse.

See the complete effective list with:

```powershell
paramux +list-keybinds
```

## 6. Use the agent sidebar and attention states

Each pane gets a sidebar row. Depending on shell integration and the running
process, the row can show its title, working directory, Git branch/dirty state,
listening ports, and latest notification.

Paramux has four agent-attention states: `working`, `waiting`, `done`, and
`error`. They drive the sidebar, pane and tab color cues, Windows notification,
and taskbar attention behavior.

Agent integration examples live in
[`contrib/paramux/hooks/`](../contrib/paramux/hooks/README.md). The Claude Code
settings example can be merged into your user or project settings. Other agent
examples use the same command:

```powershell
paramux +notify --state=waiting "Agent needs input"
paramux +notify --state=done "Agent finished"
```

Run `+notify` from inside the pane you want to update. Paramux injects
`PARAMUX_SURFACE_ID` into each pane so the command can target the correct row.

## 7. Configure the terminal

On first launch, Paramux uses:

```text
%LOCALAPPDATA%\paramux\config.ghostty
```

Open it with:

```powershell
notepad "$env:LOCALAPPDATA\paramux\config.ghostty"
```

Example options:

```ini
font-family = JetBrains Mono
font-size = 12
# Theme files are config files; only use themes from sources you trust.
theme = Dracula
```

The `.ghostty` extension and config grammar are retained from the shared
Ghostty terminal core. Save the file and press `Ctrl+Shift+,` to reload it.

List themes and inspect all options with inline documentation:

```powershell
paramux +list-themes
paramux +show-config --default --docs | more
```

Rebind an action with the same `trigger=action` grammar:

```ini
keybind = ctrl+t=new_tab
keybind = ctrl+shift+r=reload_config
```

### Optional tmux-style `Ctrl+B` prefix

The portable package includes `config-presets\tmux-prefix.ghostty`. It uses
the same built-in sequence engine as every other keybinding; no tmux process
or WSL session is required. Add the extracted preset to your config with an
absolute path:

```ini
config-file = "C:\\Tools\\paramux\\config-presets\\tmux-prefix.ghostty"
```

The preset covers common tmux/wmux tab, split, pane-focus, resize, zoom, close,
and numeric-selection chords. Direct Paramux shortcuts remain available.

## 8. Choose a shell

The in-app profile picker detects common Windows shells, including PowerShell,
Command Prompt, Git Bash, and explicitly configured WSL distributions. Override
the launched command in the config when needed:

```ini
command = pwsh.exe
```

To opt in to WSL:

```ini
command = wsl.exe
```

Paramux does not choose WSL implicitly because an installed WSL environment is
not proof that a distribution can launch successfully.

## 9. Local automation

List the running windows, tabs, and panes:

```powershell
paramux +list-windows
```

The response schema is `paramux.windows.v2`. The list response includes IDs,
focus/active state, and structural counts; it does not include terminal text.

Invoke an allowlisted action on the focused surface or a specific pane:

```powershell
paramux +perform-action new_tab
paramux +perform-action --surface-id=<surface_id> toggle_fullscreen
```

Read a pane's current viewport text:

```powershell
paramux +read-pane --surface-id=<surface_id>
```

Send exact UTF-8 text and a named terminal key to that pane:

```powershell
paramux +send --surface-id=<surface_id> "npm test"
paramux +send-key --surface-id=<surface_id> enter
```

`+perform-action`, `+notify`, `+read-pane`, `+send`, and `+send-key` use the
current Paramux instance token. In-pane clients receive it through
`PARAMUX_TOKEN`; external Paramux CLI clients use the token file under
`%LOCALAPPDATA%\paramux`. `+list-windows` remains unauthenticated for structural
discovery.

`+send` accepts one non-empty, valid UTF-8 payload up to 16 KiB. `+send-key`
supports Enter, Tab, Escape, Backspace, Delete, arrows, Home, End, Page Up, and
Page Down while respecting the pane's active terminal keyboard modes. The
generic action allowlist continues to reject terminal-write, arbitrary file
helper, and crash actions. New action variants remain disabled until reviewed.

## 10. Updates

Do not rely on the built-in stable installer updater for the current release.
`v0.1.0-paramux.6` is private, marked as a prerelease, portable-only, and
unsigned. Update manually by downloading the next private portable ZIP,
verifying its checksum, and replacing the extracted folder.

A signed installer update lane is planned, but it is not a current user path.

## 11. Crash reports

Paramux keeps local crash data under:

```text
%LOCALAPPDATA%\paramux\crash
```

Nothing in that directory is uploaded automatically. Inspect the local report
surface with:

```powershell
paramux +crash-report
```

## 12. Uninstall

From the extracted Paramux folder, remove that folder from your user `PATH`:

```powershell
.\install-paramux.ps1 -Remove
```

Open a new terminal, then delete the extracted folder. Runtime state is kept
separately under `%LOCALAPPDATA%\paramux` and is not removed automatically;
delete that directory manually only if you also want to remove configuration,
session state, and crash data.

## Next steps

- [Status](status.md) - supported behavior, current distribution status, and
  known caveats
- [Windows notes](windows.md) - paths, app identity, notifications, shells,
  automation, and troubleshooting
- [Windows capability matrix](windows-capability-matrix.md) - how inherited
  Ghostty documentation maps to Paramux
- [HACKING.md](../HACKING.md) - build, test, and runtime notes
- [CONTRIBUTING.md](../CONTRIBUTING.md) - repository contribution rules
