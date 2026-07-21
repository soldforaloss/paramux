# Release ZIP smoke: hash vs SHA256SUMS, VERSIONINFO, version --json,
# plus fixed capability probes (gallery import usage, doctor gallery
# line, attention verb, restart_pane action). Run after
# package-windows.ps1:
#
#   powershell -File scripts/smoke-zip.ps1 -Version 0.1.17
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Architecture = "x64"
)
$ErrorActionPreference = "Stop"
$dist = "dist/artifacts/paramux-$Version-windows-$Architecture"
$zip = "$dist/paramux-$Version-windows-$Architecture-portable.zip"
$sums = "$dist/SHA256SUMS-windows-$Architecture.txt"
if (-not (Test-Path $zip)) { Write-Error "ZIP not found: $zip" }

$fails = @()
function Check([string]$name, [bool]$ok) {
    if ($ok) { Write-Host "PASS $name" } else { Write-Host "FAIL $name"; $script:fails += $name }
}

$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$expected = (@(Get-Content $sums) -match "portable.zip")[0].Split(" ")[0].ToLower()
Check "ZIP hash matches SHA256SUMS" ($actual -eq $expected)

$smoke = Join-Path $env:TEMP "paramux-smoke-$Version"
Remove-Item $smoke -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $zip -DestinationPath $smoke
$com = Get-ChildItem $smoke -Recurse -Filter "paramux.com" | Select-Object -First 1
$exe = Get-ChildItem $smoke -Recurse -Filter "paramux.exe" | Select-Object -First 1

$vi = (Get-Item $exe.FullName).VersionInfo
Check "VERSIONINFO product/file = $Version" ($vi.ProductVersion -eq $Version -and $vi.FileVersion -eq $Version)

$ErrorActionPreference = "Continue"
$vj = & $com.FullName version --json | Out-String
Check "version --json reports $Version" ($vj -match ('"version":"' + [regex]::Escape($Version) + '"'))

$imp = & $com.FullName import-layout 2>&1 | Out-String
Check "import-layout slot-less usage" ($imp -match "\[slot 1-5\]")

$doc = & $com.FullName doctor 2>&1 | Out-String
Check "doctor validates the gallery" ($doc -match "layout gallery: 4 bundled templates")

$att = & $com.FullName attention 2>&1 | Out-String
Check "attention verb present" ($att -match "no running paramux instance|panes")

$acts = & $com.FullName list-actions 2>&1 | Out-String
Check "restart_pane action listed" ($acts -match "restart_pane")

if ($fails.Count -gt 0) { $ErrorActionPreference = "Stop"; Write-Error "ZIP smoke FAILED: $($fails -join ', ')" }
Write-Host "ZIP SMOKE PASS ($Version $Architecture, 7 checks)"
