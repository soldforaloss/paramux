# Developing Paramux

Paramux is a Windows-only native terminal for parallel agent workflows. The app
target is Win32, the default installed build output is `paramux.exe`, and the
retained secondary deliverable is `libghostty-vt`.

The codebase descends from Winghostty and Ghostty. Keep those names where they
identify upstream protocols, resources, libraries, or remotes; use Paramux for
the current app, executable, state paths, documentation, and repository.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing code here.

## Build and test

Use the standard Zig workflow from the repository root:

| Command | Description |
| --- | --- |
| `zig build` | Build the Win32 app and bundled resources |
| `zig build -Demit-exe=true` | Force-install `zig-out/bin/paramux.exe` and `paramux.com` |
| `zig build test` | Run the full Zig test suite |
| `zig build test -Dtest-filter=win32` | Run Win32-focused tests |
| `zig build test -Dtest-filter=scroll` | Run scroll/input regression tests |
| `zig build test -Dtest-filter=keybind` | Run keybinding/default-behavior tests |
| `zig build -Demit-lib-vt` | Build the retained `libghostty-vt` library |

For normal development, run the narrowest verification that covers the change,
then run `zig build` before finishing.

## Toolchain

This fork requires a Zig `0.15.x` release with patch version 2 or newer. The
check is enforced at compile time in `src/build/zig.zig::requireZig`: Zig
0.14.x, 0.16.x, 0.15.0, and 0.15.1 fail before user code runs. CI uses Zig
0.15.2 exactly.

If the dependency cache is empty or cannot hydrate automatically, seed it from
the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-zig-deps.ps1
```

The repository also provides `scripts/dev-windows.ps1` and
`scripts/dev-windows.cmd` to open a Windows-native shell with the expected
Visual Studio and Zig cache environment.

## Manual runtime harness

For manual app validation, use:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/interactive-win11.ps1
```

The harness launches the worktree executable with repo-local runtime state
under `.sandbox/win11/<worktree-id>/` instead of the normal
`%LOCALAPPDATA%\paramux` directory. Pass `-Rebuild` for a fresh executable,
`-ResetState` for a clean first-run repro, or `-OpenShell` for a shell with the
same sandbox environment.

For a mechanical startup smoke check under the same sandboxed environment:

```powershell
powershell -ExecutionPolicy Bypass -File test/windows/interactive-win11-smoke.ps1
```

## Runtime notes

- The application runtime is native Win32.
- The Windows renderer is OpenGL 4.3+ through WGL.
- The app executable and console launcher are `paramux.exe` and `paramux.com`.
- Normal user state is rooted at `%LOCALAPPDATA%\paramux`.
- Local automation reports the `paramux.windows.v2` schema.
- The repository retains `libghostty-vt` for Zig and C consumers.
- Cross-platform app packaging, GTK, and macOS app workflows have been removed
  and should not be reintroduced.

## Project layout

- `src/apprt/win32.zig` - Win32 application runtime and host integration.
- `src/apprt/win32_theme.zig` - theme tokens, DWM integration, accent helpers,
  and high-contrast behavior.
- `src/apprt/win32_*` - focused Win32 helpers extracted from the host runtime.
- `src/update/github_releases.zig` - GitHub Releases updater implementation.
- `src/renderer/OpenGL.zig` - WGL/OpenGL renderer backend.
- `src/config/Config.zig` - config options and defaults.
- `contrib/paramux/hooks/` - agent-attention integration examples.
- `dist/windows/` - Paramux icon, manifest, resource file, installer script,
  and portable PATH helper.
- `scripts/` - Windows packaging, dependency bootstrap, and development tools.

Upstream-derived areas intentionally kept close to Ghostty include
`src/terminal/`, `src/font/`, `src/input/`, `src/termio/`,
`src/shell-integration/`, `src/crash/`, and `libghostty-vt` surfaces.

## Formatting

- Zig: `zig fmt .`
- Other docs/resources: `prettier -w .`

## Manual validation checklist

If a change touches input, rendering, splits, sidebar state, or chrome:

1. Check wheel and precision-touchpad scrolling in a long buffer.
2. Check fast sustained output for flicker or dropped repaint.
3. Check the affected keybindings and mouse paths.
4. Check split focus and resize behavior when relevant.
5. Check agent-attention state, toast, or IPC behavior when relevant.
6. Launch `scripts/interactive-win11.ps1 -Rebuild`; add `-ResetState` for
   first-run behavior.

## Distribution status

The current user artifact is the public, unsigned x64 portable prerelease
`v0.1.0-paramux.8`. See [PACKAGING.md](PACKAGING.md) before changing release
copy or packaging behavior. Signed installers, WinGet, Scoop, and ARM64 release
artifacts remain future work.

## Scope and repository guard

When Windows-native behavior conflicts with inherited cross-platform behavior,
prefer the Windows-native result. Repository operations and pull requests must
target `soldforaloss/paramux`; the Winghostty and Ghostty repositories are
lineage/upstream references, not Paramux publish targets.
