# Layout round-trip E2E: gallery -> slot -> export -> re-import ->
# export again, asserting byte-identical template bodies. Runs against
# any paramux.com (default the dev build; point -Com at a packaged
# binary to smoke a release).
#
#   powershell -File scripts/e2e-layout-roundtrip.ps1
param(
    [string]$Com = "zig-out/bin/paramux.com"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Com)) { Write-Error "Binary not found: $Com" }
$Com = (Resolve-Path $Com).Path
$work = Join-Path $env:TEMP "paramux-layout-rt"
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $work | Out-Null

$ErrorActionPreference = "Continue"
& $Com import-layout 3 grid-2x2 --name=rt-a | Out-Null
if ($LASTEXITCODE -ne 0) { throw "import into slot 3 failed" }
& $Com export-layout 3 (Join-Path $work "a.layout.json") | Out-Null
if ($LASTEXITCODE -ne 0) { throw "export from slot 3 failed" }
& $Com import-layout 4 (Join-Path $work "a.layout.json") --name=rt-b | Out-Null
if ($LASTEXITCODE -ne 0) { throw "re-import into slot 4 failed" }
& $Com export-layout --name=rt-b (Join-Path $work "b.layout.json") | Out-Null
if ($LASTEXITCODE -ne 0) { throw "export by name failed" }

$a = Get-Content (Join-Path $work "a.layout.json") -Raw
$b = Get-Content (Join-Path $work "b.layout.json") -Raw
if ($a -ne $b) { throw "round-trip bodies differ" }
Write-Host "E2E LAYOUT ROUND-TRIP PASS (slot->file->slot->file byte-identical)"
