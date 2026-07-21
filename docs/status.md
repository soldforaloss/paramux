# Paramux status

This page describes what currently works in Paramux, what remains partial, and
what is not part of the current release. When release copy disagrees with this
page, prefer the checked artifact and repository state.

Last reviewed: 2026-07-10, against the public `v0.1.18`
prerelease.

Paramux is derived from Winghostty, which in turn carries the Ghostty terminal
core into a native Windows runtime. Ghostty names remain where they identify an
upstream protocol, config format, resource, or library; the current product,
commands, state paths, and repository are Paramux-owned.

For installation and first use, see [getting-started.md](getting-started.md).
For Windows paths, app identity, notifications, and troubleshooting, see
[windows.md](windows.md). The
[Windows capability matrix](windows-capability-matrix.md) maps inherited
Ghostty documentation to current Paramux behavior.

## Current release support

- **Windows 10 and Windows 11 on x64** are the current prerelease target.
- The renderer requires OpenGL 4.3 or newer through WGL.
- `v0.1.18` is public, portable, prerelease-only, and unsigned.
- Its ZIP is feature- and branding-complete: Paramux README, completions, and
  VERSIONINFO, plus the agent-hooks payload, config presets, and the
  `send`/`send-key` verbs. It carries the 2026-07-10 UI/UX overhaul
  (toolbar tooltips, split-down/settings buttons, pane drag-and-drop,
  settings theme picker, merge/zoom/equalize menu actions, first-run hints,
  the optional Explorer context-menu entry) plus the CLI lifecycle verbs
  (`install`, `uninstall [--purge]`, checksum-verified `update`) — the
  first release the CLI can update FROM. The earlier `v0.1.0-paramux.4`
  build is a superseded legacy test artifact.
- The release contains `paramux-0.1.18-windows-x64-portable.zip` and
  `SHA256SUMS-windows-x64.txt`.
- `install-paramux.cmd` is a PATH helper inside the ZIP, not a system
  installer.
- ARM64, a signed installer, WinGet, Scoop, and a public stable channel are
  planned rather than currently supported release paths.
- No macOS, Linux, GTK, Wayland, or X11 app runtime ships from this repository.
  `libghostty-vt` remains buildable as a retained library deliverable.

## What works today

### Parallel agent workflow

- Native tabs and horizontal/vertical split panes.
- An always-visible split button in the tab strip, split actions in the menu
  and context menu, Windows-safe keybindings, and mouse-drag divider resize.
- A per-pane sidebar that can show title, working directory, Git branch and
  dirty state, listening ports, and the latest agent notification.
- Four attention states: `working`, `waiting`, `done`, and `error`.
- Attention cues across sidebar rows, pane rings, and tabs, plus Windows toast
  and taskbar attention behavior.
- Hook examples under `contrib/paramux/hooks/`, including a ready-to-merge
  Claude Code settings example.
- A console-independent `paramux notify` path that targets the pane identified
  by its injected `PARAMUX_SURFACE_ID`.

### Local control surface

- `paramux list-windows` reports the `paramux.windows.v2` schema with window,
  tab, and pane IDs plus structural/focus state.
- `paramux perform-action` forwards reviewed keybinding actions to the running
  instance.
- `paramux read-pane` returns the current viewport text for a target pane.
- `paramux send` writes one bounded UTF-8 payload to a focused or explicitly
  selected pane, and `paramux send-key` sends one key from a closed key set.
- Sensitive methods use a per-instance token supplied through `PARAMUX_TOKEN`
  inside panes or the token file under `%LOCALAPPDATA%\paramux` for external
  Paramux CLI clients.
- `list-windows` remains unauthenticated for structural discovery.
- The generic `perform-action` allowlist rejects terminal-input,
  arbitrary-file helper, and crash actions. Dedicated `send` and
  `send-key` methods provide the token-gated terminal-input path.

### Terminal core inherited from Ghostty

- VT parsing, screen/scrollback/alternate-screen behavior, and common DEC and
  xterm sequences.
- 256-color and true-color rendering.
- Bracketed paste, mouse tracking, OSC 8 hyperlinks, and OSC 10/11/52.
- Bidi text, combining marks, and grapheme-cluster rendering.
- Kitty graphics protocol and inline image display.
- Built-in themes, custom themes, and live config reload.
- The Ghostty `key=value` config grammar and `.ghostty` file extension.
- `libghostty-vt` for Zig and C consumers.

### Native Windows runtime

- Native Win32 message loop, host windows, tabs, and splits.
- Tab overflow, drag reorder, native context menus, and a shell profile picker.
- Per-monitor DPI handling and DWM dark-title-bar integration.
- High-contrast palette switching.
- IME support for composed input.
- Drag-and-drop of files into the terminal.
- OpenGL 4.3+ rendering through WGL.
- PowerShell, PowerShell 7, Command Prompt, Git Bash, and explicit WSL launch
  paths.
- PowerShell and supported Unix-like shell integration for cwd/prompt metadata;
  `cmd.exe` remains a plain fallback without automatic prompt metadata.
- Session-shape persistence for windows, tabs, split layout, selected profiles,
  working directories, and explicit titles. Terminal contents and child
  process state are not restored.
- Local crash dumps under `%LOCALAPPDATA%\paramux\crash`; nothing is uploaded
  automatically.

## Partial or experimental

### Windows UI Automation

Accessibility is partial. The Win32 host exposes a root UI Automation provider,
caption controls retain system-provider behavior, and the command palette has a
list provider. Terminal scrollback is not yet exposed through `ITextProvider`,
and broader per-widget coverage remains planned.

### Sidebar metadata

Working-directory, Git, and command-finish metadata depend on shell integration
emitting the relevant control sequences. PowerShell and supported Unix-like
shells provide richer metadata than plain `cmd.exe`. Listening-port discovery
is periodic and scoped to the pane's child process tree.

### Agent integrations

The Paramux attention protocol and `notify` command are complete. The
portable package includes concrete Claude Code settings, Codex hooks, a Gemini
CLI extension, and an OpenCode plugin. Their lifecycle events differ, so each
adapter maps only events its agent exposes. Run `install-paramux.cmd` first,
then install the relevant adapter and restart that agent.

### Update paths

The portable install updates itself: `paramux update` fetches the newest
GitHub release (prereleases included), verifies the portable ZIP's SHA-256
against the published checksum file, and swaps the files in place while
preserving configuration. `paramux install` / `paramux uninstall` wire and
un-wire the folder (PATH, `PARAMUX_HOME`, Explorer context menu, agent
hooks). The separate checksum- and Authenticode-gated installer updater in
the codebase targets a future stable signed release and is not a current
update path.

### Win32 runtime extraction

The Win32 application runtime remains centered on the large
`src/apprt/win32.zig` host module, with focused helpers gradually extracted into
`src/apprt/win32_*` modules. Further extraction should preserve message order,
child-HWND lifetime, focus, and repaint semantics.

## Known caveats

- **Unsigned test build.** Verify the SHA-256 checksum before running the
  current portable ZIP. The included PATH helper unblocks the extracted files,
  but does not provide Authenticode publisher trust.
- **Public prerelease.** Releases are public on `soldforaloss/paramux`;
  there is still no package-manager or signed-installer channel.
- **Hardware requirement.** Paramux has no DirectX or ANGLE fallback. A driver
  that cannot expose OpenGL 4.3 through WGL cannot run this build.
- **Portable resource tree.** Keep `paramux.exe`, `paramux.com`,
  `ghostty-vt.dll`, and the packaged `share` tree together.
- **Limited release matrix.** The current artifact is x64 only. ARM64 release
  verification remains outstanding.
- **No package-manager channel.** Any old Winghostty WinGet or Scoop identifiers
  belong to the predecessor project and do not install Paramux.
- **CLI-driven portable updates.** `paramux update` applies a
  checksum-verified newer release in place; there is no background
  auto-update, and windows must be closed while it runs.
- **Local-only crash capture.** Windows can write `.dmp` files for
  process-level unhandled exceptions, but some hard-abort paths may terminate
  before a dump is available.

## Out of scope

- macOS application packaging and Xcode workflows
- GTK/Linux/Wayland/X11 app-runtime work
- Flatpak, Snap, or other Linux desktop packaging
- Cloud-hosted terminals or remote VM orchestration
- Built-in browser, mobile client, or extension marketplace
- Reproducing Ghostty's upstream community process or governance

## Next release work

The next distribution milestones are intentionally explicit:

1. Complete hands-on validation of the portable x64 build on representative
   Windows hardware.
2. Acquire and configure a trusted code-signing identity.
3. Validate and publish a signed installer and signed portable binaries.
4. Build and verify an ARM64 release on real ARM64 Windows hardware.
5. Bootstrap Paramux-owned WinGet and Scoop manifests only after the signed
   release lane is stable.
6. Continue accessibility and focused Win32 module work without regressing the
   current agent workflow.
