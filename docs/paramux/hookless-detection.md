# Hookless agent detection (design)

The third 0.2.0 gate (see roadmap-1.0.md): infer attention states for
agent CLIs that have no usable hook API or are simply not configured,
without ever reading meaning into pane content.

## Constraints (non-negotiable)

- **Opt-in** (`agent-detect = auto` config; default off). The hooks
  path stays primary — detection never overrides an explicit hook
  signal (hooks always win within their session).
- **Bounded signals only.** Process identity and output *timing* —
  never output *content* parsing (no regexing pane text for "waiting
  for approval"; that is both fragile and a privacy cliff the
  telemetry fence exists to prevent, even locally).
- **No polling storms.** Piggyback existing machinery: the child-exit
  watchdog (already drives the attention pipeline), the ports tick,
  and the PTY read path's own activity timestamps.

## Signals

| Signal | Source | Inference |
| --- | --- | --- |
| Known agent child present | child-process walk (claude/codex/gemini/opencode image names) | pane is "agent-capable"; enables the rest |
| Output flowing (bytes in the last 2s) | termio read path timestamp | `working` |
| Output quiet ≥ 10s with agent alive | same timestamp | `waiting` (the agent is probably blocked on input) |
| Agent child exited, code 0 | child-exit watchdog | `done` |
| Agent child exited, code ≠ 0 | child-exit watchdog | `error` |

The quiet threshold matches the focus-follows idle gate (10s) so the
two features share one notion of "idle".

## Precedence

`hook signal (explicit) > detection (inferred) > none`. A pane that
has received ANY hook-driven state in its lifetime marks itself
hook-managed and detection stays out permanently — mixed signals are
worse than late ones.

## Slices

1. Config knob + child-identity walk + working/quiet inference,
   sidebar shows inferred states with a hollow dot (visually distinct
   from hook-driven solid dots).
2. Exit-code mapping through the existing watchdog.
3. Doctor line ("agent detection: auto, 2 panes inferred") + docs.

Nothing here is scheduled within a specific release; the gate closes
when slices 1-2 ship with an E2E that runs a fake agent (a script
that sleeps and exits) through the inference path.
