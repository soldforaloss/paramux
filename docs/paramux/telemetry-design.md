# Telemetry design (proposal — nothing is collected today)

Status: **design document only.** Paramux currently collects no
telemetry, phones home only when you run `paramux update` (a GitHub
releases API call), and this document is the contract any future
telemetry must honor before a line of it is written.

## Principles

1. **Off by default, opt-in only.** A fresh install sends nothing. The
   only switch is an explicit `telemetry = true` the user writes into
   their config; no prompt nags for it.
2. **Local first.** Everything proposed here works by writing to
   `%LOCALAPPDATA%\paramux\metrics.jsonl` that the USER can read,
   truncate, or ship themselves. A network sink, if ever added, is a
   second opt-in on top.
3. **Counts, never content.** Candidate signals are counters and
   durations: pane count, workspace count, feature-use tallies
   (find-across-panes invoked, layouts applied), crash counts, startup
   ms. Never terminal text, paths, titles, branch names, commands,
   hostnames, or anything an agent printed.
4. **Inspectable schema.** The exact event list lives in this file and
   `paramux doctor` prints whether telemetry is on and where the file
   is. Removing a signal is a patch; adding one is a PR that updates
   this document first.
5. **No third-party SDKs.** A JSONL file and (if the network sink ever
   lands) one HTTPS POST of that file's aggregate — auditable in one
   screen of Zig.

## Why even consider it

The project publishes performance receipts (docs/paramux/perf.md) and
fixes what it can measure. The honest gap: which fleet features earn
their maintenance cost. Local, user-readable tallies answer that for
users who choose to share them in an issue — which may be all the
telemetry this project ever needs.

## Crash minidumps (same fence)

Crash reports are the one place opt-in sharing is actively useful.
Current state: `paramux crash-report` lists LOCAL crash dumps (Sentry's
in-process handler writes them under the data folder); nothing
uploads. Any future "send this crash" flow must be per-crash consent
(a visible prompt naming the file), never a standing toggle, and the
dump must be inspectable before sending (`Open Data Folder` shows it).
Automatic upload is rejected by this document.

## Decision

Adopting even the local file is deferred until a concrete decision it
would inform exists. Until then this document is the fence: any PR
adding data collection that contradicts the principles above should be
rejected by citing it.
