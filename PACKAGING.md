# Packaging Paramux for Windows

Paramux is currently distributed as an unsigned public Windows prerelease. This page
describes the artifacts that exist today and keeps future distribution work
separate from the current user path.

## Current distribution contract

As of 2026-07-20, the current build is the public prerelease
[`v0.1.7`](https://github.com/soldforaloss/paramux/releases/tag/v0.1.7).

## Versioning scheme

Releases use plain semantic versions (since `v0.1.1`; everything
before that used the historical `v0.1.0-paramux.N` prerelease naming,
which ended with `v0.1.0-paramux.9`):

- Tags are `vMAJOR.MINOR.PATCH`, with no `-paramux.N` or other
  suffixes.
- The release title is the bare tag (for example `v0.1.7`) — no
  "paramux" prefix or descriptive suffix in the release name.
- Artifact names keep their existing shape
  (`paramux-<version>-windows-x64-portable.zip`), so the `paramux update`
  pipeline is unaffected; semver orders `0.1.7` above `0.1.0-paramux.9`.
- The Release workflow no longer fires on tag pushes: it requires
  signing/distribution secrets that are not configured, so releases stay
  manual (`gh release create`) until those exist.

It publishes exactly these two assets:

- `paramux-0.1.7-windows-x64-portable.zip`
- `SHA256SUMS-windows-x64.txt`

This artifact is branding-complete: its embedded README, command completions,
and launcher VERSIONINFO all carry the Paramux identity, and the packaging
source enforces each of those properties. The earlier `v0.1.0-paramux.4`
build remains available only as a superseded legacy test artifact.

The executable is **unsigned**. The ZIP is a portable build, and
`install-paramux.cmd` inside it is a convenience script that unblocks the
extracted files and adds that folder to the current user's `PATH`. It is not a
Windows installer and does not install Paramux under Program Files.

The following distribution channels are planned, not current:

- an Authenticode-signed installer
- signed portable binaries
- a public stable release channel
- WinGet and Scoop packages
- ARM64 release artifacts

Do not advertise commands or artifacts for those channels until the required
signing identity, manifests, release assets, and hardware verification exist.

## Portable package contents

The staged `paramux` directory contains the runnable binaries and their resource
tree, including:

- `paramux.exe` and the console launcher `paramux.com`
- `install-paramux.cmd` and `install-paramux.ps1`
- concrete Claude Code, Codex, Gemini CLI, and OpenCode adapters under
  `agent-hooks`, plus the root `paramux-codex-hook.cmd` launcher
- `config-presets\tmux-prefix.ghostty`, validated by the packaged binary
- `ghostty-vt.dll`
- the packaged `share` tree used for themes, terminfo, and shell integration
- `config-template.ghostty`, `paramux.ico`, `README.md`, and `LICENSE`

Keep the extracted tree together. Copying only `paramux.exe` drops resources
that the app expects at runtime. The `.ghostty` config extension,
`libghostty-vt` name, and Ghostty resource names are intentionally retained
from the terminal core lineage.

## Build locally

The repository is pinned to Zig `0.15.2` in CI. From the repository root:

```powershell
zig build -Demit-exe=true
```

If Zig cannot hydrate the dependency cache automatically, seed it first:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-zig-deps.ps1
zig build -Demit-exe=true
```

The app binaries are written to `zig-out\bin\paramux.exe` and
`zig-out\bin\paramux.com`.

## Stage an x64 portable package

Use the Windows packaging script with an explicit architecture:

```powershell
$version = "0.1.7"
powershell -ExecutionPolicy Bypass -File scripts/package-windows.ps1 `
  -Version $version `
  -Architecture x64 `
  -SkipInstaller
```

The portable output is staged beneath:

```text
dist\artifacts\paramux-0.1.7-windows-x64\
```

The packaging script performs its own package smoke checks and emits the
portable ZIP plus `SHA256SUMS-windows-x64.txt`. Unsigned local packaging is the
expected path for the current prerelease.

`-SkipInstaller` keeps prerelease suffixes out of Inno Setup's numeric version
fields and produces only the artifact that exists today. A separate numeric
version plus `-RequireInstaller` and `-RequireSigning` exercises the future
signed distribution path; it is not part of rebuilding the current portable
prerelease.

## Verify a portable package

Run the x64 baseline guard and inspect the staged files before uploading:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-windows-x64-baseline.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/check-windows-x64-baseline.ps1 `
  -Path zig-out\bin\paramux.exe

Get-FileHash `
  .\dist\artifacts\paramux-0.1.7-windows-x64\paramux-0.1.7-windows-x64-portable.zip `
  -Algorithm SHA256
```

Compare the hash with `SHA256SUMS-windows-x64.txt`, then extract the ZIP to a
temporary directory and verify:

```powershell
.\paramux\paramux.com version
Get-AuthenticodeSignature .\paramux\paramux.exe | Select-Object Status, StatusMessage
```

For `v0.1.7`, `NotSigned` is the expected signature status. A future
signed channel must instead fail closed unless the expected Authenticode signer
and checksum both validate.

## Prerelease checklist

For the current release lane:

1. Run targeted tests for the changed code, followed by `zig build`.
2. Run the x64 baseline check.
3. Stage the x64 portable package with the intended prerelease version.
4. Confirm the ZIP contains the full resource tree and both PATH-helper files.
5. Confirm `paramux.com version` runs from the extracted ZIP.
6. Confirm the checksum file matches the uploaded ZIP.
7. Publish to `soldforaloss/paramux` as a **prerelease**, not a stable release.
8. Upload only the artifacts that were actually built and verified.

The repository and releases are public, but this lane is still not a signed
installer or package-manager release. Do not describe it as one.

## Planned signed installer

The packaging code has Authenticode and Inno Setup support ready for a future
signed channel. That channel still requires a real code-signing identity and a
release decision.

The signing inputs are:

- `WINDOWS_CODESIGN_PFX_BASE64`
- `WINDOWS_CODESIGN_PFX_PASSWORD`
- optional `WINDOWS_CODESIGN_TIMESTAMP_URL`
- optional `WINDOWS_CODESIGN_TRUST_SELF_SIGNED` for internal probes only

An internal signing smoke can use a local PFX:

```powershell
$env:WINDOWS_CODESIGN_PFX_PATH = "C:\secure\paramux-signing.pfx"
$env:WINDOWS_CODESIGN_PFX_PASSWORD = "<pfx-password>"
$env:WINDOWS_CODESIGN_TRUST_SELF_SIGNED = "true"

powershell -ExecutionPolicy Bypass -File scripts/package-windows.ps1 `
  -Version 0.1.0 `
  -Architecture x64 `
  -RequireInstaller `
  -RequireSigning
```

Self-signed validation is useful for an internal packaging probe, but it does
not create public publisher trust or SmartScreen reputation.

## Planned ARM64 and package-manager tracks

The build and packaging scripts contain ARM64 and package-manager scaffolding,
but no ARM64 asset, WinGet package, or Scoop bucket is part of the current
Paramux release. Before enabling those tracks:

- build and test on real ARM64 Windows hardware
- publish matching architecture-specific checksums
- choose and bootstrap Paramux-owned package identifiers and manifests
- point all package metadata at `soldforaloss/paramux`
- verify install, upgrade, and uninstall behavior end to end

Old Winghostty package identifiers and repositories are predecessor history;
they are not Paramux distribution channels.

## Versioning and lineage

Current test tags use `v0.1.0-paramux.<revision>`. The exact inherited
Ghostty compatibility base remains recorded in
`dist/windows/release-metadata.json` for maintainers.

Paramux descends from Winghostty and Ghostty, but its app identity, executable,
release assets, paths, and repository target are Paramux-owned. The retained
`libghostty-vt` library keeps its upstream public name.
