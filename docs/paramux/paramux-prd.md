# paramux — Product Requirements Document (MVP)

**Owner:** Tommy Rush
**Status:** Working draft v0.2
**Last updated:** July 7, 2026
**Scope:** Lean-wedge MVP. Match cmux's core UX natively on Windows; beat the existing web-rendered wmux ports on feel, not feature count.

---

## 1. Summary

The paramux MVP is a native Windows terminal for running multiple AI coding agents in parallel. It provides split panes and tabbed workspaces, a vertical tab sidebar showing live per-pane state, and a color-coded attention system that tells you at a glance which agent is working, waiting, done, or errored — without clicking through every pane.

## 2. Target user & primary use case

A Windows developer running 2–5 coding-agent CLIs at once (Claude Code, Codex, Gemini CLI, OpenCode) — e.g., Claude Code building a backend in one pane, Codex on the frontend in another, and tests running in a third — who needs to (a) keep them organized and (b) know instantly which one is blocked, finished, or errored, without cycling through panes.

## 3. Goals / Non-goals

**Goals (MVP)**
- Native Windows app: fast cold start, low idle memory, and GPU-accelerated text via a real terminal core (libghostty/winghostty) — not xterm.js in a WebView.
- Split panes + tabbed workspaces with a cmux-style vertical sidebar.
- Live per-pane metadata: shell/agent label, git branch, cwd, open ports, latest notification text.
- The agent-attention system: color-coded pane/tab states + native Windows toast + taskbar flash.
- Basic agent detection for the major CLIs.
- Minimal scriptability: a named-pipe JSON-RPC surface plus a CLI.
- Signed, one-command install.

**Non-goals (explicitly deferred to keep it lean)**
- Agent-to-agent messaging / channels.
- Cloud or remote agent VMs.
- Built-in browser panel / CDP automation.
- Session persistence across reboot. *(Note: even cmux ships without session restore today — this is a fast-follow, not MVP.)*
- Mobile companion, extension/marketplace SDK, SSH workspaces.
- Windows-Terminal-profile-provider integration.

## 4. Architecture

Mirror of cmux's shape, retargeted to Windows: **native shell + shared terminal core + agent layer.**

```
┌──────────────────────────────────────────────────┐
│ paramux app  (native Win32 / WinUI 3)             │
│  window chrome · tab sidebar · pane manager       │
│  attention / notification controller              │
├──────────────────────────────────────────────────┤
│ Terminal core                                     │
│  libghostty-vt  (VT parse + screen state)         │
│  GPU text renderer  (D3D11 / WGL-OpenGL)          │
│  ConPTY host  (one PTY per pane)                  │
│  shell integration  (OSC 133 / OSC 7 / 9/99/777)  │
├──────────────────────────────────────────────────┤
│ Agent layer                                       │
│  agent detection · per-pane state machine         │
│  git / cwd / port watchers  → sidebar             │
│  notification bridge  (toast + taskbar flash)     │
├──────────────────────────────────────────────────┤
│ Control surface                                   │
│  named pipe (\\.\pipe\paramux) · JSON-RPC + CLI   │
└──────────────────────────────────────────────────┘
```

**Key architectural decision (locked):** build the terminal-core layer on **winghostty** (native Win32 + Ghostty core + WGL renderer + ConPTY, MIT and license-compatible) rather than reimplementing VT parsing and GPU text rendering. This concentrates effort on the agent layer and sidebar — the actual differentiator — and de-risks the hardest part. Guardrail: keep the terminal dependency behind a thin interface so a switch to libghostty-vt directly (a fresh WinUI 3 + DirectX 11 host) stays a fallback if winghostty stalls.

## 5. Functional requirements

Each requirement has an acceptance criterion. **P0 = MVP**; **P1 = fast-follow** (listed for roadmap clarity, not built first).

**FR-1 (P0) — Native terminal pane.** A pane runs a Windows shell (PowerShell / CMD / pwsh / bash) over ConPTY, parsed by libghostty-vt, GPU-rendered.
- *Accept:* running the `claude` / `codex` / `gemini` CLIs renders correctly (colors, cursor shapes, wide/CJK/emoji, redraws) with no visible lag at high output rates.

**FR-2 (P0) — Splits & tabs.** Split any pane horizontally or vertically; multiple tabbed workspaces.
- *Accept:* keyboard + mouse split/close/resize works; layout persists for the app session (not across reboot).

**FR-3 (P0) — Vertical sidebar with live metadata.** Per pane: shell/agent label, git branch + dirty state, cwd, listening ports, latest notification text — updated in real time via shell-integration hooks.
- *Accept:* switching branches, changing directory, or opening a port updates the sidebar within ~1s; metadata set matches what cmux/wmux expose.

**FR-4 (P0) — Agent-attention system.** Color-coded pane ring + tab indicator: *working / waiting-for-input / done / error*. Fires a Windows toast + taskbar flash on transition to waiting/done/error.
- *Accept:* with 4 agents running, a user looking away is notified when any goes to waiting/done/error and can identify **which** pane from the sidebar without cycling panes. This is the headline feature and must feel reliable.

**FR-5 (P0) — Agent detection & state.** Detect Claude Code, Codex CLI, Gemini CLI, and OpenCode in a pane and drive FR-4. Use agent hooks where available (e.g., Claude Code Notification/Stop hooks) plus output-idle/throughput heuristics; support OSC 9/99/777 and a `paramux notify` CLI as fallbacks.
- *Accept:* Claude Code "waiting for input" and "finished" transitions are reflected within ~2s; a manual `paramux notify "msg"` produces a visible toast.

**FR-6 (P0) — Config.** Ghostty-compatible `key = value` config for themes and keybindings; import Ghostty and Windows Terminal themes.
- *Accept:* a Ghostty theme file renders; core keybindings are rebindable; the packaged optional tmux-prefix preset validates and loads.

**FR-7 (P0) — Control surface (CLI + named pipe).** `\\.\pipe\paramux` JSON-RPC: create workspace, split pane, send keys, read pane content, set notification. Plus a `paramux` CLI.
- *Accept:* a script can open a workspace, split it, launch an agent, and read output; mutating methods are auth-gated with a per-instance token.

**FR-8 (P0) — Packaging & install.** Signed installer + portable ZIP; winget + Scoop.
- *Accept:* `winget install ...` works, and a signed build is not hard-blocked by SmartScreen.

**P1 fast-follow (not MVP):** session/layout persistence including reboot survival; built-in browser panel; clickable links + image paste; richer scriptability; interactive onboarding walkthrough. *(This is the path to feature parity with the wmux ports once the native wedge is landed.)*

## 6. Non-functional requirements

- **Performance (the whole point).** Cold start noticeably faster and idle memory noticeably lower than the web-rendered competitors (Electron and Tauri/xterm.js alike). Establish concrete targets against a measured baseline — provisional: cold start < 500 ms; idle < 150 MB for a single pane. Validate, then publish as a differentiator.
- **Platforms.** Windows 10 1809+ (ConPTY) and Windows 11; x64 + ARM64 (winghostty already supports both).
- **Reliability.** The attention system must not miss or falsely fire state changes under load — it is the core value.
- **Accessibility.** Partial UI Automation at MVP (parity with winghostty's current state), with scrollback/screen-reader coverage a known, documented gap.
- **Security.** Named-pipe mutating methods require a per-instance token; the control surface is not network-exposed by default.

## 7. UX notes

- **Sidebar-first.** The vertical tab sidebar is the primary organizer (cmux's model); each row carries the FR-3 metadata and the FR-4 color state.
- **One color language.** Pick a single palette for working/waiting/done/error and use it identically on the pane ring, the tab, and the sidebar dot.
- **Prefix-key decision (locked).** cmux deliberately avoids tmux-style prefix keys; the wmux ports keep Ctrl+B for tmux muscle memory. **Decision:** direct chorded shortcuts by default (cmux-like) for the native feel, plus an optional tmux-prefix mode — WSL/tmux migrants can enable Ctrl+B.

## 8. Milestones (verifiable exit criteria)

- **M0 — Terminal renders.** A native window runs one ConPTY shell via the (winghostty-based) core. *Exit: run Claude Code in it and interact normally.*
- **M1 — Panes & tabs.** Splits + tabbed workspaces. *Exit: 4 panes across 2 tabs, resizable.*
- **M2 — Sidebar metadata.** FR-3 live data. *Exit: branch/cwd/port changes reflected in < 1s.*
- **M3 — Attention system.** FR-4. *Exit: blind test — a user identifies the blocked agent among 4 without cycling panes.*
- **M4 — Agent detection + notifications.** FR-5. *Exit: Claude Code waiting/finished → toast within ~2s.*
- **M5 — Control surface.** FR-7. *Exit: a script drives a full workspace end-to-end.*
- **M6 — Package & launch.** FR-8. *Exit: signed winget install works; Show HN goes live.*

## 9. Decisions (locked) & open items

**Locked**
- **Terminal core:** build on winghostty (native Win32 + Ghostty + GPU rendering + ConPTY); a thin interface keeps libghostty-vt-direct as a fallback.
- **UI framework:** Win32 (follows winghostty).
- **License:** MIT.
- **Keybindings:** direct shortcuts by default + optional tmux-prefix mode.
- **Name:** paramux.

**Still open**
- **cmux-protocol compatibility:** whether to make the named-pipe protocol cmux/wmux-compatible so existing ecosystem tooling works out of the box. Worth it if cheap — amirlehmam/wmux already matches cmux's protocol, so matching it widens compatibility.
- **Performance targets:** the provisional numbers in §6 need validation against a real baseline before they're published.

---

### References

- cmux (feature set, native/no-Electron stance): https://github.com/manaflow-ai/cmux
- winghostty (native Win32 runtime, WGL renderer, x64+ARM64, signing): https://github.com/amanthanvi/winghostty
- Ghostty / libghostty-vt (Windows supported as a libghostty target): https://github.com/ghostty-org/ghostty
- Ghostty Windows-support discussion (WinUI 3 + DirectX 11 host prototype): https://github.com/ghostty-org/ghostty/discussions/2563
- wmux (amirlehmam — sidebar metadata, notifications, protocol compatibility, named-pipe API): https://github.com/amirlehmam/wmux
- wmux (openwong2kim — ConPTY, xterm.js, per-session token auth): https://github.com/openwong2kim/wmux
