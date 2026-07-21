# Fleet soak harness: launches paramux, builds an N-agent workspace
# over IPC, then drives attention cycles + pane churn for -Hours,
# sampling process health every minute into a CSV. The 1.0 roadmap's
# crash-free-soak gate runs this at -Hours 72; -Minutes 3 is the
# self-test.
#
#   powershell -File scripts/soak-fleet.ps1 -Minutes 3     # self-test
#   powershell -File scripts/soak-fleet.ps1 -Hours 72      # the gate
param(
    [string]$Binary = "zig-out/bin/paramux.exe",
    [string]$Com = "zig-out/bin/paramux.com",
    [int]$Hours = 0,
    [int]$Minutes = 0,
    [int]$Panes = 8,
    [string]$OutCsv = "soak-results.csv"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Binary)) { Write-Error "Build first: zig build -Demit-exe=true" }
$totalMinutes = $Hours * 60 + $Minutes
if ($totalMinutes -le 0) { $totalMinutes = 3 }

$proc = Start-Process -FilePath $Binary -PassThru
Start-Sleep -Seconds 4
$versionLine = (& $Com version 2>$null | Select-Object -First 1)
if (-not $versionLine) { $versionLine = "unknown" }
"timestamp,minute,alive,workspaces,panes,paramux_mb,children,child_mb,notify_cycles,version,att_http" | Out-File $OutCsv -Encoding utf8
$servePort = 7891
$serveProc = Start-Process $Com -ArgumentList "serve", "--port=$servePort" -PassThru -WindowStyle Hidden
$ipcToken = ""
$tokenPath = Join-Path $env:LOCALAPPDATA "paramux\paramux-ipc-token"
if (Test-Path $tokenPath) { $ipcToken = (Get-Content $tokenPath -Raw).Trim() }

$states = @("working", "waiting", "done", "none")
$cycles = 0
try {
    # Build the fleet: panes-1 extra terminals in the first workspace.
    for ($i = 1; $i -lt $Panes; $i++) {
        & $Com perform-action new_split:auto | Out-Null
        Start-Sleep -Milliseconds 300
    }
    $ErrorActionPreference = "Continue"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $minute = 0
    while ($sw.Elapsed.TotalMinutes -lt $totalMinutes) {
        # Drive attention churn: a notify + an occasional pane cycle.
        foreach ($s in $states) {
            & $Com notify "--state=$s" "soak cycle $cycles" | Out-Null
            $cycles++
            Start-Sleep -Milliseconds 400
        }
        if ($cycles % 40 -eq 0) {
            # Churn: add a pane, then close it (undo-safe close path).
            & $Com perform-action new_split:auto | Out-Null
            Start-Sleep -Milliseconds 400
            & $Com perform-action close_surface | Out-Null
        }
        if ([math]::Floor($sw.Elapsed.TotalMinutes) -gt $minute) {
            $minute = [math]::Floor($sw.Elapsed.TotalMinutes)
            $proc.Refresh()
            $alive = -not $proc.HasExited
            $mb = if ($alive) { [math]::Round($proc.WorkingSet64 / 1MB, 1) } else { 0 }
            $statusRaw = if ($alive) { (& $Com status --no-header) } else { @() }
            if ($alive -and @($statusRaw).Count -eq 0) {
                # A sample can land while the app is mid-notify; settle and retry once.
                Start-Sleep -Milliseconds 500
                $statusRaw = (& $Com status --no-header)
            }
            $paneCount = @($statusRaw).Count
            $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue)
            $childMb = [math]::Round((($children | ForEach-Object { $_.WorkingSetSize } | Measure-Object -Sum).Sum / 1MB), 1)
            $attCode = 0
            if ($ipcToken) {
                try {
                    $attResp = Invoke-WebRequest -Uri "http://127.0.0.1:$servePort/attention" -Headers @{Authorization="Bearer $ipcToken"} -UseBasicParsing -TimeoutSec 5
                    $attCode = $attResp.StatusCode
                } catch { $attCode = -1 }
            }
            "$((Get-Date).ToString('s')),$minute,$alive,1,$paneCount,$mb,$($children.Count),$childMb,$cycles,$versionLine,$attCode" | Add-Content $OutCsv
            if (-not $alive) { throw "paramux exited during soak at minute $minute" }
        }
    }
    Write-Host "SOAK PASS: $totalMinutes minute(s), $cycles notify cycles, paramux alive throughout. Results: $OutCsv"
} finally {
    if ($serveProc -and -not $serveProc.HasExited) { Stop-Process -Id $serveProc.Id -Force -ErrorAction SilentlyContinue }
    if (-not $proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 1 }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}
