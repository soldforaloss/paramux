[CmdletBinding()]
param(
    # Kept for compatibility with existing local invocations. This verifies the
    # explicitly documented prerelease rather than GitHub's public "latest".
    [switch]$CheckRemoteLatest
)

$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
. (Join-Path $PSScriptRoot "windows-architecture.ps1")

$copyPaths = @(
    "README.md",
    "PACKAGING.md",
    "docs/getting-started.md",
    "docs/status.md",
    "docs/windows.md",
    "docs/windows-capability-matrix.md",
    "site/README.md",
    "site/components/hero/release-chip.jsx",
    "site/components/heroes.jsx",
    "site/components/release/release-block.jsx",
    "site/components/why/product-facts.jsx",
    "site/bundle.js"
)

$failures = New-Object System.Collections.Generic.List[string]
$textCache = @{}

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Get-Text {
    param([string]$RelativePath)

    if ($script:textCache.ContainsKey($RelativePath)) {
        return $script:textCache[$RelativePath]
    }

    $path = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $RelativePath))
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Missing checked copy file: $RelativePath"
        $script:textCache[$RelativePath] = $null
        return $null
    }

    $text = Get-Content -LiteralPath $path -Raw
    $script:textCache[$RelativePath] = $text
    return $text
}

function Require-Contains {
    param(
        [string]$RelativePath,
        [string]$Needle,
        [string]$Reason
    )

    $text = Get-Text -RelativePath $RelativePath
    if ($null -ne $text -and $text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Add-Failure "${RelativePath}: missing required text `"$Needle`" - $Reason"
    }
}

function Forbid-Contains {
    param(
        [string]$Needle,
        [string]$Reason
    )

    foreach ($relativePath in $copyPaths) {
        $text = Get-Text -RelativePath $relativePath
        if ($null -ne $text -and $text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Add-Failure "${relativePath}: forbidden text `"$Needle`" - $Reason"
        }
    }
}

function Test-RemoteReleasePayload {
    param(
        [string]$Tag,
        [string]$Version,
        [string]$PortableName,
        [string]$ChecksumsName,
        [switch]$KnownLegacyPayload
    )

    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $tempRoot = [System.IO.Path]::Combine($tempBase, "paramux-release-copy-$([guid]::NewGuid().ToString('N'))")
    if (-not $tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "Refusing unsafe remote-release temporary path: $tempRoot"
        return
    }

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        # Under $ErrorActionPreference = "Stop", Windows PowerShell 5.1 turns
        # any gh stderr line into a terminating NativeCommandError when stderr
        # is redirected, bypassing the $LASTEXITCODE handling below. Relax the
        # preference around the native call only.
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $downloadOutput = & gh release download $Tag `
                --repo soldforaloss/paramux `
                --dir $tempRoot `
                --pattern $PortableName `
                --pattern $ChecksumsName 2>&1
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($LASTEXITCODE -ne 0) {
            $downloadText = @($downloadOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            Add-Failure "Failed to download $Tag payload: $downloadText"
            return
        }

        $portablePath = Join-Path $tempRoot $PortableName
        $checksumsPath = Join-Path $tempRoot $ChecksumsName
        $checksumPattern = '^([0-9a-fA-F]{64}) \*' + [regex]::Escape($PortableName) + '$'
        $checksumLine = @(Get-Content -LiteralPath $checksumsPath | Where-Object { $_ -match $checksumPattern }) | Select-Object -First 1
        if (-not $checksumLine) {
            Add-Failure "$Tag checksum payload has no entry for $PortableName."
            return
        }
        [void]($checksumLine -match $checksumPattern)
        $expectedHash = $Matches[1].ToLowerInvariant()
        $actualHash = (Get-FileHash -LiteralPath $portablePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            Add-Failure "$Tag portable ZIP checksum mismatch."
            return
        }

        $extractRoot = Join-Path $tempRoot "expanded"
        Expand-Archive -LiteralPath $portablePath -DestinationPath $extractRoot
        $portableRoot = Join-Path $extractRoot "paramux"
        if ($KnownLegacyPayload) {
            # The pinned prerelease is a documented legacy test artifact whose
            # payload predates the package-level Paramux rebrand. Its checksum,
            # asset list, and prerelease status are still enforced above; only
            # the new-branding invariants are skipped, and this carve-out
            # expires automatically when the pinned version changes.
            Write-Host "Skipping portable README branding check: $Tag is a documented legacy payload."
            Write-Host "Skipping predecessor-text scan: $Tag is a documented legacy payload."
            Write-Host "Skipping VERSIONINFO check: $Tag is a documented legacy payload."
            Write-Host "Skipping legacy-completion check: $Tag is a documented legacy payload."
        } else {
            $portableReadmePath = Join-Path $portableRoot "README.md"
            $portableReadme = Get-Content -LiteralPath $portableReadmePath -Raw
            if ($portableReadme -notmatch '(?m)^# Paramux Portable for Windows$') {
                Add-Failure "$Tag ships a README without the portable Paramux identity."
            }
            if ($portableReadme -match '(?i)winghostty') {
                Add-Failure "$Tag ships predecessor product branding in its portable README."
            }

            foreach ($name in @("paramux.exe", "paramux.com")) {
                $versionInfo = (Get-Item -LiteralPath (Join-Path $portableRoot $name)).VersionInfo
                if ($versionInfo.ProductName -ne "Paramux" -or
                    $versionInfo.OriginalFilename -ne $name -or
                    $versionInfo.FileVersion -ne $Version -or
                    $versionInfo.ProductVersion -ne $Version) {
                    Add-Failure "$Tag ships incomplete Paramux VERSIONINFO in $name."
                }
            }

            foreach ($relativePath in @(
                "share\bash-completion\completions\ghostty.bash",
                "share\fish\vendor_completions.d\ghostty.fish",
                "share\zsh\site-functions\_ghostty"
            )) {
                if (Test-Path -LiteralPath (Join-Path $portableRoot $relativePath)) {
                    Add-Failure "$Tag ships a predecessor command completion: $relativePath"
                }
            }
        }
    } catch {
        Add-Failure "Failed to inspect $Tag payload: $($_.Exception.Message)"
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

$readme = Get-Text -RelativePath "README.md"
$version = $null
if ($null -ne $readme -and $readme -match 'releases/tag/v([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?)') {
    $version = $Matches[1]
} else {
    Add-Failure "README.md: could not find an explicitly tagged semantic release."
}

Forbid-Contains -Needle "releases/latest" -Reason "The prerelease must use an explicit, reviewable tag."
Forbid-Contains -Needle "winget install" -Reason "Paramux has no published WinGet package."
Forbid-Contains -Needle "scoop install" -Reason "Paramux has no published Scoop package."

if ($version) {
    $tag = "v$version"
    $portableName = New-WindowsPackageArtifactName -Version $version -Architecture "x64" -Kind "portable"
    $checksumsName = New-WindowsPackageArtifactName -Version $version -Architecture "x64" -Kind "checksums"
    # ARM64 portable + checksums publish alongside x64 since v0.1.9;
    # only signed installers remain unpublished.
    $unpublishedArtifacts = @(
        (New-WindowsPackageArtifactName -Version $version -Architecture "x64" -Kind "setup"),
        (New-WindowsPackageArtifactName -Version $version -Architecture "arm64" -Kind "setup")
    )

    foreach ($path in @("README.md", "PACKAGING.md", "docs/getting-started.md", "docs/status.md", "docs/windows.md")) {
        Require-Contains -RelativePath $path -Needle $tag -Reason "Current release copy must agree on the pinned prerelease."
        Require-Contains -RelativePath $path -Needle $portableName -Reason "Current release copy must name the only executable artifact."
        Require-Contains -RelativePath $path -Needle $checksumsName -Reason "Current release copy must name its checksum asset."
        Require-Contains -RelativePath $path -Needle "unsigned" -Reason "The current executable has no Authenticode signature."
    }

    Require-Contains -RelativePath "README.md" -Needle "install-paramux.cmd" -Reason "The documented install path is the portable PATH helper."
    Require-Contains -RelativePath "PACKAGING.md" -Needle "publishes exactly these four assets" -Reason "Packaging copy must separate current artifacts from future channels."
    Require-Contains -RelativePath "docs/status.md" -Needle "x64 only" -Reason "Status must not imply a verified ARM64 release."
    Require-Contains -RelativePath "site/components/hero/release-chip.jsx" -Needle $version -Reason "The site badge must match the README prerelease."
    Require-Contains -RelativePath "site/components/heroes.jsx" -Needle "releases/tag/$tag" -Reason "The site CTA must point at the pinned release."
    Require-Contains -RelativePath "site/components/release/release-block.jsx" -Needle $tag -Reason "The site release facts must match the README prerelease."
    Require-Contains -RelativePath "site/components/why/product-facts.jsx" -Needle $tag -Reason "The site product facts must match the README prerelease."
    Require-Contains -RelativePath "site/bundle.js" -Needle $tag -Reason "The generated site bundle must be rebuilt after release-copy changes."

    if ($version -eq "0.1.0-paramux.4") {
        foreach ($path in @(
            "README.md",
            "PACKAGING.md",
            "docs/getting-started.md",
            "docs/status.md",
            "site/components/release/release-block.jsx",
            "site/components/why/product-facts.jsx",
            "site/bundle.js"
        )) {
            Require-Contains -RelativePath $path -Needle "legacy test artifact" -Reason "v4 has a verified legacy-branded payload and must carry an explicit warning."
        }
    }

    foreach ($artifact in $unpublishedArtifacts) {
        Forbid-Contains -Needle $artifact -Reason "The pinned prerelease did not publish this artifact."
    }

    if ($CheckRemoteLatest) {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Add-Failure "Cannot verify the remote prerelease because gh is not installed."
        } else {
            # See Test-RemoteReleasePayload: relax EAP=Stop around the native
            # gh call so a stderr line cannot bypass $LASTEXITCODE handling in
            # Windows PowerShell 5.1.
            $previousErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $ghOutput = & gh release view $tag --repo soldforaloss/paramux --json tagName,publishedAt,assets,isPrerelease,isDraft 2>&1
            } finally {
                $ErrorActionPreference = $previousErrorActionPreference
            }
            if ($LASTEXITCODE -ne 0) {
                $ghText = @($ghOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
                Add-Failure "gh release view failed for ${tag}: $ghText"
            } else {
                try {
                    # Keep stderr records (e.g. gh update nags) out of the JSON.
                    $jsonText = @($ghOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
                    $release = $jsonText | ConvertFrom-Json
                } catch {
                    Add-Failure "Failed to parse gh release JSON: $($_.Exception.Message)"
                    $release = $null
                }

                if ($release) {
                    if ($release.tagName -ne $tag) {
                        Add-Failure "README release is $tag, but GitHub returned $($release.tagName)."
                    }
                    if (-not $release.isPrerelease -or $release.isDraft) {
                        Add-Failure "$tag must remain a published prerelease, not a stable release or draft."
                    }

                    $assetNames = @($release.assets | ForEach-Object { [string]$_.name })
                    # Dual-arch since v0.1.9: the ARM64 pair is expected.
                    $arm64Portable = New-WindowsPackageArtifactName -Version $version -Architecture "arm64" -Kind "portable"
                    $arm64Checksums = New-WindowsPackageArtifactName -Version $version -Architecture "arm64" -Kind "checksums"
                    $expectedAssets = @($portableName, $checksumsName, $arm64Portable, $arm64Checksums)
                    $unexpectedAssets = @($assetNames | Where-Object { $_ -notin $expectedAssets })
                    $missingAssets = @($expectedAssets | Where-Object { $_ -notin $assetNames })
                    if ($unexpectedAssets.Count -gt 0) {
                        Add-Failure "$tag has undocumented assets: $($unexpectedAssets -join ', ')."
                    }
                    if ($missingAssets.Count -gt 0) {
                        Add-Failure "$tag is missing documented assets: $($missingAssets -join ', ')."
                    }

                    try {
                        $publishedDate = [DateTimeOffset]::Parse([string]$release.publishedAt).UtcDateTime.ToString("yyyy-MM-dd")
                        Require-Contains -RelativePath "README.md" -Needle "published $publishedDate" -Reason "README release date must match GitHub."
                    } catch {
                        Add-Failure "Could not parse GitHub publishedAt date: $($release.publishedAt)"
                    }

                    Test-RemoteReleasePayload `
                        -Tag $tag `
                        -Version $version `
                        -PortableName $portableName `
                        -ChecksumsName $checksumsName `
                        -KnownLegacyPayload:($version -eq "0.1.0-paramux.4")
                }
            }
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Release copy checks failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Release copy checks passed." -ForegroundColor Green
