# E2E for the restore-commands contract, three phases:
#   A. default config     -> save_session must NOT capture commands
#   B. --restore-commands -> saved JSON carries the pane's child command
#   C. relaunch same name -> the command actually relaunches (ping.exe
#      appears under the new instance's process tree)
#
# Saves happen via `perform-action save_session` while the instance is
# alive, and phases end with a hard kill: the graceful-exit path sees
# zero windows after a close and would delete the state file (closing
# the last window means "forget this session"; quit/autosave persist).
#
# Uses an isolated --session-name so the operator's real session state
# is never touched. Needs a built zig-out and a free instance.
#
#   powershell -File scripts/e2e-restore-commands.ps1
param(
    [string]$Binary = "zig-out/bin/paramux.exe",
    [string]$Com = "zig-out/bin/paramux.com"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Binary)) { Write-Error "Build first: zig build -Demit-exe=true" }

$session = "e2erestore"
$stateFile = Join-Path $env:LOCALAPPDATA "paramux\session-state-$session.json"
$marker = "ping -t 127.0.0.1"

function Stop-Tree([int]$ProcessId) {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Tree $_.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Start-Phase([string[]]$ExtraArgs, [bool]$StartMarker) {
    $procArgs = @("--session-name=$session", "--confirm-close-surface=false") + $ExtraArgs
    $p = Start-Process $Binary -ArgumentList $procArgs -PassThru
    Start-Sleep 5
    if ($p.HasExited) { Write-Error "paramux exited immediately (phase args: $procArgs)" }
    if ($StartMarker) {
        & $Com send "$marker`r" | Out-Null
        Start-Sleep 3
    }
    & $Com perform-action save_session | Out-Null
    Start-Sleep 2
    return $p
}

$failures = @()

# Phase A: defaults never capture commands.
Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
$p = Start-Phase @() $true
if (-not (Test-Path $stateFile)) {
    $failures += "A: save_session wrote no session file ($stateFile)"
} elseif (Select-String -Path $stateFile -Pattern '"command"' -Quiet) {
    $failures += "A: default config captured a command (opt-in violated)"
} else {
    Write-Host "A OK: default save carries no command field"
}
Stop-Tree $p.Id
Start-Sleep 2

# Phase B: opt-in captures the running child command line.
Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
$p = Start-Phase @("--restore-commands=true") $true
if (-not (Test-Path $stateFile)) {
    $failures += "B: save_session wrote no session file"
} elseif (-not (Select-String -Path $stateFile -Pattern '"command"' -Quiet)) {
    $failures += "B: no command captured with restore-commands=true"
} elseif (-not (Select-String -Path $stateFile -Pattern "ping" -Quiet)) {
    $failures += "B: command field exists but does not contain the marker child"
} else {
    Write-Host "B OK: saved session carries the ping command line"
}
Stop-Tree $p.Id
Start-Sleep 2

# Phase C: relaunch restores and actually reruns the command.
$p = Start-Process $Binary -ArgumentList @(
    "--session-name=$session", "--confirm-close-surface=false", "--restore-commands=true"
) -PassThru
Start-Sleep 8
$pingFound = $false
$queue = New-Object System.Collections.Queue
$queue.Enqueue($p.Id)
while ($queue.Count -gt 0) {
    $parent = $queue.Dequeue()
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$parent" -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.Name -ieq "PING.EXE") { $script:pingFound = $true }
            $queue.Enqueue($_.ProcessId)
        }
}
if ($pingFound) {
    Write-Host "C OK: relaunch restarted the captured command (ping.exe alive)"
} else {
    $failures += "C: no ping.exe under the restored instance"
}
Stop-Tree $p.Id
Remove-Item $stateFile -Force -ErrorAction SilentlyContinue

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host "E2E RESTORE-COMMANDS PASS"
