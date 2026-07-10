[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Architecture = $null,

    [string]$OutputRoot = "dist/artifacts",

    [switch]$SkipBuild,

    [switch]$SkipInstaller,

    [switch]$RequireInstaller,

    [switch]$RequireSigning
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot "windows-architecture.ps1")
. (Join-Path $PSScriptRoot "path-safety.ps1")

if ($SkipInstaller -and $RequireInstaller) {
    throw "-SkipInstaller and -RequireInstaller cannot be used together."
}

$archInfo = Get-WindowsPackageArchitecture -Architecture $(if ($Architecture) { $Architecture } else { Get-DefaultWindowsPackageArchitecture })
$Architecture = $archInfo.Name

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$outputRootPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
if (-not (Test-PathIsStrictDescendant -Candidate $outputRootPath -Parent $repoRoot)) {
    throw "OutputRoot must resolve below the repository root: $outputRootPath"
}
$userHome = if ($env:USERPROFILE) {
    $env:USERPROFILE
} elseif ($env:HOMEDRIVE -and $env:HOMEPATH) {
    "$($env:HOMEDRIVE)$($env:HOMEPATH)"
} else {
    Join-Path "C:" "Users"
}
$localAppData = if ($env:LOCALAPPDATA) {
    $env:LOCALAPPDATA
} else {
    Join-Path $userHome "AppData\Local"
}
$zigTarget = $archInfo.ZigTarget
$stageBase = Join-Path $outputRootPath "paramux-$Version-windows-$Architecture"
$portableRoot = Join-Path $stageBase "paramux"
$zipPath = Join-Path $stageBase (New-WindowsPackageArtifactName -Version $Version -Architecture $Architecture -Kind portable)
$installerPath = Join-Path $stageBase (New-WindowsPackageArtifactName -Version $Version -Architecture $Architecture -Kind setup)
$checksumsPath = Join-Path $stageBase (New-WindowsPackageArtifactName -Version $Version -Architecture $Architecture -Kind checksums)
$releaseIconPath = Join-Path $stageBase "paramux-icon.svg"
$zigOutBin = Join-Path $repoRoot "zig-out/bin"
$zigOutShare = Join-Path $repoRoot "zig-out/share"
$exePath = Join-Path $zigOutBin "paramux.exe"
$runtimeFiles = @(
    "paramux.com",
    "paramux.exe",
    "ghostty-vt.dll"
)
$licensePath = Join-Path $repoRoot "LICENSE"
$readmePath = Join-Path $repoRoot "dist/windows/README-portable.md"
$agentHooksPath = Join-Path $repoRoot "contrib/paramux/hooks"
$codexHookLauncherPath = Join-Path $repoRoot "dist/windows/paramux-codex-hook.cmd"
$hookConfiguratorPath = Join-Path $repoRoot "dist/windows/configure-paramux-hooks.ps1"
$configPresetsPath = Join-Path $repoRoot "src/config/presets"
$configTemplatePath = Join-Path $repoRoot "src/config/config-template"
$innoScriptPath = Join-Path $repoRoot "dist/windows/paramux.iss"
$iconPath = Join-Path $repoRoot "dist/windows/paramux.ico"
$releaseIconSourcePath = Join-Path $repoRoot "images/paramux-flag-light.svg"
$signingPfxPath = if ($env:WINDOWS_CODESIGN_PFX_PATH) {
    $env:WINDOWS_CODESIGN_PFX_PATH
} else {
    $null
}
$signingPfxBase64 = if ($env:WINDOWS_CODESIGN_PFX_BASE64) {
    $env:WINDOWS_CODESIGN_PFX_BASE64
} else {
    $null
}
$signingPfxPassword = if ($env:WINDOWS_CODESIGN_PFX_PASSWORD) {
    $env:WINDOWS_CODESIGN_PFX_PASSWORD
} else {
    $null
}
$signingTimestampUrl = if ($env:WINDOWS_CODESIGN_TIMESTAMP_URL) {
    $env:WINDOWS_CODESIGN_TIMESTAMP_URL
} else {
    "http://timestamp.digicert.com"
}
$signingDescription = if ($env:WINDOWS_CODESIGN_DESCRIPTION) {
    $env:WINDOWS_CODESIGN_DESCRIPTION
} else {
    "paramux"
}
$signingUrl = if ($env:WINDOWS_CODESIGN_URL) {
    $env:WINDOWS_CODESIGN_URL
} else {
    "https://github.com/soldforaloss/paramux"
}
$trustSelfSignedSigningCert = if ($env:WINDOWS_CODESIGN_TRUST_SELF_SIGNED) {
    $env:WINDOWS_CODESIGN_TRUST_SELF_SIGNED
} else {
    $null
}
$preferredSignToolPath = if ($env:WINDOWS_CODESIGN_SIGNTOOL_PATH) {
    $env:WINDOWS_CODESIGN_SIGNTOOL_PATH
} else {
    $null
}

if (-not $env:ZIG_LOCAL_CACHE_DIR) {
    $env:ZIG_LOCAL_CACHE_DIR = Join-Path $repoRoot ".zig-cache"
}
if (-not $env:ZIG_GLOBAL_CACHE_DIR) {
    $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $localAppData "zig"
}

New-Item -ItemType Directory -Path $env:ZIG_LOCAL_CACHE_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $env:ZIG_GLOBAL_CACHE_DIR -Force | Out-Null

function Remove-TreeIfPresent {
    param([string]$PathToRemove)

    if (-not (Test-Path -LiteralPath $PathToRemove)) {
        return
    }

    $resolved = [System.IO.Path]::GetFullPath($PathToRemove)
    if (-not (Test-PathIsStrictDescendant -Candidate $resolved -Parent $repoRoot)) {
        throw "Refusing to remove path outside repo root: $resolved"
    }

    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Get-PeMachine {
    param([string]$PathToCheck)

    $fullPath = (Resolve-Path -LiteralPath $PathToCheck).Path
    $stream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $reader = [System.IO.BinaryReader]::new($stream)
        try {
            if ($reader.ReadUInt16() -ne 0x5A4D) {
                throw "Not a PE file: $fullPath"
            }

            if ($stream.Length -lt 0x40) {
                throw "PE file is too small to contain a header offset: $fullPath"
            }
            $stream.Position = 0x3C
            $peOffset = $reader.ReadUInt32()
            if ($peOffset + 6 -gt $stream.Length) {
                throw "PE header offset is outside the file bounds: $fullPath"
            }
            $stream.Position = $peOffset
            if ($reader.ReadUInt32() -ne 0x00004550) {
                throw "Missing PE signature: $fullPath"
            }

            return $reader.ReadUInt16()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-PeMachine {
    param(
        [string]$PathToCheck,
        [string]$ExpectedArchitecture
    )

    $expectedMachine = (Get-WindowsPackageArchitecture -Architecture $ExpectedArchitecture).PeMachine
    $actualMachine = Get-PeMachine -PathToCheck $PathToCheck
    if ($actualMachine -ne $expectedMachine) {
        throw ("Expected {0} to be {1} PE machine 0x{2:X4}, got 0x{3:X4}." -f $PathToCheck, $ExpectedArchitecture, $expectedMachine, $actualMachine)
    }
}

function Assert-ParamuxVersionInfo {
    param(
        [string]$PathToCheck,
        [string]$ExpectedVersion,
        [string]$ExpectedOriginalFilename
    )

    $versionMatch = [regex]::Match(
        $ExpectedVersion,
        '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-paramux\.(?<revision>0|[1-9]\d*))?$'
    )
    if (-not $versionMatch.Success) {
        throw "Expected a stable or Paramux prerelease semantic version, got: $ExpectedVersion"
    }

    $versionInfo = (Get-Item -LiteralPath $PathToCheck).VersionInfo
    $expectedFields = @{
        CompanyName = "Paramux Contributors"
        FileDescription = "Paramux terminal workspace"
        LegalCopyright = "Copyright (c) Paramux contributors"
        OriginalFilename = $ExpectedOriginalFilename
        ProductName = "Paramux"
        FileVersion = $ExpectedVersion
        ProductVersion = $ExpectedVersion
    }

    foreach ($field in $expectedFields.Keys) {
        if ($versionInfo.$field -ne $expectedFields[$field]) {
            throw "Expected $field '$($expectedFields[$field])' in $PathToCheck, got '$($versionInfo.$field)'."
        }
    }

    $expectedNumericFields = @{
        FileMajorPart = [int]$versionMatch.Groups["major"].Value
        FileMinorPart = [int]$versionMatch.Groups["minor"].Value
        FileBuildPart = [int]$versionMatch.Groups["patch"].Value
        FilePrivatePart = if ($versionMatch.Groups["revision"].Success) {
            [int]$versionMatch.Groups["revision"].Value
        } else {
            0
        }
        ProductMajorPart = [int]$versionMatch.Groups["major"].Value
        ProductMinorPart = [int]$versionMatch.Groups["minor"].Value
        ProductBuildPart = [int]$versionMatch.Groups["patch"].Value
        ProductPrivatePart = if ($versionMatch.Groups["revision"].Success) {
            [int]$versionMatch.Groups["revision"].Value
        } else {
            0
        }
    }
    foreach ($field in $expectedNumericFields.Keys) {
        if ($versionInfo.$field -ne $expectedNumericFields[$field]) {
            throw "Expected $field '$($expectedNumericFields[$field])' in $PathToCheck, got '$($versionInfo.$field)'."
        }
    }
}

function Find-SignTool {
    param([string]$PreferredPath)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        if (-not (Test-Path -LiteralPath $PreferredPath)) {
            throw "Configured signtool.exe path was not found: $PreferredPath"
        }

        return [System.IO.Path]::GetFullPath($PreferredPath)
    }

    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $sdkRoots = @(
        "C:\Program Files (x86)\Windows Kits\10\bin",
        "C:\Program Files\Windows Kits\10\bin"
    )

    foreach ($sdkRoot in $sdkRoots) {
        if (-not (Test-Path -LiteralPath $sdkRoot)) {
            continue
        }

        $sdkVersions = Get-ChildItem -LiteralPath $sdkRoot -Directory | Sort-Object Name -Descending
        foreach ($sdkVersion in $sdkVersions) {
            $candidate = Join-Path $sdkVersion.FullName "x64\signtool.exe"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function ConvertTo-Boolean {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        "1" { return $true }
        "true" { return $true }
        "yes" { return $true }
        "on" { return $true }
        "0" { return $false }
        "false" { return $false }
        "no" { return $false }
        "off" { return $false }
        default {
            throw "Expected WINDOWS_CODESIGN_TRUST_SELF_SIGNED to be one of: true, false, 1, 0, yes, no, on, off."
        }
    }
}

function Test-SelfSignedTrustStatus {
    param([System.Management.Automation.Signature]$Signature)

    if ($Signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) {
        return $true
    }

    if ($Signature.Status -eq [System.Management.Automation.SignatureStatus]::NotTrusted) {
        return $true
    }

    if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::UnknownError) {
        return $false
    }

    $message = if ($Signature.StatusMessage) { $Signature.StatusMessage } else { "" }
    return $message -match "root certificate.*not trusted|self-signed|not trusted by the trust provider"
}

function New-TemporaryPfxFile {
    param([string]$Base64Value)

    try {
        $bytes = [Convert]::FromBase64String($Base64Value)
    }
    catch {
        throw "WINDOWS_CODESIGN_PFX_BASE64 was not valid base64."
    }

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("paramux-signing-" + [System.Guid]::NewGuid().ToString("N") + ".pfx")
    [System.IO.File]::WriteAllBytes($path, $bytes)
    return $path
}

function Get-SigningConfig {
    $hasPath = -not [string]::IsNullOrWhiteSpace($signingPfxPath)
    $hasBase64 = -not [string]::IsNullOrWhiteSpace($signingPfxBase64)

    if ($hasPath -and $hasBase64) {
        throw "Set only one of WINDOWS_CODESIGN_PFX_PATH or WINDOWS_CODESIGN_PFX_BASE64."
    }

    if (-not $hasPath -and -not $hasBase64) {
        if ($RequireSigning) {
            throw "Release signing is required, but no code-signing certificate was configured."
        }

        return $null
    }

    if ([string]::IsNullOrWhiteSpace($signingPfxPassword)) {
        throw "WINDOWS_CODESIGN_PFX_PASSWORD must be set when release signing is enabled."
    }

    $signToolPath = Find-SignTool -PreferredPath $preferredSignToolPath
    if (-not $signToolPath) {
        throw "signtool.exe was not found. Install the Windows SDK or set WINDOWS_CODESIGN_SIGNTOOL_PATH."
    }

    $resolvedPfxPath = if ($hasBase64) {
        New-TemporaryPfxFile -Base64Value $signingPfxBase64
    } else {
        [System.IO.Path]::GetFullPath($signingPfxPath)
    }

    if (-not (Test-Path -LiteralPath $resolvedPfxPath)) {
        throw "Configured code-signing certificate was not found: $resolvedPfxPath"
    }

    $trustSelfSigned = ConvertTo-Boolean -Value $trustSelfSignedSigningCert
    $signingCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $resolvedPfxPath,
        $signingPfxPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    )
    $isSelfSigned = $signingCert.Subject -eq $signingCert.Issuer

    if ($trustSelfSigned -and -not $isSelfSigned) {
        throw "WINDOWS_CODESIGN_TRUST_SELF_SIGNED=true is only supported for a self-signed PFX."
    }

    return @{
        SignToolPath = $signToolPath
        PfxPath = $resolvedPfxPath
        PfxPassword = $signingPfxPassword
        TimestampUrl = if ($trustSelfSigned) { $null } else { $signingTimestampUrl }
        Description = $signingDescription
        Url = $signingUrl
        TemporaryPfxPath = if ($hasBase64) { $resolvedPfxPath } else { $null }
        CertificateThumbprint = $signingCert.Thumbprint
        IsSelfSigned = $isSelfSigned
        TrustSelfSigned = $trustSelfSigned
    }
}

function Invoke-SignFile {
    param(
        [hashtable]$SigningConfig,
        [string]$PathToSign
    )

    $signArgs = @(
        "sign",
        "/fd", "SHA256",
        "/f", $SigningConfig.PfxPath,
        "/p", $SigningConfig.PfxPassword
    )

    if (-not [string]::IsNullOrWhiteSpace($SigningConfig.TimestampUrl)) {
        $signArgs += @("/t", $SigningConfig.TimestampUrl)
    }

    $signArgs += @(
        "/d", $SigningConfig.Description,
        "/du", $SigningConfig.Url,
        $PathToSign
    )

    & $SigningConfig.SignToolPath @signArgs

    if ($LASTEXITCODE -ne 0) {
        throw "signtool.exe failed for $PathToSign with exit code $LASTEXITCODE."
    }
}

function Assert-ValidSignature {
    param(
        [string]$PathToCheck,
        [hashtable]$SigningConfig
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $PathToCheck
    if ($SigningConfig -and $SigningConfig.TrustSelfSigned) {
        if (-not $signature.SignerCertificate) {
            throw "Expected a self-signed Authenticode signature on $PathToCheck, but no signer certificate was present."
        }

        if ($signature.SignerCertificate.Thumbprint -ne $SigningConfig.CertificateThumbprint) {
            throw "Expected signer thumbprint $($SigningConfig.CertificateThumbprint) on $PathToCheck, but got $($signature.SignerCertificate.Thumbprint)."
        }

        if (-not (Test-SelfSignedTrustStatus -Signature $signature)) {
            throw "Expected a self-signed Authenticode signature on $PathToCheck, but got $($signature.Status): $($signature.StatusMessage)"
        }

        return
    }

    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Expected a valid Authenticode signature on $PathToCheck, but got $($signature.Status): $($signature.StatusMessage)"
    }
}

$signingConfig = $null
$temporarySigningPfxPath = $null

try {
    Write-Host "Signing config: loading"
    $signingConfig = Get-SigningConfig
    Write-Host "Signing config: loaded"
    if ($signingConfig) {
        $temporarySigningPfxPath = $signingConfig.TemporaryPfxPath
        Write-Host "Code signing : enabled"
        if ($signingConfig.TrustSelfSigned) {
            Write-Host "Signing trust: validating self-signed signatures by expected signer thumbprint"
            Write-Host "Timestamping : disabled for self-signed signing"
        }
    } else {
        Write-Host "Code signing : disabled"
    }

    if (-not $SkipBuild) {
        Push-Location $repoRoot
        try {
            & zig build -Demit-exe=true -Demit-lib-vt=true -Doptimize=ReleaseFast "-Dtarget=$zigTarget" -Dcpu=baseline "-Dversion-string=$Version"
            if ($LASTEXITCODE -ne 0) {
                throw "zig build failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }

    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Expected build output was not found: $exePath"
    }

    Write-Host "Packaging arch : $Architecture ($zigTarget)"
    foreach ($runtimeFile in $runtimeFiles) {
        $runtimePath = Join-Path $zigOutBin $runtimeFile
        if (-not (Test-Path -LiteralPath $runtimePath)) {
            throw "Expected build output was not found: $runtimePath"
        }
        Assert-PeMachine -PathToCheck $runtimePath -ExpectedArchitecture $Architecture
    }
    Assert-ParamuxVersionInfo `
        -PathToCheck (Join-Path $zigOutBin "paramux.exe") `
        -ExpectedVersion $Version `
        -ExpectedOriginalFilename "paramux.exe"
    Assert-ParamuxVersionInfo `
        -PathToCheck (Join-Path $zigOutBin "paramux.com") `
        -ExpectedVersion $Version `
        -ExpectedOriginalFilename "paramux.com"
    if ($Architecture -eq "x64") {
        & (Join-Path $repoRoot "scripts/check-windows-x64-baseline.ps1") -Path $exePath
    }

    Write-Host "Packaging phase: stage portable tree"
    Remove-TreeIfPresent -PathToRemove $stageBase
    New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null

    foreach ($runtimeFile in $runtimeFiles) {
        $runtimePath = Join-Path $zigOutBin $runtimeFile
        if (-not (Test-Path -LiteralPath $runtimePath)) {
            throw "Expected runtime artifact was not found: $runtimePath"
        }

        $destinationPath = Join-Path $portableRoot $runtimeFile
        Copy-Item -LiteralPath $runtimePath -Destination $destinationPath -Force

        if ($signingConfig -and @(".com", ".exe", ".dll") -contains [System.IO.Path]::GetExtension($destinationPath)) {
            Invoke-SignFile -SigningConfig $signingConfig -PathToSign $destinationPath
            Assert-ValidSignature -PathToCheck $destinationPath -SigningConfig $signingConfig
        }
    }

    Copy-Item -LiteralPath $licensePath -Destination (Join-Path $portableRoot "LICENSE") -Force
    Copy-Item -LiteralPath $configTemplatePath -Destination (Join-Path $portableRoot "config-template.ghostty") -Force
    Copy-Item -LiteralPath $readmePath -Destination (Join-Path $portableRoot "README.md") -Force
    Copy-Item -LiteralPath $iconPath -Destination (Join-Path $portableRoot "paramux.ico") -Force
    Copy-Item -LiteralPath $releaseIconSourcePath -Destination $releaseIconPath -Force
    # PATH installer so `paramux` works as a command (run install-paramux.cmd).
    Copy-Item -LiteralPath (Join-Path $repoRoot "dist/windows/install-paramux.ps1") -Destination (Join-Path $portableRoot "install-paramux.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "dist/windows/install-paramux.cmd") -Destination (Join-Path $portableRoot "install-paramux.cmd") -Force
    Copy-Item -LiteralPath $codexHookLauncherPath -Destination (Join-Path $portableRoot "paramux-codex-hook.cmd") -Force
    Copy-Item -LiteralPath $hookConfiguratorPath -Destination (Join-Path $portableRoot "configure-paramux-hooks.ps1") -Force

    $agentHooksDestination = Join-Path $portableRoot "agent-hooks"
    New-Item -ItemType Directory -Path $agentHooksDestination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $agentHooksPath -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $agentHooksDestination -Recurse -Force
    }
    foreach ($requiredHookFile in @(
        "README.md",
        "claude-code.settings.json",
        "codex/hooks.json",
        "codex/paramux-hook.cjs",
        "gemini-paramux/gemini-extension.json",
        "gemini-paramux/hooks/hooks.json",
        "gemini-paramux/scripts/notify.cjs",
        "gemini-paramux/scripts/notify.cmd",
        "opencode/paramux.js"
    )) {
        $hookPath = Join-Path $agentHooksDestination $requiredHookFile
        if (-not (Test-Path -LiteralPath $hookPath)) {
            throw "Expected packaged agent hook file was not staged: $hookPath"
        }
    }

    $configPresetsDestination = Join-Path $portableRoot "config-presets"
    New-Item -ItemType Directory -Path $configPresetsDestination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $configPresetsPath -File -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $configPresetsDestination -Force
    }
    $tmuxPrefixPresetPath = Join-Path $configPresetsDestination "tmux-prefix.ghostty"
    if (-not (Test-Path -LiteralPath $tmuxPrefixPresetPath)) {
        throw "Expected tmux-prefix config preset was not staged: $tmuxPrefixPresetPath"
    }
    # The packaged binary can only run when the host can execute it: ARM64
    # Windows emulates x64, but x64 hosts cannot run ARM64 PEs. release.yml
    # packages arm64 on an x64 runner, and windows-arm64.yml still exercises
    # this validation natively.
    $hostArchitecture = Get-DefaultWindowsPackageArchitecture
    $canExecutePackagedBinary = ($Architecture -eq $hostArchitecture) -or ($Architecture -eq "x64" -and $hostArchitecture -eq "arm64")
    if ($canExecutePackagedBinary) {
        & (Join-Path $portableRoot "paramux.com") "+validate-config" "--config-file=$tmuxPrefixPresetPath"
        if ($LASTEXITCODE -ne 0) {
            throw "Packaged tmux-prefix preset failed config validation with exit code $LASTEXITCODE."
        }
    } else {
        Write-Host "Skipping tmux-prefix preset runtime validation: $Architecture binary cannot execute on $hostArchitecture host."
    }

    if (Test-Path -LiteralPath $zigOutShare) {
        Copy-Tree -Source $zigOutShare -Destination $portableRoot

        # Incremental build trees can retain completion files installed under
        # the predecessor command name. They are compatibility-irrelevant and
        # must not leak into a Paramux package.
        $legacyCompletionPaths = @(
            "share\bash-completion\completions\ghostty.bash",
            "share\fish\vendor_completions.d\ghostty.fish",
            "share\zsh\site-functions\_ghostty"
        )
        foreach ($relativePath in $legacyCompletionPaths) {
            $legacyPath = Join-Path $portableRoot $relativePath
            if (Test-Path -LiteralPath $legacyPath) {
                Write-Host "Excluding legacy completion: $relativePath"
                Remove-Item -LiteralPath $legacyPath -Force
            }
        }

        $paramuxCompletionPaths = @(
            "share\bash-completion\completions\paramux.bash",
            "share\fish\vendor_completions.d\paramux.fish",
            "share\zsh\site-functions\_paramux"
        )
        foreach ($relativePath in $paramuxCompletionPaths) {
            $completionPath = Join-Path $portableRoot $relativePath
            if (-not (Test-Path -LiteralPath $completionPath)) {
                throw "Expected Paramux completion was not staged: $completionPath"
            }
        }
    }

    $portableReadmePath = Join-Path $portableRoot "README.md"
    $portableReadme = Get-Content -LiteralPath $portableReadmePath -Raw
    if ($portableReadme -notmatch '(?m)^# Paramux Portable for Windows$') {
        throw "Portable README is missing its Paramux identity: $portableReadmePath"
    }
    if ($portableReadme -match '(?i)winghostty') {
        throw "Portable README contains predecessor product branding: $portableReadmePath"
    }
    if ($portableReadme -match '\]\((?!https://|mailto:|#)[^)]+\)') {
        throw "Portable README contains a relative Markdown link that will break after extraction: $portableReadmePath"
    }

    Write-Host "Packaging phase: create portable zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $portableRoot,
        $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true
    )

    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace("\", "/") })
        foreach ($requiredEntry in @(
            "paramux/README.md",
            "paramux/paramux.exe",
            "paramux/paramux.com",
            "paramux/paramux-codex-hook.cmd",
            "paramux/configure-paramux-hooks.ps1",
            "paramux/agent-hooks/README.md",
            "paramux/agent-hooks/claude-code.settings.json",
            "paramux/agent-hooks/codex/hooks.json",
            "paramux/agent-hooks/codex/paramux-hook.cjs",
            "paramux/agent-hooks/gemini-paramux/gemini-extension.json",
            "paramux/agent-hooks/gemini-paramux/hooks/hooks.json",
            "paramux/agent-hooks/gemini-paramux/scripts/notify.cjs",
            "paramux/agent-hooks/gemini-paramux/scripts/notify.cmd",
            "paramux/agent-hooks/opencode/paramux.js",
            "paramux/config-presets/tmux-prefix.ghostty",
            "paramux/share/bash-completion/completions/paramux.bash",
            "paramux/share/fish/vendor_completions.d/paramux.fish",
            "paramux/share/zsh/site-functions/_paramux"
        )) {
            if ($entryNames -notcontains $requiredEntry) {
                throw "Portable ZIP is missing required entry: $requiredEntry"
            }
        }
        foreach ($legacyEntry in @(
            "paramux/share/bash-completion/completions/ghostty.bash",
            "paramux/share/fish/vendor_completions.d/ghostty.fish",
            "paramux/share/zsh/site-functions/_ghostty"
        )) {
            if ($entryNames -contains $legacyEntry) {
                throw "Portable ZIP contains a legacy command completion: $legacyEntry"
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    Write-Host "Packaging phase: build installer"
    $iscc = if ($SkipInstaller) { $null } else { Get-Command ISCC.exe -ErrorAction SilentlyContinue }
    if (-not $SkipInstaller -and -not $iscc) {
        $candidates = @(
            (Join-Path $localAppData "Programs\Inno Setup 6\ISCC.exe"),
            "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
            "C:\Program Files\Inno Setup 6\ISCC.exe"
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) {
                $iscc = @{ Source = $candidate }
                break
            }
        }
    }

    if ($SkipInstaller) {
        Write-Host "Installer build: skipped by request"
    }
    elseif ($iscc) {
        & $iscc.Source `
            "/DMyAppVersion=$Version" `
            "/DPackageArch=$Architecture" `
            "/DStageDir=$portableRoot" `
            "/DOutputDir=$stageBase" `
            "/DSourceDir=$repoRoot" `
            $innoScriptPath

        if ($LASTEXITCODE -ne 0) {
            throw "ISCC.exe failed with exit code $LASTEXITCODE."
        }
    }
    elseif ($RequireInstaller) {
        throw "Inno Setup compiler (ISCC.exe) was not found."
    }
    else {
        Write-Warning "ISCC.exe not found. Skipping installer build."
    }

    if ($signingConfig -and (Test-Path -LiteralPath $installerPath)) {
        Invoke-SignFile -SigningConfig $signingConfig -PathToSign $installerPath
        Assert-ValidSignature -PathToCheck $installerPath -SigningConfig $signingConfig
    }
    elseif ($signingConfig -and $RequireInstaller) {
        throw "Signing was enabled, but the installer artifact was not produced."
    }

    Write-Host "Packaging phase: write checksums"
    $hashTargets = @(
        @{
            Name = [System.IO.Path]::GetFileName($zipPath)
            Path = $zipPath
        }
    )

    if (Test-Path -LiteralPath $installerPath) {
        $hashTargets += @{
            Name = [System.IO.Path]::GetFileName($installerPath)
            Path = $installerPath
        }
    }

    $hashLines = foreach ($target in $hashTargets) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target.Path).Hash.ToLowerInvariant()
        "$hash *$($target.Name)"
    }

    Set-Content -LiteralPath $checksumsPath -Value $hashLines

    Write-Host "Portable ZIP: $zipPath"
    if (Test-Path -LiteralPath $installerPath) {
        Write-Host "Installer    : $installerPath"
    }
    Write-Host "Checksums    : $checksumsPath"
}
finally {
    if ($temporarySigningPfxPath -and (Test-Path -LiteralPath $temporarySigningPfxPath)) {
        Remove-Item -LiteralPath $temporarySigningPfxPath -Force
    }
}
