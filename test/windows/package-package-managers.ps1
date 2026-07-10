param(
    [string] $Version = '0.0.1'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$packageScript = Join-Path $repoRoot 'scripts\package-package-managers.ps1'
. (Join-Path $repoRoot 'scripts\windows-architecture.ps1')
. (Join-Path $repoRoot 'scripts\path-safety.ps1')

$fixtureRelative = Join-Path '.zig-cache' ("package-manager-metadata-{0}" -f [guid]::NewGuid().ToString('N'))
$artifactRelative = Join-Path $fixtureRelative 'artifacts'
$fixtureRoot = Join-Path $repoRoot $fixtureRelative
$artifactRoot = Join-Path $repoRoot $artifactRelative

function Assert-Equal {
    param(
        [object] $Expected,
        [object] $Actual,
        [string] $Label
    )

    if ($Expected -ne $Actual) {
        throw "$Label mismatch. Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Label
    )

    if (-not $Condition) {
        throw $Label
    }
}

$insidePath = Join-Path $repoRoot 'dist\artifacts\package-managers'
$siblingPath = Join-Path ($repoRoot + '-review-sibling') 'output'
Assert-True (Test-PathIsStrictDescendant -Candidate $insidePath -Parent $repoRoot) 'Expected nested output path to be accepted.'
Assert-True (-not (Test-PathIsStrictDescendant -Candidate $repoRoot -Parent $repoRoot)) 'Repository root must not be accepted as its own child.'
Assert-True (-not (Test-PathIsStrictDescendant -Candidate $siblingPath -Parent $repoRoot)) 'Raw-prefix sibling path must not be accepted.'

function Invoke-MetadataCase {
    param(
        [string] $Name,
        [AllowEmptyString()]
        [string] $PackageIdentifier
    )

    $outputRelative = Join-Path $fixtureRelative "output-$Name"
    & $packageScript `
        -Version $Version `
        -Tag "v$Version" `
        -Repo 'example/paramux' `
        -Architectures @('x64') `
        -ArtifactRoot $artifactRelative `
        -OutputRoot $outputRelative `
        -WingetPackageIdentifier $PackageIdentifier

    $metadataPath = Join-Path $repoRoot (Join-Path $outputRelative 'metadata.json')
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    Assert-Equal -Expected $PackageIdentifier -Actual $metadata.winget.packageIdentifier -Label "$Name package identifier"
    Assert-Equal -Expected $Version -Actual $metadata.winget.version -Label "$Name WinGet version"
    Assert-Equal -Expected 1 -Actual @($metadata.winget.installerUrlArgs).Count -Label "$Name installer URL count"
    Assert-Equal -Expected "$($metadata.winget.installerUrl)|x64" -Actual $metadata.winget.installerUrlArgs[0] -Label "$Name installer URL argument"
    Write-Host "metadata case ${Name}: packageIdentifier='$PackageIdentifier', installerUrlArgs=1"
}

try {
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

    $setupName = New-WindowsPackageArtifactName -Version $Version -Architecture 'x64' -Kind 'setup'
    $portableName = New-WindowsPackageArtifactName -Version $Version -Architecture 'x64' -Kind 'portable'
    $checksumsName = New-WindowsPackageArtifactName -Version $Version -Architecture 'x64' -Kind 'checksums'
    $setupPath = Join-Path $artifactRoot $setupName
    $portablePath = Join-Path $artifactRoot $portableName

    [System.IO.File]::WriteAllText($setupPath, 'setup fixture')
    [System.IO.File]::WriteAllText($portablePath, 'portable fixture')
    [System.IO.File]::WriteAllText((Join-Path $artifactRoot 'paramux-icon.svg'), '<svg/>')

    $setupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $setupPath).Hash.ToLowerInvariant()
    $portableHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $portablePath).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllLines(
        (Join-Path $artifactRoot $checksumsName),
        @(
            "$setupHash *$setupName",
            "$portableHash *$portableName"
        )
    )

    Invoke-MetadataCase -Name 'empty' -PackageIdentifier ''
    Invoke-MetadataCase -Name 'configured' -PackageIdentifier 'Example.Paramux'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Host 'package manager metadata validation: PASS'
