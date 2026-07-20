# Running multiple paramux instances

One paramux instance is one window-set, one IPC pipe, one saved
session. To run several truly independent instances — say a work fleet
and a personal fleet — give each its own class and session name.

## The recipe

1. **Pick a class per instance.** The `--class` argument (also honored
   by every CLI verb) namespaces the IPC pipe and single-instance
   coordination:

   ```powershell
   paramux --class=work
   paramux --class=lab
   ```

2. **Pair it with a session name** so saved layouts stay separate.
   Each class should use its own config file carrying:

   ```
   session-name = work
   ```

   which persists to `session-state-work.json` instead of the shared
   default.

3. **Target CLI verbs at the right instance:**

   ```powershell
   paramux status --class=work
   paramux run --class=lab "claude -p 'triage the queue'"
   paramux send --class=work --all-panes "git fetch"
   ```

   Verbs without `--class` resolve the default instance.

## What stays shared

- `%LOCALAPPDATA%\paramux` (config default, layouts.json slots, themes,
  update staging) is per-user, not per-instance. Layout slots are a
  deliberate shared library — save in one fleet, apply in another.
- `paramux update` updates the binary every instance runs.

## What stays separate

- The IPC pipe and token handshake (per class).
- Saved session shape (per `session-name`).
- Windows, workspaces, attention state, broadcast toggles (per process).

Agent hooks inside panes need no changes: `PARAMUX_SURFACE_ID` routes
`paramux notify` to the exact pane regardless of class.
