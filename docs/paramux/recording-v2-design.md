# Recording v2 (design — v1 ships as `paramux record`)

v1 samples `read-pane` twice a second into an asciinema cast: honest,
dependency-free, but it cannot capture faster-than-500ms output or
styling. v2's bar:

- **Tap the PTY, don't sample it.** The right seam is termio's output
  path: a per-surface tee that appends raw VT bytes + timestamps to a
  ring/file when recording is armed. Exact bytes -> exact playback
  (colors, cursor movement, TUI redraws).
- **Arm/disarm over IPC** (`record start/stop --surface-id`) with the
  token gate, since raw output is pane content.
- **Cast v2 stays the container** (header + [t, "o", data] events, VT
  passthrough) so every asciinema player keeps working.
- **Bounded by default**: size cap (e.g. 64MB) with oldest-event drop
  and a truthful "[truncated]" marker event.
- Privacy: recording state must be VISIBLE in the pane's sidebar row
  (a red dot) the entire time; no silent capture, ever.

Est. shape: `src/termio/record_tee.zig` + surface arm/disarm plumbing
+ IPC verbs + the sidebar indicator. Post-v0.1.14 material.
