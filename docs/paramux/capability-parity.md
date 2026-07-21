# Paramux capability parity

**Snapshot:** 2026-07-10  
**Compared with:** cmux, tmux, amirlehmam/wmux, openwong2kim/wmux  
**Status legend:** Implemented · Partial · Missing · Deliberately deferred · Unverified

## What parity means

Paramux aims to support the useful workflows people reach for in cmux, tmux,
and wmux while remaining a native Windows application. Parity does not require
copying another product's layout, Unix-only implementation details, or every
cloud/service feature. A workflow is only implemented when it works end to end
and has evidence in the current repo or runtime.

## Current matrix

| Workflow | Paramux status | Current evidence or gap |
| --- | --- | --- |
| Native terminal architecture | Implemented | Win32 + ConPTY + WGL/OpenGL 4.3 on the shared Ghostty core. |
| Tabs, splits, focus, resize, and zoom | Implemented | Independent panes, tab workspaces, split directions, drag resize, focus navigation, and pane zoom. |
| Mouse-first pane navigation | Implemented | Sidebar rows focus their panes; zoomed tabs move zoom to the selected row. |
| All-workspace navigation | Implemented | The `▾` and terminal context menus expose `Tabs / Workspaces...`; its overview lists every tab, pane count, active tab, and strongest attention state for direct numeric selection. |
| Live pane metadata | Implemented | cwd, git branch/dirty state, ports, textual attention state, and the latest bounded notification render in each active-tab sidebar row. |
| Per-pane agent attention | Implemented | Working/waiting/done/error drive pane rings, tab stripes, sidebar dots, toasts, and taskbar flash. Alerts survive focus/navigation and clear with deliberate terminal input. |
| Notification history / inbox | Missing | There is no in-app history or unread-jump workflow. |
| Agent hook adapters | Implemented | The portable package includes concrete, protocol-aware Claude Code, Codex CLI, Gemini CLI, and OpenCode adapters plus bounded contract tests. |
| Hookless agent detection | Missing | Paramux does not infer agent state from process/output heuristics when a CLI has no usable hook API or is not configured. |
| Local automation | Partial | List windows, safe actions, notify, read-pane, bounded send, and terminal-mode-aware send-key work end to end. Workspace naming, a complete process-launch contract, and versioned JSON-RPC compatibility remain incomplete. |
| IPC authentication | Partial | Sensitive methods are token-gated, but `new_window` is currently unauthenticated. |
| Configuration, themes, keybindings | Implemented | Ghostty-compatible config, theme import, key tables, direct native shortcuts, and a packaged/validated optional `Ctrl+B` tmux-prefix preset work. |
| Session continuity | Partial | Window/tab/split/profile/cwd layout restores; terminal processes, contents, scrollback, and agent resume state do not. |
| Native distribution | Partial | The local portable path guards its Paramux README, exact launcher VERSIONINFO, hooks, completion names, archive entries, checksum, and x64 baseline, and the live `v0.1.12` prerelease ships that guarded payload. The CLI manages the install lifecycle (`install`, `uninstall [--purge]`, checksum-verified in-place `update` from GitHub releases). Signed installer, public WinGet/Scoop, and verified ARM64 are not shipped. |
| Explorer shell integration | Implemented | "Open in Paramux" right-click verbs for folders, folder backgrounds, and drives (HKCU, per-user): registered by `install-paramux.ps1`, the Inno installer's optional task, or the in-app Settings toggle; opens the folder as a new window in the running instance via the single-instance forward. Windows 11 shows it under "Show more options" (top-level entries need MSIX, which the unsigned portable build does not ship). |
| Browser / CDP | Deliberately deferred | Explicit PRD non-goal for MVP, despite also appearing in the P1 list. |
| Managed SSH / remote workspaces | Deliberately deferred | Explicit PRD non-goal. Ordinary SSH inside a terminal remains available. |
| A2A channels / delegation | Deliberately deferred | Explicit PRD non-goal. |
| Performance, hardware, accessibility coverage | Unverified | Requires current Windows 10/11, x64/ARM64, GPU, DPI, and assistive-technology runs. |

## Required parity backlog

The next product work should close these in order:

1. **Finish fallback detection.** Add bounded process/output signals for agents
   whose hook API is unavailable or not configured.
2. **Finish the control contract.** Add versioned JSON-RPC compatibility,
   workspace naming, and the remaining create/split/launch workflow. Require
   the per-instance token for every mutation.
3. **Finish distribution.** Signed installer, WinGet, Scoop, x64, ARM64, and a
   package-level branding/security verifier.
4. **Add continuity fast-follows.** Notification history, agent-aware restore,
   scrollback/history persistence, image paste, and richer content panes.

## Product-contract conflicts to resolve

- The PRD calls browser/CDP both an MVP non-goal and a P1 fast-follow.
- The PRD requires mutating-method authentication while `new_window` remains
  unauthenticated.
- “Session persistence” needs a precise definition separating layout metadata,
  live PTYs, scrollback, and agent resume state.

Until those decisions are made, implementation evidence wins over optimistic
requirement wording.

## Primary competitor sources

Sources were reviewed on 2026-07-09:

- cmux: [repository](https://github.com/manaflow-ai/cmux),
  [API](https://cmux.com/docs/api),
  [session restore](https://cmux.com/docs/session-restore),
  [SSH](https://cmux.com/docs/ssh)
- tmux: [repository](https://github.com/tmux/tmux),
  [Getting Started](https://github.com/tmux/tmux/wiki/Getting-Started),
  [Advanced Use](https://github.com/tmux/tmux/wiki/Advanced-Use),
  [Control Mode](https://github.com/tmux/tmux/wiki/Control-Mode)
- amirlehmam/wmux: [repository](https://github.com/amirlehmam/wmux)
- openwong2kim/wmux: [repository](https://github.com/openwong2kim/wmux)

The repo and current runtime remain the source of truth for Paramux status.
