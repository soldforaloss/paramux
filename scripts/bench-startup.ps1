# Measures paramux cold-start CLI latency and idle memory, writing the
# receipts to docs/paramux/perf.md. Run after `zig build -Demit-exe=true`:
#
#   powershell -File scripts/bench-startup.ps1
#
# CLI latency uses `paramux version` (process spawn -> exit), the honest
# floor for any `paramux <verb>`. GUI idle memory samples paramux.exe's
# working set 5s after launch, then closes it.
param(
    [string]$Binary = "zig-out/bin/paramux.com",
    [string]$OutFile = "docs/paramux/perf.md",
    [int]$Runs = 5,
    # CI budget: nonzero fails the script when median CLI cold-start
    # exceeds this many milliseconds. 0 = measure only.
    [int]$MaxCliMs = 0,
    # CI mode skips the GUI memory sample (no interactive desktop).
    [switch]$CliOnly
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Binary)) { Write-Error "Binary not found: $Binary" }

# CLI cold-start: N runs of `paramux version`.
$cliTimes = @()
for ($i = 0; $i -lt $Runs; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Binary version | Out-Null
    $sw.Stop()
    $cliTimes += $sw.Elapsed.TotalMilliseconds
}
$cliMin = [math]::Round(($cliTimes | Measure-Object -Minimum).Minimum, 1)
$cliAvg = [math]::Round(($cliTimes | Measure-Object -Average).Average, 1)

# GUI idle memory: launch, wait, sample, close.
$exe = Join-Path (Split-Path (Resolve-Path $Binary)) "paramux.exe"
$guiRow = "| GUI idle working set (5s after launch) | not sampled (paramux.exe missing) |"
if ($CliOnly) { $guiRow = "| GUI idle working set | skipped (-CliOnly) |" }
if ((-not $CliOnly) -and (Test-Path $exe)) {
    $proc = Start-Process -FilePath $exe -PassThru
    Start-Sleep -Seconds 5
    try {
        $proc.Refresh()
        $ws = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        $guiRow = "| GUI idle working set (5s after launch) | $ws MB |"
    } finally {
        if (-not $proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 1 }
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$ver = (& $Binary version | Select-Object -First 1)
$content = @"
# Performance receipts

Measured by ``scripts/bench-startup.ps1`` on the maintainer's dev machine
($stamp, $ver, Debug-build CLI unless noted). Regenerate after
performance-relevant changes; numbers are receipts, not promises.

| Metric | Value |
| --- | --- |
| CLI cold start, best of $Runs (``paramux version``) | $cliMin ms |
| CLI cold start, average of $Runs | $cliAvg ms |
$guiRow

The PRD targets: cold start under 500 ms, idle under 150 MB (release
builds on real hardware). Release-build numbers belong here once
measured on the target machine.
"@
$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
if (-not $CliOnly) { [System.IO.File]::WriteAllText($OutFile, $content, (New-Object System.Text.UTF8Encoding $false)) }
if (-not $CliOnly) { Write-Host "Wrote $OutFile (CLI best $cliMin ms, avg $cliAvg ms)." }

if ($MaxCliMs -gt 0) {
    if ($cliAvg -gt $MaxCliMs) {
        Write-Error "CLI cold-start average ${cliAvg}ms exceeds the ${MaxCliMs}ms budget."
    }
    Write-Host "Perf budget OK: average ${cliAvg}ms <= ${MaxCliMs}ms."
}
