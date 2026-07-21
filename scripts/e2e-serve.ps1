# serve E2E: boots paramux + `paramux serve`, then proves the HTTP
# contract end to end — auth on the content routes, ETag/304 revalidation
# on /attention, and a live /status body.
#
#   powershell -File scripts/e2e-serve.ps1
param(
    [string]$Binary = "zig-out/bin/paramux.exe",
    [string]$Com = "zig-out/bin/paramux.com",
    [int]$Port = 7893
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Binary)) { Write-Error "Build first: zig build -Demit-exe=true" }
$fails = @()
function Check([string]$name, [bool]$ok) {
    if ($ok) { Write-Host "PASS $name" } else { Write-Host "FAIL $name"; $script:fails += $name }
}

$proc = Start-Process -FilePath $Binary -PassThru
Start-Sleep -Seconds 4
$serve = Start-Process $Com -ArgumentList "serve", "--port=$Port" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$token = (Get-Content (Join-Path $env:LOCALAPPDATA "paramux\paramux-ipc-token") -Raw).Trim()
$auth = @{Authorization = "Bearer $token"}
$base = "http://127.0.0.1:$Port"

try {
    $st = Invoke-WebRequest -Uri "$base/status" -UseBasicParsing -TimeoutSec 10
    Check "/status 200" ($st.StatusCode -eq 200)
    Check "/status body has windows" ($st.Content -match '"windows"')

    $att = Invoke-WebRequest -Uri "$base/attention" -Headers $auth -UseBasicParsing -TimeoutSec 10
    Check "/attention 200 with token" ($att.StatusCode -eq 200)
    $etag = $att.Headers["ETag"]
    Check "/attention sends ETag" (-not [string]::IsNullOrEmpty($etag))

    $code401 = 0
    try { Invoke-WebRequest -Uri "$base/attention" -UseBasicParsing -TimeoutSec 10 | Out-Null }
    catch { $code401 = [int]$_.Exception.Response.StatusCode }
    Check "/attention 401 without token" ($code401 -eq 401)

    $code304 = 0
    try {
        Invoke-WebRequest -Uri "$base/attention" -UseBasicParsing -TimeoutSec 10 `
            -Headers @{Authorization = "Bearer $token"; "If-None-Match" = $etag} | Out-Null
    } catch { $code304 = [int]$_.Exception.Response.StatusCode }
    Check "/attention 304 on matching ETag" ($code304 -eq 304)

    # Pane text route, both sides of the auth gate. The id comes from a
    # regex over the raw JSON: ConvertFrom-Json would round u64 ids
    # through a double and corrupt them.
    $sid = ([regex]::Match($st.Content, '"surface_id":(\d+)')).Groups[1].Value
    Check "/status carries a pane id" (-not [string]::IsNullOrEmpty($sid))
    if ($sid) {
        $pt = Invoke-WebRequest -Uri "$base/panes/$sid/text" -Headers $auth -UseBasicParsing -TimeoutSec 10
        Check "/panes/<id>/text 200 with token" ($pt.StatusCode -eq 200)
        $ptCode = 0
        try { Invoke-WebRequest -Uri "$base/panes/$sid/text" -UseBasicParsing -TimeoutSec 10 | Out-Null }
        catch { $ptCode = [int]$_.Exception.Response.StatusCode }
        Check "/panes/<id>/text 401 without token" ($ptCode -eq 401)
    }
} finally {
    if ($serve -and -not $serve.HasExited) { Stop-Process -Id $serve.Id -Force -ErrorAction SilentlyContinue }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

if ($fails.Count -gt 0) { Write-Error "serve E2E FAILED: $($fails -join ', ')" }
Write-Host "serve E2E PASS (9 checks)"
