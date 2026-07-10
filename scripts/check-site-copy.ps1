param()

$ErrorActionPreference = "Stop"

$siteRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\site"))
if (-not (Test-Path -LiteralPath $siteRoot)) {
    throw "Site root not found: $siteRoot"
}

$nodeModulesRoot = [System.IO.Path]::GetFullPath((Join-Path $siteRoot "node_modules"))
$siteItems = @(Get-ChildItem -LiteralPath $siteRoot -Recurse -Force | Where-Object {
    -not $_.FullName.StartsWith($nodeModulesRoot, [System.StringComparison]::OrdinalIgnoreCase)
})
$textFiles = @($siteItems | Where-Object {
    -not $_.PSIsContainer -and
    $_.Extension -in @(".html", ".css", ".js", ".jsx", ".md", ".txt", ".svg")
})
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Require-FileText {
    param(
        [string]$RelativePath,
        [string]$Needle,
        [string]$Reason
    )

    $path = Join-Path $siteRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Missing required file: $RelativePath"
        return
    }

    $text = Get-Content -LiteralPath $path -Raw
    if ($text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Add-Failure "${RelativePath}: missing `"$Needle`" - $Reason"
    }
}

$forbiddenRules = @(
    @{ Pattern = "winget install"; Reason = "Paramux has no public WinGet package." },
    @{ Pattern = "scoop install"; Reason = "Paramux has no public Scoop package." },
    @{ Pattern = "releases/latest"; Reason = "The prerelease CTA must use an explicit tag." },
    @{ Pattern = "D3D11"; Reason = "The shipping renderer is OpenGL 4.3 through WGL." },
    @{ Pattern = "DirectX 11"; Reason = "The shipping renderer is OpenGL 4.3 through WGL." },
    @{ Pattern = "%APPDATA%\paramux\config"; Reason = "The real config root is under LOCALAPPDATA." },
    @{ Pattern = "downloads updates automatically"; Reason = "The current portable prerelease is updated manually." },
    @{ Pattern = "silent auto-update"; Reason = "The current portable prerelease is updated manually." },
    @{ Pattern = "full parity"; Reason = "Capability parity is still in progress." }
)

foreach ($rule in $forbiddenRules) {
    foreach ($match in @(Select-String -LiteralPath $textFiles.FullName -SimpleMatch -Pattern $rule.Pattern)) {
        Add-Failure ("{0}:{1}: forbidden text `"{2}`" - {3}" -f $match.Path, $match.LineNumber, $rule.Pattern, $rule.Reason)
    }
}

$staleNames = @($siteItems | Where-Object { $_.Name -like "*winghostty*" })
foreach ($item in $staleNames) {
    Add-Failure "Stale predecessor-branded site path: $($item.FullName)"
}

$versionSource = Join-Path $siteRoot "components\hero\release-chip.jsx"
$version = $null
if (Test-Path -LiteralPath $versionSource) {
    $versionText = Get-Content -LiteralPath $versionSource -Raw
    if ($versionText -match "PARAMUX_VERSION\s*=\s*'([^']+)'") {
        $version = $Matches[1]
    }
}
if (-not $version) {
    Add-Failure "components/hero/release-chip.jsx: could not parse PARAMUX_VERSION."
} else {
    $tag = "v$version"
    Require-FileText -RelativePath "components\heroes.jsx" -Needle "releases/tag/$tag" -Reason "The primary CTA must point at the pinned prerelease."
    Require-FileText -RelativePath "components\release\release-block.jsx" -Needle $tag -Reason "Release facts must agree with the hero badge."
    Require-FileText -RelativePath "components\why\product-facts.jsx" -Needle $tag -Reason "Product facts must agree with the hero badge."
    Require-FileText -RelativePath "bundle.js" -Needle $tag -Reason "The generated bundle must be current."
}

Require-FileText -RelativePath "index.html" -Needle "Paramux" -Reason "Document metadata must use the product brand."
Require-FileText -RelativePath "bundle.js" -Needle "public prerelease" -Reason "The release badge must reflect public availability."
Require-FileText -RelativePath "bundle.js" -Needle "Windows x64" -Reason "The only verified release architecture is x64."
Require-FileText -RelativePath "bundle.js" -Needle "unsigned" -Reason "The current binary is not Authenticode signed."
Require-FileText -RelativePath "bundle.js" -Needle "LOCALAPPDATA" -Reason "Automation copy must use the real local state root."
Require-FileText -RelativePath "bundle.js" -Needle "paramux.windows.v2" -Reason "The automation demo must use the current discovery schema."
Require-FileText -RelativePath "bundle.js" -Needle "working" -Reason "The mission-control demo must show agent attention states."
Require-FileText -RelativePath "bundle.js" -Needle "waiting" -Reason "The mission-control demo must show agent attention states."
Require-FileText -RelativePath "bundle.js" -Needle "done" -Reason "The mission-control demo must show agent attention states."
Require-FileText -RelativePath "bundle.js" -Needle "error" -Reason "The mission-control demo must show agent attention states."
Require-FileText -RelativePath "bundle.js" -Needle "https://github.com/soldforaloss/paramux" -Reason "The site must retain a repository link."

if ($failures.Count -gt 0) {
    Write-Host "Site copy checks failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Site copy checks passed." -ForegroundColor Green
