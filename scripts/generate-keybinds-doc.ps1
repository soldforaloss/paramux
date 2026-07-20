# Regenerates docs/paramux/keybinds.md from the built binary's actual
# default keybinds, so the doc can never drift from the code.
#
#   powershell -File scripts/generate-keybinds-doc.ps1
#
# Requires zig-out/bin/paramux.com (run `zig build -Demit-exe=true` first).
param(
    [string]$Binary = "zig-out/bin/paramux.com",
    [string]$OutFile = "docs/paramux/keybinds.md"
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $Binary)) {
    Write-Error "Binary not found: $Binary (build first with: zig build -Demit-exe=true)"
}

$lines = & $Binary list-keybinds
if ($LASTEXITCODE -ne 0) { Write-Error "list-keybinds failed with exit $LASTEXITCODE" }

$rows = foreach ($line in $lines) {
    if ($line -match '^keybind = (.+?)=(.+)$') {
        [pscustomobject]@{ Chord = $Matches[1]; Action = $Matches[2] }
    }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Default keybinds")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Generated from ``paramux list-keybinds`` by ``scripts/generate-keybinds-doc.ps1`` -- do not edit by hand; regenerate after changing defaults in ``src/config/Config.zig``.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Chord | Action |")
[void]$sb.AppendLine("| --- | --- |")
foreach ($row in $rows) {
    [void]$sb.AppendLine("| ``$($row.Chord)`` | ``$($row.Action)`` |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("$($rows.Count) bindings.")

$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
Write-Host "Wrote $OutFile ($($rows.Count) bindings)."
