# de-DE runtime smoke: boots the GUI with `ui-language = de` through an
# XDG_CONFIG_HOME override (never the real config), asserts the process
# stays alive and answers IPC, then cleans up. Proves the whole German
# strings table live — window creation walks every menu/dialog/banner
# table field, not just the comptime conversions the tests cover.
#
#   powershell -File scripts/smoke-de.ps1
param(
    [string]$Binary = "zig-out/bin/paramux.exe",
    [string]$Com = "zig-out/bin/paramux.com"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Binary)) { Write-Error "Build first: zig build -Demit-exe=true" }

Get-Process paramux -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$cfgRoot = Join-Path $env:TEMP "paramux-de-smoke-config"
Remove-Item $cfgRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory (Join-Path $cfgRoot "paramux") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $cfgRoot "paramux\config.ghostty"), "ui-language = de`n", (New-Object System.Text.UTF8Encoding $false))

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = (Resolve-Path $Binary).Path
$psi.UseShellExecute = $false
$psi.EnvironmentVariables["XDG_CONFIG_HOME"] = $cfgRoot
$p = [System.Diagnostics.Process]::Start($psi)
try {
    Start-Sleep -Seconds 5
    if ($p.HasExited) { throw "paramux exited under ui-language=de (code $($p.ExitCode))" }
    $ErrorActionPreference = "Continue"
    $rows = @(& $Com status --no-header).Count
    if ($rows -lt 1) { $ErrorActionPreference = "Stop"; throw "status returned no rows under ui-language=de" }
    Write-Host "DE SMOKE PASS: alive with $rows pane row(s) under ui-language=de"
} finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $cfgRoot -Recurse -Force -ErrorAction SilentlyContinue
}
