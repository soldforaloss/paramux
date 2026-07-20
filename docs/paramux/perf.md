# Performance receipts

Measured by `scripts/bench-startup.ps1` on the maintainer's dev machine
(2026-07-20, paramux 1.3.2-dev+windows, Debug-build CLI unless noted). Regenerate after
performance-relevant changes; numbers are receipts, not promises.

| Metric | Value |
| --- | --- |
| CLI cold start, best of 5 (`paramux version`) | 13.8 ms |
| Windows Terminal (wt.exe -v), best of 5 | 48.2 ms |
| CLI cold start, average of 5 | 43 ms |
| GUI idle working set (5s after launch) | 133.4 MB |

The PRD targets: cold start under 500 ms, idle under 150 MB (release
builds on real hardware). Release-build numbers belong here once
measured on the target machine.