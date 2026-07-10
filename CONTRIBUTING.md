# Contributing to Paramux

Thanks for working on Paramux.

`soldforaloss/paramux` is currently a private Windows-first repository.
Invited collaborators can use its Issues and pull requests for focused,
actionable work. Bug reports should be reproducible; feature requests should
state the user problem and stay within the Windows product scope.

Paramux descends from Winghostty and Ghostty. That lineage remains relevant to
the terminal core, but repository operations, product identity, commands,
paths, release links, and pull requests must target
[`soldforaloss/paramux`](https://github.com/soldforaloss/paramux).

## Contribution rules

1. Understand and verify the change end to end before calling it done.
2. Prefer Windows-native behavior when it conflicts with inherited
   cross-platform behavior.
3. Keep scope tight and start with the narrowest reliable Zig test.
4. Preserve `libghostty-vt`; it remains a supported retained deliverable.
5. Keep docs, packaging, and user-visible strings aligned with the Paramux
   identity.
6. Keep current distribution claims truthful: today that means the private,
   unsigned x64 portable prerelease. Signed installers, WinGet, Scoop, and
   ARM64 releases are planned rather than current.

## Before opening a pull request

- Read [HACKING.md](HACKING.md) for build, test, and runtime commands.
- Read any applicable `AGENTS.md` files before editing.
- If you use AI assistance, you are responsible for understanding and
  reviewing the final change. See [AI_POLICY.md](AI_POLICY.md).
- Confirm the pull request target is `soldforaloss/paramux`, not either
  predecessor repository.

## Validation

Prefer the narrowest command that covers your change:

- `zig build test -Dtest-filter=win32`
- `zig build test -Dtest-filter=scroll`
- `zig build test -Dtest-filter=keybind`
- `zig build`
- `zig build -Demit-exe=true`

If the change touches input, rendering, window chrome, process startup,
packaging, agent attention, IPC, or update behavior, do a manual Windows check
as well:

1. Launch `zig-out/bin/paramux.exe`.
2. Verify the affected behavior on Windows.
3. Re-check the adjacent behavior that the change could reasonably affect,
   such as scrolling, keybindings, split focus, repainting, IPC, or packaging.

## Scope guard

This fork does not preserve upstream macOS or GTK app surfaces. Do not
reintroduce:

- macOS application packaging or Xcode workflows
- GTK, Wayland, or X11 app-runtime logic
- Linux desktop packaging such as Flatpak or Snap

## Pull request notes

- Keep changes minimal and focused.
- Include exact validation commands and results.
- Call out risks or follow-up work if a change is intentionally partial.
- Do not claim a distribution channel or platform is supported until its
  release artifacts and install path have been verified.
