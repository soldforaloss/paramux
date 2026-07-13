<#
.SYNOPSIS
    Writes trusted absolute executable paths into the packaged agent hook files.

.DESCRIPTION
    The source hook files deliberately contain non-executable placeholders.
    This script replaces them with paths anchored to this verified portable
    install so a project working directory cannot shadow a global hook command.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] $Value
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText(
        $Path,
        $json + [Environment]::NewLine,
        $utf8
    )
}

$root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$paramuxExecutable = Join-Path $root 'paramux.com'
$codexLauncher = Join-Path $root 'paramux-codex-hook.cmd'
$claudeSettingsPath = Join-Path $root 'agent-hooks\claude-code.settings.json'
$codexHooksPath = Join-Path $root 'agent-hooks\codex\hooks.json'

foreach ($requiredPath in @(
    $paramuxExecutable,
    $codexLauncher,
    $claudeSettingsPath,
    $codexHooksPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing required Paramux hook file: $requiredPath"
    }
}

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (
    [string]::IsNullOrWhiteSpace($windowsPowerShell) -or
    -not [System.IO.Path]::IsPathRooted($windowsPowerShell) -or
    -not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)
) {
    throw 'Windows PowerShell must have an existing absolute executable path.'
}
if ($windowsPowerShell -match '\s') {
    throw "The Windows PowerShell path contains whitespace and cannot be rendered safely: $windowsPowerShell"
}

$claudeSettings = Get-Content -LiteralPath $claudeSettingsPath -Raw |
    ConvertFrom-Json
$claudeHandlerCount = 0
foreach ($eventProperty in $claudeSettings.hooks.PSObject.Properties) {
    foreach ($group in @($eventProperty.Value)) {
        foreach ($handler in @($group.hooks)) {
            if ($handler.type -eq 'command') {
                $handler.command = $paramuxExecutable
                $claudeHandlerCount++
            }
        }
    }
}
if ($claudeHandlerCount -ne 6) {
    throw "Expected 6 Claude command hooks, found $claudeHandlerCount."
}

$launcherCommand = "& '" + $codexLauncher.Replace("'", "''") + "'"
$encodedLauncherCommand = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($launcherCommand)
)
$codexCommandWindows = $windowsPowerShell +
    ' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
    $encodedLauncherCommand
$codexHooks = Get-Content -LiteralPath $codexHooksPath -Raw |
    ConvertFrom-Json
$codexHandlerCount = 0
foreach ($eventProperty in $codexHooks.hooks.PSObject.Properties) {
    foreach ($group in @($eventProperty.Value)) {
        foreach ($handler in @($group.hooks)) {
            if ($handler.type -eq 'command') {
                $handler.commandWindows = $codexCommandWindows
                $codexHandlerCount++
            }
        }
    }
}
if ($codexHandlerCount -ne 4) {
    throw "Expected 4 Codex command hooks, found $codexHandlerCount."
}

Write-JsonFile -Path $claudeSettingsPath -Value $claudeSettings
Write-JsonFile -Path $codexHooksPath -Value $codexHooks

Write-Host 'Configured agent hooks with trusted absolute Paramux paths.' -ForegroundColor Green
