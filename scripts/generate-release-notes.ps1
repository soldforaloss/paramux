# Draft release notes from commit subjects since the last tag,
# grouped by the conventional "area:" prefix this repo uses. Output is
# a starting skeleton — the published notes are still written by hand
# (the generator can't know what deserves the headline).
#
#   powershell -File scripts/generate-release-notes.ps1                 # since latest tag
#   powershell -File scripts/generate-release-notes.ps1 -FromTag v0.1.8
#   powershell -File scripts/generate-release-notes.ps1 -Out draft.md
param(
    [string]$FromTag = "",
    [string]$To = "HEAD",
    [string]$Out = ""
)
$ErrorActionPreference = "Stop"

if (-not $FromTag) {
    $FromTag = (git describe --tags --abbrev=0 $To).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $FromTag) { Write-Error "no tag found; pass -FromTag" }
}
$range = "$FromTag..$To"
$subjects = @(git log --no-merges --format="%s" $range)
if ($LASTEXITCODE -ne 0) { Write-Error "git log failed for range $range" }

$groups = [ordered]@{}
foreach ($subject in $subjects) {
    if ($subject -match '^([a-z0-9-]+):\s*(.+)$') {
        $area = $Matches[1]
        $rest = $Matches[2]
    } else {
        $area = "other"
        $rest = $subject
    }
    if (-not $groups.Contains($area)) { $groups[$area] = New-Object System.Collections.ArrayList }
    $null = $groups[$area].Add($rest)
}

$linesOut = New-Object System.Collections.ArrayList
$null = $linesOut.Add("# Draft notes: $range ($($subjects.Count) commits)")
$null = $linesOut.Add("")
$null = $linesOut.Add("<!-- Generated skeleton - pick headlines, merge related lines, add install footer. -->")
foreach ($area in $groups.Keys) {
    $null = $linesOut.Add("")
    $null = $linesOut.Add("## $area")
    $null = $linesOut.Add("")
    foreach ($entry in $groups[$area]) { $null = $linesOut.Add("- $entry") }
}

$text = $linesOut -join [Environment]::NewLine
if ($Out) {
    $text | Out-File $Out -Encoding utf8
    Write-Host "Wrote $Out ($($subjects.Count) commits since $FromTag)."
} else {
    $text
}
