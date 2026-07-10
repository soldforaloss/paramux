# Paramux Portable for Windows

Paramux is a native Windows command center for parallel coding agents. This
portable directory is self-contained: keep its binaries and `share` resources
together.

## Verify the download

Download the architecture-specific `SHA256SUMS-windows-<arch>.txt` beside the
ZIP from the same GitHub release. Before extracting the ZIP or running anything
inside it, compare the listed digest with:

```powershell
Get-FileHash .\paramux-<version>-windows-<arch>-portable.zip -Algorithm SHA256
Get-Content .\SHA256SUMS-windows-<arch>.txt
```

After the hashes match, extract the archive. You can then inspect its optional
Authenticode signature before running it:

```powershell
Get-AuthenticodeSignature .\paramux\paramux.exe |
  Select-Object Status, StatusMessage, SignerCertificate
```

Only run artifacts from the private Paramux release you were authorized to
access. The release page states whether that particular build is signed.

## Install and run

1. After verification and extraction, double-click `install-paramux.cmd`. It
   adds this directory to your user `PATH`, sets `PARAMUX_HOME`, writes trusted
   absolute paths into the packaged Claude/Codex hook templates, and removes
   the downloaded-file mark from the extracted files.
2. Open a new PowerShell or Command Prompt window.
3. Run `paramux`.

To remove the PATH entry later, run:

```powershell
.\install-paramux.ps1 -Remove
```

You can also run `paramux.exe` directly without installing a PATH entry.
`paramux.com` is the console-friendly launcher used by shells.

## Configuration and help

The user configuration is `%LOCALAPPDATA%\paramux\config.ghostty`. The
`.ghostty` extension, `ghostty-vt.dll`, and the `share\ghostty` resource folder
are retained compatibility names from Paramux's Ghostty terminal core.

Ready-to-install agent-attention adapters for Claude Code, Codex CLI, Gemini
CLI, and OpenCode are included in `agent-hooks\README.md`. Run the installer
before copying them: Claude and Codex receive absolute installed paths, while
Gemini and OpenCode resolve `paramux.com` through the installed
`PARAMUX_HOME`. Restart agents after setup.

The local automation surface can discover panes, read their viewport, and send
bounded input without a network service:

```powershell
paramux +list-windows
paramux +read-pane --surface-id=42
paramux +send --surface-id=42 "npm test"
paramux +send-key --surface-id=42 enter
```

For tmux/wmux muscle memory, `config-presets\tmux-prefix.ghostty` adds opt-in
`Ctrl+B` sequences for tabs, splits, pane navigation, resize, zoom, and close.
Include it from `%LOCALAPPDATA%\paramux\config.ghostty` with an absolute path:

```ini
config-file = "C:\\Tools\\paramux\\config-presets\\tmux-prefix.ghostty"
```

Paramux's direct native shortcuts remain enabled alongside the preset.

- Repository and release notes: https://github.com/soldforaloss/paramux
- Getting started: https://github.com/soldforaloss/paramux/blob/paramux/docs/getting-started.md
- Windows reference: https://github.com/soldforaloss/paramux/blob/paramux/docs/windows.md
- Capability status: https://github.com/soldforaloss/paramux/blob/paramux/docs/paramux/capability-parity.md
- Security policy: https://github.com/soldforaloss/paramux/blob/paramux/SECURITY.md

Run `paramux +help` for CLI actions and `paramux +list-keybinds` for the active
keyboard map.
