<#
.SYNOPSIS
    Add this paramux folder to your PATH so `paramux` works from any terminal.

.DESCRIPTION
    Run this once from the extracted paramux folder (the one containing
    paramux.exe and paramux.com). It:
      * strips the "downloaded from the internet" mark from the folder (so
        Windows SmartScreen won't prompt), and
      * adds the folder to your per-user PATH (idempotent; no admin needed).

    Then open a NEW terminal and run `paramux`.

.PARAMETER Remove
    Remove this folder from your PATH instead of adding it.
#>
[CmdletBinding()]
param(
    [switch] $Remove
)

$ErrorActionPreference = "Stop"
$dir = $PSScriptRoot

if (-not (Test-Path -LiteralPath (Join-Path $dir "paramux.exe"))) {
    Write-Host "paramux.exe was not found next to this script." -ForegroundColor Red
    Write-Host "Run install-paramux.ps1 from inside the extracted 'paramux' folder." -ForegroundColor Red
    exit 1
}

function Get-UserPathParts {
    $raw = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrEmpty($raw)) { return @() }
    return @($raw -split ';' | Where-Object { $_ -ne '' })
}

if ($Remove) {
    $parts = Get-UserPathParts | Where-Object { $_ -ne $dir }
    [Environment]::SetEnvironmentVariable("Path", ($parts -join ';'), "User")
    Write-Host "Removed from your PATH: $dir" -ForegroundColor Yellow
    Write-Host "Open a new terminal for the change to take effect."
    return
}

# Clear the Mark-of-the-Web so there's no SmartScreen friction, ever.
try {
    Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
} catch {}

# Add to the per-user PATH (idempotent; uses the .NET API, not setx, so it
# won't truncate a long PATH).
$parts = Get-UserPathParts
if ($parts -contains $dir) {
    Write-Host "Already on your PATH: $dir" -ForegroundColor Yellow
} else {
    [Environment]::SetEnvironmentVariable("Path", ((@($parts) + $dir) -join ';'), "User")
    Write-Host "Added to your PATH: $dir" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Open a NEW terminal, then try:" -ForegroundColor Cyan
Write-Host "  paramux                  # launch the terminal"
Write-Host "  paramux -e claude        # launch it running Claude Code"
Write-Host "  paramux +list-windows    # automation / scripting"
Write-Host ""
Write-Host "(To undo: run  .\install-paramux.ps1 -Remove )"
