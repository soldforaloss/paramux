param(
    [string] $Version = '0.0.1',
    [string] $Architecture = $null,
    [string] $OutputRoot = 'dist/artifacts',
    [switch] $SkipPackage
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts\windows-architecture.ps1')
$Architecture = (Get-WindowsPackageArchitecture -Architecture $(if ($Architecture) { $Architecture } else { Get-DefaultWindowsPackageArchitecture })).Name
$packageScript = Join-Path $repoRoot 'scripts\package-windows.ps1'
$shellHarness = Join-Path $repoRoot 'test\windows\cli-shell-command.ps1'
$detachedHarness = Join-Path $repoRoot 'test\windows\cli-detached-action.ps1'

$outputRootPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
$stageBase = Join-Path $outputRootPath ("paramux-{0}-windows-{1}" -f $Version, $Architecture)
$portableRoot = Join-Path $stageBase 'paramux'
$portableExe = Join-Path $portableRoot 'paramux.exe'
$portableCommand = Join-Path $portableRoot 'paramux.com'
$codexHookLauncher = Join-Path $portableRoot 'paramux-codex-hook.cmd'
$hookConfigurator = Join-Path $portableRoot 'configure-paramux-hooks.ps1'
$portableResources = Join-Path $portableRoot 'share\ghostty'
$tmuxPrefixPreset = Join-Path $portableRoot 'config-presets\tmux-prefix.ghostty'
$agentHooksRoot = Join-Path $portableRoot 'agent-hooks'
$agentHookFiles = @(
    'README.md',
    'claude-code.settings.json',
    'codex\hooks.json',
    'codex\paramux-hook.cjs',
    'gemini-paramux\gemini-extension.json',
    'gemini-paramux\hooks\hooks.json',
    'gemini-paramux\scripts\notify.cjs',
    'gemini-paramux\scripts\notify.cmd',
    'opencode\paramux.js'
)

if (-not $SkipPackage) {
    & $packageScript -Version $Version -Architecture $Architecture -OutputRoot $OutputRoot
}

$requiredPortablePaths = @(
    $portableRoot,
    $portableExe,
    $portableCommand,
    $codexHookLauncher,
    $hookConfigurator,
    $portableResources,
    $tmuxPrefixPreset
) + @($agentHookFiles | ForEach-Object { Join-Path $agentHooksRoot $_ })

foreach ($path in $requiredPortablePaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing packaged portable artifact path: $path"
    }
}

& $portableCommand '+validate-config' ("--config-file={0}" -f $tmuxPrefixPreset)
if ($LASTEXITCODE -ne 0) {
    throw "Packaged tmux-prefix preset failed config validation with exit code $LASTEXITCODE."
}

& $shellHarness `
    -Shell cmd `
    -BinDir $portableRoot `
    -Arguments @('+help') `
    -ExpectedText 'Usage: paramux [+action] [options]'

& $shellHarness `
    -Shell powershell `
    -BinDir $portableRoot `
    -Arguments @('+version') `
    -ExpectedText 'Build Config'

& $shellHarness `
    -Shell cmd `
    -BinDir $portableRoot `
    -Arguments @('+boo', '--help') `
    -ExpectedText 'The `boo` command is used to display the project animation in the terminal.'

& $shellHarness `
    -Shell powershell `
    -BinDir $portableRoot `
    -Arguments @('+list-keybinds') `
    -ExpectedText 'keybind = ctrl+shift+,=reload_config'

& $shellHarness `
    -Shell cmd `
    -BinDir $portableRoot `
    -Arguments @('+list-colors') `
    -ExpectedText 'alice blue = #f0f8ff'

& $shellHarness `
    -Shell powershell `
    -BinDir $portableRoot `
    -Arguments @('+list-themes') `
    -ExpectedText '0x96f (resources)'

& $detachedHarness `
    -ExePath $portableExe `
    -Action '+boo' `
    -ResourcesDir $portableResources

Write-Host "portable package CLI validation: PASS (root=$portableRoot)"
