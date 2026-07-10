<#
.SYNOPSIS
    Configure this portable Paramux install for terminals and agent hooks.

.DESCRIPTION
    Run this once from the extracted paramux folder (the one containing
    paramux.exe and paramux.com). It:
      * strips the "downloaded from the internet" mark from the folder (so
        Windows SmartScreen won't prompt), and
      * adds the folder to your per-user PATH (idempotent; no admin needed),
      * sets the per-user PARAMUX_HOME variable,
      * writes absolute installed paths into the Claude and Codex hook files, and
      * adds "Open in Paramux" to the Explorer right-click menu for folders,
        folder backgrounds, and drives (per-user registry, no admin; on
        Windows 11 it appears under "Show more options").

    Then open a NEW terminal and run `paramux`.

.PARAMETER Remove
    Remove this folder from your PATH, clear PARAMUX_HOME, and delete the
    "Open in Paramux" context-menu entries — each only when it still points
    at this folder.

.PARAMETER NoContextMenu
    Skip registering the Explorer "Open in Paramux" context-menu entries.
#>
[CmdletBinding()]
param(
    [switch] $Remove,
    [switch] $NoContextMenu
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

# The Explorer "Open in Paramux" verb keys (per-user, HKCU — no admin).
# Directory = right-click a folder icon; Directory\Background = the empty
# space inside an open folder; Drive = a drive root in This PC. Keep this
# list in sync with src\apprt\win32_explorer_menu.zig, which owns the same
# keys for the in-app Settings toggle.
$contextMenuKeys = @(
    "HKCU:\Software\Classes\Directory\shell\Paramux",
    "HKCU:\Software\Classes\Directory\Background\shell\Paramux",
    "HKCU:\Software\Classes\Drive\shell\Paramux"
)

function Install-ContextMenu([string] $ExePath) {
    # `"%V\."` (not a bare "%V"): for root folders like C:\ the trailing
    # backslash would escape the closing quote; `\.` keeps the quote intact
    # and normalizes away during path resolution.
    $command = "`"$ExePath`" --working-directory=`"%V\.`""
    foreach ($key in $contextMenuKeys) {
        New-Item -Path "$key\command" -Force | Out-Null
        Set-ItemProperty -LiteralPath $key -Name '(Default)' -Value 'Open in Paramux'
        Set-ItemProperty -LiteralPath $key -Name 'Icon' -Value "`"$ExePath`",0"
        Set-ItemProperty -LiteralPath "$key\command" -Name '(Default)' -Value $command
    }
    Write-Host "Added 'Open in Paramux' to the Explorer right-click menu." -ForegroundColor Green
    Write-Host "  (On Windows 11 it lives under 'Show more options'.)"
}

function Remove-ContextMenu([string] $ExePath) {
    $removed = $false
    foreach ($key in $contextMenuKeys) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        # Only remove entries that point at THIS install; leave a different
        # paramux install's registration alone.
        $cmd = (Get-ItemProperty -LiteralPath "$key\command" -ErrorAction SilentlyContinue).'(Default)'
        if ($null -ne $cmd -and ($cmd -notlike "`"$ExePath`"*")) {
            Write-Host "Preserved context-menu entry (points elsewhere): $key" -ForegroundColor Yellow
            continue
        }
        Remove-Item -LiteralPath $key -Recurse -Force
        $removed = $true
    }
    if ($removed) {
        Write-Host "Removed 'Open in Paramux' from the Explorer right-click menu." -ForegroundColor Yellow
    }
}

if ($Remove) {
    Remove-ContextMenu (Join-Path $dir "paramux.exe")

    $parts = Get-UserPathParts | Where-Object { $_ -ne $dir }
    [Environment]::SetEnvironmentVariable("Path", ($parts -join ';'), "User")
    Write-Host "Removed from your PATH: $dir" -ForegroundColor Yellow

    $installedHome = [Environment]::GetEnvironmentVariable("PARAMUX_HOME", "User")
    if ([string]::Equals($installedHome, $dir, [StringComparison]::OrdinalIgnoreCase)) {
        [Environment]::SetEnvironmentVariable("PARAMUX_HOME", $null, "User")
        if ([string]::Equals($env:PARAMUX_HOME, $dir, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item Env:PARAMUX_HOME -ErrorAction SilentlyContinue
        }
        Write-Host "Cleared PARAMUX_HOME for this install." -ForegroundColor Yellow
    } elseif (-not [string]::IsNullOrEmpty($installedHome)) {
        Write-Host "Preserved PARAMUX_HOME because it points elsewhere: $installedHome" -ForegroundColor Yellow
    }

    Write-Host "Open a new terminal for the change to take effect."
    return
}

# Clear the Mark-of-the-Web so there's no SmartScreen friction, ever.
try {
    Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
} catch {}

$hookConfigurator = Join-Path $dir 'configure-paramux-hooks.ps1'
if (-not (Test-Path -LiteralPath $hookConfigurator -PathType Leaf)) {
    throw "Missing agent hook configurator: $hookConfigurator"
}
& $hookConfigurator

# Add to the per-user PATH (idempotent; uses the .NET API, not setx, so it
# won't truncate a long PATH).
$parts = Get-UserPathParts
if ($parts -contains $dir) {
    Write-Host "Already on your PATH: $dir" -ForegroundColor Yellow
} else {
    [Environment]::SetEnvironmentVariable("Path", ((@($parts) + $dir) -join ';'), "User")
    Write-Host "Added to your PATH: $dir" -ForegroundColor Green
}

[Environment]::SetEnvironmentVariable("PARAMUX_HOME", $dir, "User")
$env:PARAMUX_HOME = $dir
Write-Host "Set PARAMUX_HOME: $dir" -ForegroundColor Green

if (-not $NoContextMenu) {
    Install-ContextMenu (Join-Path $dir "paramux.exe")
}

Write-Host ""
Write-Host "Done. Open a NEW terminal, then try:" -ForegroundColor Cyan
Write-Host "  paramux                  # launch the terminal"
Write-Host "  paramux -e claude        # launch it running Claude Code"
Write-Host "  paramux list-windows    # automation / scripting"
Write-Host ""
Write-Host "(To undo: run  .\install-paramux.ps1 -Remove )"
