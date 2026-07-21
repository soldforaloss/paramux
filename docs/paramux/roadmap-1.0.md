# The road to 1.0

What "stable" will mean for paramux, and the gates between here and a
`v1.0.0` tag. This is the contract for the stable channel — items move
from PLANNED to DONE only with receipts (tests, docs, or published
artifacts), and the list itself is versioned in PRs.

## Quality gates

| Gate | State | Receipt when done |
| --- | --- | --- |
| Signed installer | PLANNED (decision pack: signing-decision.md) | Authenticode-signed setup.exe on a release; SmartScreen-clean install video |
| WinGet + Scoop | PLANNED (blocked on signing) | `winget install paramux` works; docs/paramux/distribution.md flips |
| ARM64 artifact on every release | DONE (manual dispatch each release since v0.1.8) | Two-arch release pages, `update` picks the right arch |
| Session restore v2 | DONE | Named sessions + opt-in `restore-commands` capture/relaunch, 4-phase E2E (`e2e-restore-commands.ps1`), session-schema.md |
| UIA text pattern | DONE | TextPattern with line/word/page units, live TextChanged, wide-glyph geometry; Narrator checklist in accessibility-testing.md; parity rows flipped |
| Crash-free soak | HARNESS READY (72h run pending) | `soak-fleet.ps1` gated on /attention probes; the 72h run with zero crashes, receipts in perf.md |
| Perf budgets in CI | DONE | test.yml perf gate (250ms CLI); extend with GUI cold-start once measurable headless |
| IPC fuzz + hardening | DONE | Fuzz suite in CI; pipe rejects remote + squatting; constant-time tokens; busy-pipe deadline retries |
| Copy/docs truthfulness | DONE (enforced) | Release-copy + site contracts in CI; remote audit each release |
| Config stability | PLANNED | One release with zero breaking config renames; deprecation policy written (config-deprecation-policy.md) |
| Localization readiness | DONE | `win32_strings` table covers all static chrome + composed labels; de-DE ships behind `ui-language`; runtime smoke in the release sweep |

## The 0.2.0 line (decided 2026-07-21)

Fifteen 0.1.x releases hardened the foundation (accessibility, fleet
CLI, layouts as files, the attention lifecycle, i18n, the release
train). `v0.2.0` is **earned, not declared**: it ships when the
remaining "Missing" rows of capability-parity.md close —

1. **Notification history / inbox persistence** — the attention
   inbox survives restarts and the history is queryable (the current
   8-transition in-memory timeline becomes a bounded on-disk log).
2. **`new_window` IPC auth design** — the naive token gate has been
   tried and reverted twice: transient `-e` processes clobber the
   shared token file and multiple paramux processes share one pipe
   name, so gating regresses `-e` fleet dedup into duplicate
   windows. Closing this row means the real design (per-instance
   token discovery or per-process pipe naming), not a predicate
   flip. Interim stance, documented: the token file is same-user
   readable anyway, so the open method adds no same-user attack
   surface beyond what a local process already has.
3. **Hookless agent detection (bounded)** — process/output signals
   for agents with no usable hook API, opt-in and documented.

Until those land with receipts, releases stay 0.1.x. No milestone
bumps for accumulation alone.

## Non-gates (explicitly not blocking 1.0)

- macOS/Linux ports (never; see scope guard).
- Built-in SSH/remote panes (design doc exists; post-1.0).
- Telemetry of any kind (fence stands regardless of version).

## Versioning after 1.0

Semver with a stable channel: `1.x.y` releases move through
prerelease → stable; `paramux update` gains `--channel` at that point.
Until every PLANNED gate above is DONE, releases stay `0.x` prereleases
and the README says so.
