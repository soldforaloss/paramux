# Announcement draft — "why paramux" (unpublished)

Draft copy for the first public announcement (blog post / HN / r/commandline),
held here until the maintainer decides the launch moment. Facts below
are verifiable against the repo at v0.1.14; update the version pins
when publishing.

---

## Paramux: a native Windows command center for parallel coding agents

I run several AI coding agents at once — Claude Code fixing tests in
one repo, Codex migrating a schema in another, Gemini triaging issues.
The terminal I wanted for that didn't exist on Windows: the agent-era
multiplexers are Electron/xterm.js ports, and classic terminals don't
know an "agent waiting for approval" from a compile loop.

So paramux is a fork of the native-Windows Ghostty work (winghostty)
that keeps the GPU terminal core — real OpenGL rendering, ConPTY panes,
13.8ms CLI cold start on my machine vs 48.2ms for Windows Terminal —
and builds the missing layer on top:

- **A sidebar that answers "who needs me?"** Every workspace and pane,
  always visible, with working/waiting/done/error states fed by real
  agent hooks (Claude Code, Codex CLI, Gemini CLI, OpenCode adapters
  ship in the box). Waiting panes show how long they've waited.
- **Attention that reaches you**: toasts with an Open Inbox button, an
  attention inbox (Ctrl+Alt+I), a while-you-were-away digest, token
  budget alarms, webhooks, and an on-attention command for your own
  automation.
- **Fleets as a first-class object**: `paramux run "claude -p '...'"`
  spawns a pane and prints its id; `paramux status --watch` is the
  fleet table; `paramux open .` recreates a project's committed
  `.paramux/layout` — panes, folders, commands, environment.
- **Native everything**: Win32 chrome, per-monitor DPI, jump lists,
  high contrast, UIA groundwork, x64 and native ARM64 builds.

It's an unsigned prerelease under heavy iteration — the README shows
the real capture, the capability matrix says exactly what's partial,
and the 1.0 roadmap lists the receipt-gated path to stable. MIT.

**Get it**: https://github.com/soldforaloss/paramux/releases — verify
the checksum, extract, run `install-paramux.cmd`, then `paramux`.

---

## Publishing checklist (maintainer)

- [ ] Update version pins + numbers to the release being announced.
- [ ] Re-run `scripts/bench-startup.ps1` the same day; quote fresh numbers.
- [ ] Screenshot/GIF current build (record-demo.ps1).
- [ ] Decide venues + timing; HN prefers plain "Show HN" framing.
- [ ] Expect and welcome "why not WSL/tmux" — the answer is the
      attention layer + native Windows, not terminal religion.
