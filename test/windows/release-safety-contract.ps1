param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Assert-Contains {
    param(
        [string] $Text,
        [string] $Needle,
        [string] $Message
    )

    if (-not $Text.Contains($Needle)) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [string] $Text,
        [string] $Needle,
        [string] $Message
    )

    if ($Text.Contains($Needle)) {
        throw $Message
    }
}

$releaseWorkflow = Get-Content -LiteralPath (
    Join-Path $repoRoot '.github\workflows\release.yml'
) -Raw
Assert-Contains $releaseWorkflow 'RELEASE_INPUT_VERSION: ${{ inputs.version }}' 'Manual release version must enter PowerShell through the environment.'
Assert-Contains $releaseWorkflow 'RELEASE_INPUT_PRERELEASE: ${{ inputs.prerelease }}' 'Manual prerelease state must enter PowerShell through the environment.'
Assert-NotContains $releaseWorkflow '$version = "${{ inputs.version }}"' 'Manual release input must not be injected into PowerShell source.'
Assert-NotContains $releaseWorkflow 'if ("${{ github.event_name }}"' 'GitHub event data must not be injected into PowerShell source.'
Assert-Contains $releaseWorkflow 'gh release create $tag --target $env:GITHUB_SHA' 'New releases must tag the packaged checkout commit.'
Assert-Contains $releaseWorkflow '$releaseTarget -ne $env:GITHUB_SHA' 'Existing releases must be proven to target the packaged checkout commit before assets are replaced.'
Assert-Contains $releaseWorkflow 'gh release edit failed with exit code' 'Release metadata edits must fail closed before asset upload.'
Assert-Contains $releaseWorkflow 'git config user.name failed with exit code' 'Scoop publishing must stop when author-name configuration fails.'
Assert-Contains $releaseWorkflow 'git config user.email failed with exit code' 'Scoop publishing must stop when author-email configuration fails.'
Assert-Contains $releaseWorkflow 'git add failed with exit code' 'Scoop publishing must stop when staging the manifest fails.'
Assert-NotContains $releaseWorkflow '-RequirePackageManagers' 'Release preflight must preserve the explicit Scoop/WinGet skip paths.'
Assert-Contains $releaseWorkflow '$PSNativeCommandUseErrorActionPreference = $true' 'Release test blocks must fail on the first native command error.'

$testWorkflow = Get-Content -LiteralPath (
    Join-Path $repoRoot '.github\workflows\test.yml'
) -Raw
Assert-Contains $testWorkflow '$PSNativeCommandUseErrorActionPreference = $true' 'Windows CI multiline native commands must fail immediately.'

$armWorkflow = Get-Content -LiteralPath (
    Join-Path $repoRoot '.github\workflows\windows-arm64.yml'
) -Raw
Assert-Contains $armWorkflow '$PSNativeCommandUseErrorActionPreference = $true' 'ARM64 multiline native commands must fail immediately.'

$packageWindows = Get-Content -LiteralPath (
    Join-Path $repoRoot 'scripts\package-windows.ps1'
) -Raw
Assert-Contains $packageWindows 'Test-PathIsStrictDescendant' 'Windows packaging deletion must use a separator-aware boundary check.'
Assert-Contains $packageWindows 'zig build failed with exit code' 'Windows packaging must stop after a failed build.'

$packageManagers = Get-Content -LiteralPath (
    Join-Path $repoRoot 'scripts\package-package-managers.ps1'
) -Raw
Assert-Contains $packageManagers 'Test-PathIsStrictDescendant' 'Package-manager output deletion must use a separator-aware boundary check.'

Write-Host 'release safety contract: PASS'
