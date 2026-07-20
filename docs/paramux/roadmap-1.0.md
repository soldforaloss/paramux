# The road to 1.0

What "stable" will mean for paramux, and the gates between here and a
`v1.0.0` tag. This is the contract for the stable channel — items move
from PLANNED to DONE only with receipts (tests, docs, or published
artifacts), and the list itself is versioned in PRs.

## Quality gates

| Gate | State | Receipt when done |
| --- | --- | --- |
| Signed installer | PLANNED | Authenticode-signed setup.exe on a release; SmartScreen-clean install video |
| WinGet + Scoop | PLANNED (blocked on signing) | `winget install paramux` works; docs/paramux/distribution.md flips |
| ARM64 artifact on every release | READY (manual dispatch) | Two-arch release pages, `update` picks the right arch |
| Session restore v2 | PARTIAL | Named sessions ship; restore of per-pane commands documented + tested |
| UIA text pattern | STARTED (HelpText live; snapshot layer ready) | Narrator reads scrollback; capability matrix row flips |
| Crash-free soak | PLANNED | 72h fleet soak (8 agents) with zero crashes, receipts in perf.md |
| Perf budgets in CI | DONE | test.yml perf gate (250ms CLI); extend with GUI cold-start once measurable headless |
| IPC fuzz + hardening | DONE | Fuzz suite in CI; pipe rejects remote + squatting; constant-time tokens |
| Copy/docs truthfulness | DONE (enforced) | Release-copy + site contracts in CI |
| Config stability | PLANNED | One release with zero breaking config renames; deprecation policy written |
| Localization readiness | NOTES (docs/paramux/i18n-notes.md) | Chrome strings behind one table; one proof-of-concept locale |

## Non-gates (explicitly not blocking 1.0)

- macOS/Linux ports (never; see scope guard).
- Built-in SSH/remote panes (design doc exists; post-1.0).
- Telemetry of any kind (fence stands regardless of version).

## Versioning after 1.0

Semver with a stable channel: `1.x.y` releases move through
prerelease → stable; `paramux update` gains `--channel` at that point.
Until every PLANNED gate above is DONE, releases stay `0.x` prereleases
and the README says so.
