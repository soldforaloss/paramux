# One-command launcher for the crash-free-soak gate: runs
# soak-fleet.ps1 detached (survives closing this console) with a
# transcript, per-minute CSV, and a DONE marker holding the verdict.
#
#   powershell -File scripts/start-soak.ps1              # the 72h gate
#   powershell -File scripts/start-soak.ps1 -Hours 1     # shorter run
#   powershell -File scripts/start-soak.ps1 -Minutes 2   # wrapper self-test
#
# Watch progress:  Get-Content soak-runs\soak-<stamp>\soak.log -Tail 5 -Wait
# Verdict:         soak-runs\soak-<stamp>\DONE.txt (absent = still running)
param(
    [int]$Hours = 72,
    [int]$Minutes = 0,
    [int]$Panes = 8,
    [string]$OutDir = "soak-runs"
)
$ErrorActionPreference = "Stop"

$soakScript = Join-Path $PSScriptRoot "soak-fleet.ps1"
if (-not (Test-Path $soakScript)) { Write-Error "soak-fleet.ps1 not found next to this script" }
if (-not (Test-Path "zig-out/bin/paramux.exe")) { Write-Error "Build first: zig build -Demit-exe=true" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $OutDir "soak-$stamp"
New-Item -ItemType Directory -Force $runDir | Out-Null
$runDirFull = (Resolve-Path $runDir).Path
$log = Join-Path $runDirFull "soak.log"
$csv = Join-Path $runDirFull "soak-results.csv"
$marker = Join-Path $runDirFull "DONE.txt"
$soakFull = (Resolve-Path $soakScript).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# -Minutes overrides -Hours for wrapper self-tests.
$duration = if ($Minutes -gt 0) { "-Hours 0 -Minutes $Minutes" } else { "-Hours $Hours" }

# The detached shell runs the soak, then writes the verdict marker.
$inner = @(
    "Set-Location '$repoRoot';",
    "`$ErrorActionPreference = 'Continue';",
    "& powershell -NoProfile -ExecutionPolicy Bypass -File '$soakFull' $duration -Panes $Panes -OutCsv '$csv' > '$log' 2>&1;",
    "if (`$LASTEXITCODE -eq 0 -and (Select-String -Path '$log' -Pattern 'SOAK PASS' -Quiet)) {",
    "  'PASS ' + (Get-Date -Format s) | Out-File '$marker' -Encoding utf8",
    "} else {",
    "  'FAIL ' + (Get-Date -Format s) + ' (see soak.log)' | Out-File '$marker' -Encoding utf8",
    "}"
) -join " "

Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $inner
) | Out-Null

$durationLabel = if ($Minutes -gt 0) { "$Minutes minute(s)" } else { "$Hours hour(s)" }
Write-Host "Soak launched detached: $durationLabel, $Panes panes."
Write-Host "  log:     $log"
Write-Host "  csv:     $csv"
Write-Host "  verdict: $marker (written when the run ends)"
