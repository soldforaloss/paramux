# Paramux UX redesign

Status: adopted 2026-07-10. Phase 1 ships first; later phases land in order
unless the PRD says otherwise. References studied (docs/READMEs/reviews, not
forks): tmux + zellij/byobu, cmux (manaflow-ai — the AI-agent terminal
manager), wmux (both actively developed Windows ports), Windows Terminal,
iTerm2.

## Why: the current experience fails three ways

1. **You can lose a terminal.** The sidebar only lists the ACTIVE tab's
   panes. Pressing `+` (new tab) replaces the whole sidebar and the whole
   content area; the terminal you were using vanishes from every visible
   surface. Getting back requires knowing that the small tab button at the
   top is where it went. This is the single worst defect: losing sight of a
   running agent is the one thing a parallel-agent terminal must never do.
2. **Splitting is confusing.** `+` (new tab), `◫` (split right), and `⊟`
   (split down) sit side by side and look alike, but one of them navigates
   away while the other two edit the current layout. The cost of a mis-click
   is wildly asymmetric and the icons don't communicate that.
3. **Navigation is inconsistent.** Tabs are switched at the top, panes at
   the left, zoom hides panes (now at least labeled), and nothing shows a
   stable address for anything. There is no cheap "back to where I just was".

## What the references agree on

Every reference solves orientation the same way — **one persistent,
always-complete map of every terminal, with visible state per item**:

- tmux: the status bar lists every window with a stable index plus flags
  (`*` current, `-` last, `#` activity, `Z` zoomed). Losing a terminal is
  structurally impossible; `prefix l`/`;` toggle to the last window/pane.
  Its one failure — invisible chords/discoverability — is what zellij fixed
  with a context-aware hint bar, on by default, dismissible.
- cmux: a persistent left sidebar of vertical "workspace" cards (branch,
  cwd, ports, last notification) is the whole navigation model. Its creator
  explicitly abandoned horizontal tabs ("couldn't even read the titles").
  Attention is redundant (pane ring + glowing row + badge + toast) and
  `Cmd+Shift+U` jumps to the most recent unread. Top user complaints:
  focus-loss bugs and ordinals that remap on reorder — budget against both.
- wmux / Windows Terminal / iTerm2: agent-control verbs over a pipe (the
  model paramux already has), a single labeled "new" affordance with
  modifier grammar, MRU Ctrl+Tab switching, middle-click close everywhere,
  dimmed inactive splits, and honest session-restore banners. Windows
  Terminal ships zero session persistence — restore is the wedge.

## The model

Vocabulary: a **workspace** is what the code calls a tab — one task/agent
plus its supporting splits. A **pane** is one terminal. Window > workspace >
pane, rigid and shallow, exactly one visible hierarchy.

**The sidebar is the product.** It always shows every workspace and every
pane, top to bottom, with live state. The content area shows the active
workspace's panes; the tab strip stays (familiar, drag-reorder, overflow
menu) but is secondary chrome. Nothing that exists is ever invisible.

```
 1 · api refactor        ●2   <- workspace header: ordinal, title, attention
     claude   main* api       <- pane rows: title + branch/cwd/ports or
     waiting for approval        attention words (existing metadata)
 2 · docs site
     claude   done  site
     cmd      site
 + New workspace              <- labeled; creation is deliberate, never a mis-click
```

## Phase 1 — the unified sidebar (ships now)

- Sidebar lists ALL workspaces as headers with their pane rows beneath.
  Headers: 1-based ordinal (stable address, matches `ctrl+N` goto_tab),
  title, aggregated attention dot, hover ✕ close, middle-click close.
  Active header gets the accent stripe; inactive panes render dimmed but
  fully readable.
- Click a pane row anywhere → switch workspace AND focus that pane. One
  click returns to any terminal from anywhere. Click a header → switch.
- `+ New workspace` is a labeled row at the bottom of the tree — creation
  becomes deliberate; the icon `+` in the strip remains for muscle memory.
- Wheel scrolling when the tree outgrows the window.
- Drag-to-rearrange stays scoped to rows of the active workspace (cross-
  workspace move is phase 2 plumbing).
- Zoom labels, hover close, drag grips, first-run hints all carry over.

Acceptance: open a new workspace while an agent runs — the agent's row is
still on screen, labeled, one click away. That failure mode is dead.

## Phase 2 — navigation muscle memory

- **Last-workspace / last-pane toggle** (tmux `l`/`;`): one chord bounces
  between your two working contexts. Bind by default.
- **Jump to most recent unread attention** (cmux `Cmd+Shift+U`): one chord,
  plus making the existing notification words a queue.
- MRU Ctrl+Tab switcher overlay (hold-modifier list, Windows Terminal
  style) instead of positional cycling.
- Ordinals bind to workspace identity, not list position (cmux's top
  complaint) — reorder must not remap `ctrl+1`.
- Unify vocabulary in every menu/label: workspace, split, pane.

## Phase 3 — discoverability that comes off

- zellij-style hint strip: a one-line bar showing the currently valid
  actions ("Enter accept · Esc cancel" during confirms; "drag to rearrange"
  while dragging; prefix hints while the tmux-prefix preset is armed).
  Dismissible once internalized, like training wheels.
- Command palette already exists (`Ctrl+Shift+P`); index every menu action
  in it so the long tail is searchable.
- Split affordances that look like their result (`|` / `—` glyph pairing).

## Phase 4 — the wedge

- **Session restore**: workspaces, panes, cwds, titles across relaunch
  (Windows Terminal has nothing here; wmux's daemon and iTerm2's honest
  "Session Restored" banner set the bar). Scrollback restore later.
- Cross-workspace pane move (drag a row onto another workspace header).
- Duplicate pane/workspace inheriting cwd.

## Non-goals (unchanged from the PRD)

No Electron/WebView rendering, no A2A messaging, no cloud/SSH scope creep.
The CLI keeps the wmux/cmux verb family (`send`, `read-pane`,
`perform-action`, `notify`, bare words, `+` accepted for compat) — no
tmux-style attach semantics.
