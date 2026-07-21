# Performance receipts

Measured by `scripts/bench-startup.ps1` on the maintainer's dev machine
(2026-07-21, paramux 0.1.14, packaged ReleaseFast x64 binary). Regenerate after
performance-relevant changes; numbers are receipts, not promises.

| Metric | Value |
| --- | --- |
| CLI cold start, best of 5 (`paramux version`) | 12.4 ms |
| Windows Terminal (wt.exe -v), best of 5 | 49.6 ms |
| CLI cold start, average of 5 | 14.5 ms |
| GUI idle working set (5s after launch) | 118.3 MB |

The PRD targets: cold start under 500 ms, idle under 150 MB (release
builds on real hardware). Release-build numbers belong here once
measured on the target machine.