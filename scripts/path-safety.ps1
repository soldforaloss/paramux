function Test-PathIsStrictDescendant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Candidate,

        [Parameter(Mandatory = $true)]
        [string] $Parent
    )

    $trimChars = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $candidatePath = [System.IO.Path]::GetFullPath($Candidate).TrimEnd($trimChars)
    $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd($trimChars)
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    if ([string]::Equals($candidatePath, $parentPath, $comparison)) {
        return $false
    }

    $parentPrefix = $parentPath + [System.IO.Path]::DirectorySeparatorChar
    return $candidatePath.StartsWith($parentPrefix, $comparison)
}
