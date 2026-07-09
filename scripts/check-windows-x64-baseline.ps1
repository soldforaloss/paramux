<#
.SYNOPSIS
    Fail the build if an x64 PE contains AMD-only SSE4a EXTRQ/INSERTQ
    instructions, which crash (illegal instruction) on Intel CPUs and violate
    the baseline x86-64 target guarantee.

.DESCRIPTION
    The SSE4a instructions EXTRQ/INSERTQ encode as the byte triples
    66/F2 0F 78/79. A naive scan of .text for those bytes produces FALSE
    POSITIVES, because the same three bytes routinely occur inside another
    instruction's RIP-relative displacement or immediate (e.g. the disp32 of a
    `lea rdx,[rip+X]`). A `-Dcpu=baseline` build provably cannot emit SSE4a, so
    every such hit is coincidental operand data — but a byte scan cannot tell
    the difference, and whether it fires is layout-dependent (flaky across
    builds).

    This check therefore only treats a hit as real when it lands at an actual
    instruction boundary. It scans for candidate byte triples first (cheap); if
    there are none it passes immediately with no disassembler needed (the common
    case). When a candidate exists, it disassembles .text with dumpbin (which
    ships with the MSVC toolchain used to build the -windows-msvc target) and
    checks whether the candidate's address is a printed instruction start. A
    boundary-aligned 66/F2 0F 78/79 is genuinely EXTRQ/INSERTQ and fails the
    build; a hit inside another instruction is ignored. If a candidate exists
    but no disassembler can be found, the check fails closed (it will not pass a
    binary it cannot verify).

.NOTES
    Boundary detection is disassembler-agnostic: it only relies on dumpbin
    printing an address at each instruction start, not on dumpbin knowing the
    (obscure, AMD-only) SSE4a mnemonics.

    Scoped assumptions (intentional; valid for the Zig + MSVC/LLD x64 toolchain
    that builds this project):
      * Scans the .text section only. This toolchain consolidates all code
        (including statically-linked objects) into a single executable .text
        section, so SSE4a cannot hide in a differently-named code section.
      * Detects EXTRQ/INSERTQ (66/F2 [REX] 0F 78/79), the SSE4a forms a compiler
        would plausibly mis-emit; it does not scan for MOVNTSS/MOVNTSD.
      * Boundary confirmation uses dumpbin's linear sweep, which is reliable
        because the compiler emits linear-sweepable code and places jump tables
        in .rdata, not inline in .text. If a candidate exists but the sweep does
        not reach its region, the check fails closed rather than guessing.
#>
param(
    [string] $Path,
    [switch] $SelfTest,
    [string] $DumpbinPath
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Core, testable logic
# ---------------------------------------------------------------------------

# Scan a .text byte buffer for candidate SSE4a EXTRQ/INSERTQ byte triples
# (66/F2 0F 78/79). Returns one object per hit with its position + address.
function Find-Sse4aCandidates {
    param(
        [byte[]] $Text,
        [uint32] $TextVA,
        [uint64] $ImageBase
    )

    $out = @()
    # Latin-1 (codepage 28591) maps each byte 1:1 to the same code point, so a
    # .NET regex over the string view matches raw bytes and $m.Index is the byte
    # offset. This is orders of magnitude faster than a per-byte PowerShell loop
    # over a multi-MB .text.
    #
    # Pattern: the mandatory prefix (66 for EXTRQ, F2 for INSERTQ), an OPTIONAL
    # REX prefix (0x40-0x4F), then 0F 78/79. The REX byte is required to address
    # xmm8-xmm15 and sits between the mandatory prefix and the opcode, e.g.
    # `INSERTQ xmm1,xmm8` = F2 44 0F 79 C8 -- omitting the optional REX would miss
    # that whole class. $m.Index is the leading mandatory prefix = the true
    # instruction start, so the boundary/address math below stays correct.
    $view = [System.Text.Encoding]::GetEncoding(28591).GetString($Text)
    $rx = [regex] "[\x66\xF2][\x40-\x4F]?\x0F[\x78\x79]"
    foreach ($m in $rx.Matches($view)) {
        $i = $m.Index
        $rva = [uint64]$TextVA + [uint64]$i
        $hex = for ($k = 0; $k -lt $m.Length; $k++) { "{0:X2}" -f [int]$m.Value[$k] }
        $out += [pscustomobject]@{
            OffsetInText = $i
            Rva          = $rva
            Abs          = [uint64]$ImageBase + $rva
            Bytes        = ($hex -join " ")
        }
    }
    # Comma-wrap so a single hit still surfaces as an array with a .Count.
    return , $out
}

# Partition candidates into genuine violations (address is an instruction
# start) vs. coincidental operand data. $InstructionStarts is a
# HashSet[uint64] of absolute instruction-start addresses. Pure so it can be
# unit-tested without a disassembler.
function Select-BoundaryViolations {
    param(
        [object[]] $Candidates,
        [System.Collections.Generic.HashSet[uint64]] $InstructionStarts
    )
    $out = @()
    foreach ($c in $Candidates) {
        if ($InstructionStarts.Contains([uint64]$c.Abs)) {
            $out += $c
        }
    }
    return , $out
}

# Locate dumpbin.exe: explicit override, env var, PATH, then any MSVC install
# discovered via vswhere (including Build Tools, hence -products *).
function Resolve-DumpbinPath {
    param([string] $Override)

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if (-not (Test-Path -LiteralPath $Override)) {
            throw "Configured dumpbin path was not found: $Override"
        }
        return (Resolve-Path -LiteralPath $Override).Path
    }
    if (-not [string]::IsNullOrWhiteSpace($env:PARAMUX_DUMPBIN)) {
        if (Test-Path -LiteralPath $env:PARAMUX_DUMPBIN) {
            return (Resolve-Path -LiteralPath $env:PARAMUX_DUMPBIN).Path
        }
    }
    $cmd = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        # Under $ErrorActionPreference='Stop', a native command writing ANY stderr
        # is promoted to a terminating error (the `2>$null` discards the text but
        # does not stop the throw). Run vswhere with Continue semantics locally so
        # a benign stderr line doesn't abort discovery before the fall-through find.
        $installs = @()
        $savedEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $installs = & $vswhere -products * -latest -property installationPath 2>$null }
        catch { $installs = @() }
        finally { $ErrorActionPreference = $savedEap }
        foreach ($vs in @($installs)) {
            if ([string]::IsNullOrWhiteSpace($vs)) { continue }
            $msvcRoot = Join-Path $vs "VC\Tools\MSVC"
            if (-not (Test-Path -LiteralPath $msvcRoot)) { continue }
            $versions = Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidate = Join-Path $v.FullName "bin\Hostx64\x64\dumpbin.exe"
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }
        }
    }
    return $null
}

# Disassemble .text with dumpbin and return the subset of $CandidateAbs that
# appear as instruction-start addresses. Streams dumpbin's stdout and stops as
# soon as it has passed the last candidate, so it only disassembles up to the
# candidate region (candidates are typically early in .text).
function Get-InstructionStartsForCandidates {
    param(
        [string]   $Dumpbin,
        [string]   $ExePath,
        [uint64[]] $CandidateAbs,
        [uint64]   $TextStartAbs,
        [uint64]   $TextEndAbs
    )

    $wanted = New-Object 'System.Collections.Generic.HashSet[uint64]'
    foreach ($a in $CandidateAbs) { [void]$wanted.Add([uint64]$a) }
    $found = New-Object 'System.Collections.Generic.HashSet[uint64]'
    # Cast to uint64: Measure-Object returns .Maximum as a double, which breaks
    # the {0:X} hex formatting in the fail-closed throw below (and keeps the
    # address comparisons on a single integer type).
    $maxAbs = [uint64](($CandidateAbs | Measure-Object -Maximum).Maximum)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Dumpbin
    $psi.Arguments = "/disasm:nobytes `"$ExePath`""
    $psi.RedirectStandardOutput = $true
    # Do NOT redirect stderr: we stop reading stdout as soon as we pass the last
    # candidate and then kill dumpbin, so its stdout pipe is left full. A second
    # (stderr) redirected pipe that we then tried to drain would deadlock against
    # that. dumpbin writes nothing to stderr on success, so inheriting it is fine.
    $psi.RedirectStandardError = $false
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    # Highest .text instruction-start address dumpbin actually emitted. Used to
    # prove the candidate region was really disassembled (fail-closed guard).
    $maxSeen = [uint64]0

    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $reader = $proc.StandardOutput
        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            # x64 instruction lines: "  000000014001FB6E: lea   rdx,..."
            if ($line -match '^\s+([0-9A-Fa-f]{16}):\s') {
                $addr = [Convert]::ToUInt64($matches[1], 16)
                if (($addr -ge $TextStartAbs) -and ($addr -lt $TextEndAbs)) {
                    if ($addr -gt $maxSeen) { $maxSeen = $addr }
                    if ($wanted.Contains($addr)) { [void]$found.Add($addr) }
                    # Stop once we've disassembled past the last candidate.
                    if ($addr -gt $maxAbs) { break }
                }
            }
        }
    }
    finally {
        try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
        try { [void]$proc.WaitForExit(5000) } catch {}
        try { $reader.Dispose() } catch {}
        $proc.Dispose()
    }

    # Fail closed if dumpbin did not actually disassemble through the candidate
    # region (runtime failure, wrong-arch/broken dumpbin, unexpected address
    # format, truncated output). Without this, an empty result would be silently
    # read as "every candidate is coincidental operand data" and PASS -- the exact
    # fail-open the guard must avoid. Note: we cannot gate on $proc.ExitCode,
    # because the happy path deliberately Kill()s dumpbin after the early break.
    if ($maxSeen -lt $maxAbs) {
        throw ("Windows x64 baseline check: dumpbin did not disassemble the candidate region of .text (reached 0x{0:X}, needed to cover 0x{1:X}). Cannot verify -- failing closed. dumpbin={2}" -f $maxSeen, $maxAbs, $Dumpbin)
    }

    # Comma-wrap: a bare `return $found` would unroll the (enumerable) HashSet
    # into the pipeline and emit nothing when it is empty, yielding $null.
    return , $found
}

# ---------------------------------------------------------------------------
# Self-test mode (hermetic; no PE / disassembler needed)
# ---------------------------------------------------------------------------
if ($SelfTest) {
    $script:failed = 0
    function Assert-True {
        param([bool] $Condition, [string] $Message)
        if ($Condition) { Write-Host "  ok: $Message" }
        else { Write-Host "FAIL: $Message"; $script:failed++ }
    }

    # A real reg-form INSERTQ xmm0,xmm1 (F2 0F 79 C1) then ret (C3).
    $insertq = [byte[]] @(0xF2, 0x0F, 0x79, 0xC1, 0xC3)
    $c1 = Find-Sse4aCandidates -Text $insertq -TextVA 0x1000 -ImageBase 0x140000000
    Assert-True (($c1.Count -eq 1) -and ($c1[0].OffsetInText -eq 0)) "finds the INSERTQ candidate at offset 0"

    # A coincidental triple inside a lea disp32: 48 8D 15 [F2 0F 79 00] C3.
    $lea = [byte[]] @(0x48, 0x8D, 0x15, 0xF2, 0x0F, 0x79, 0x00, 0xC3)
    $c2 = Find-Sse4aCandidates -Text $lea -TextVA 0x1000 -ImageBase 0x140000000
    Assert-True (($c2.Count -eq 1) -and ($c2[0].OffsetInText -eq 3)) "finds the coincidental triple inside the lea disp at offset 3"

    # Bytes with no SSE4a triple -> no candidates.
    $clean = [byte[]] @(0x48, 0x8B, 0xC1, 0xC3)
    $c3 = Find-Sse4aCandidates -Text $clean -TextVA 0x1000 -ImageBase 0x140000000
    Assert-True ($c3.Count -eq 0) "clean bytes yield no candidates"

    # REX-prefixed INSERTQ xmm1,xmm8 (F2 44 0F 79 C8) then ret. The mandatory F2
    # and the 0F are non-adjacent (REX 0x44 sits between them); the scan must
    # still catch it, anchored at the leading F2, with the REX byte in Bytes.
    $rexInsertq = [byte[]] @(0xF2, 0x44, 0x0F, 0x79, 0xC8, 0xC3)
    $c4 = Find-Sse4aCandidates -Text $rexInsertq -TextVA 0x1000 -ImageBase 0x140000000
    Assert-True (($c4.Count -eq 1) -and ($c4[0].OffsetInText -eq 0) -and ($c4[0].Bytes -eq "F2 44 0F 79")) "finds the REX-prefixed INSERTQ (xmm8-15) at offset 0"
    $startsC = New-Object 'System.Collections.Generic.HashSet[uint64]'
    [void]$startsC.Add([uint64](0x140000000 + 0x1000 + 0))
    $vC = Select-BoundaryViolations -Candidates $c4 -InstructionStarts $startsC
    Assert-True ($vC.Count -eq 1) "boundary-aligned REX-prefixed INSERTQ is flagged"

    # Discriminator: INSERTQ at an instruction boundary IS a violation.
    $startsA = New-Object 'System.Collections.Generic.HashSet[uint64]'
    [void]$startsA.Add([uint64](0x140000000 + 0x1000 + 0))
    $vA = Select-BoundaryViolations -Candidates $c1 -InstructionStarts $startsA
    Assert-True ($vA.Count -eq 1) "boundary-aligned INSERTQ is flagged as a violation"

    # Discriminator: coincidental triple inside the lea (boundary is the lea at
    # offset 0, not the triple at offset 3) is NOT a violation.
    $startsB = New-Object 'System.Collections.Generic.HashSet[uint64]'
    [void]$startsB.Add([uint64](0x140000000 + 0x1000 + 0))
    $vB = Select-BoundaryViolations -Candidates $c2 -InstructionStarts $startsB
    Assert-True ($vB.Count -eq 0) "triple inside a lea displacement is not flagged"

    if ($script:failed -gt 0) {
        throw "SSE4a baseline self-test: $($script:failed) assertion(s) failed."
    }
    Write-Host "SSE4a baseline self-test: all assertions passed."
    return
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "Specify -Path <exe/dll> to check, or -SelfTest to run the unit tests."
}
if (-not (Test-Path -LiteralPath $Path)) {
    throw "File not found: $Path"
}

$fullPath = (Resolve-Path -LiteralPath $Path).Path
$stream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
try {
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file: $fullPath"
        }

        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Missing PE signature: $fullPath"
        }

        $machine = $reader.ReadUInt16()
        $sectionCount = $reader.ReadUInt16()
        $stream.Position = $peOffset + 20
        $optionalHeaderSize = $reader.ReadUInt16()
        $sectionTable = $peOffset + 24 + $optionalHeaderSize

        if ($machine -ne 0x8664) {
            Write-Host "CPU baseline check: skipped non-x64 PE $fullPath"
            return
        }

        # ImageBase (PE32+): optional header offset 24, 8 bytes.
        $stream.Position = $peOffset + 24 + 24
        $imageBase = $reader.ReadUInt64()

        $textSection = $null
        for ($i = 0; $i -lt $sectionCount; $i++) {
            $stream.Position = $sectionTable + ($i * 40)
            $nameBytes = $reader.ReadBytes(8)
            $name = [System.Text.Encoding]::ASCII.GetString($nameBytes).TrimEnd([char]0)
            $virtualSize = $reader.ReadUInt32()
            $virtualAddress = $reader.ReadUInt32()
            $rawSize = $reader.ReadUInt32()
            $rawPointer = $reader.ReadUInt32()
            if ($name -eq ".text") {
                $textSection = [pscustomobject]@{
                    VirtualSize    = $virtualSize
                    VirtualAddress = $virtualAddress
                    RawSize        = $rawSize
                    RawPointer     = $rawPointer
                }
                break
            }
        }

        if ($null -eq $textSection) {
            throw "Missing .text section: $fullPath"
        }

        $stream.Position = $textSection.RawPointer
        $text = $reader.ReadBytes($textSection.RawSize)
    }
    finally {
        $reader.Dispose()
    }
}
finally {
    $stream.Dispose()
}

$candidates = Find-Sse4aCandidates -Text $text -TextVA $textSection.VirtualAddress -ImageBase $imageBase

# Fast path: no candidate byte patterns at all -> nothing to disambiguate.
if ($candidates.Count -eq 0) {
    Write-Host "CPU baseline check: passed for $fullPath"
    return
}

# A candidate exists; confirm at instruction boundaries with a disassembler.
$dumpbin = Resolve-DumpbinPath -Override $DumpbinPath
$candidateList = ($candidates | ForEach-Object { $_.Bytes + " @ RVA 0x" + ("{0:X}" -f $_.Rva) }) -join "; "

if ($null -eq $dumpbin) {
    throw ("Windows x64 baseline check: found {0} candidate SSE4a byte pattern(s) that must be confirmed at an instruction boundary, but no disassembler (dumpbin.exe) was found to verify them. Install the Windows SDK / MSVC (dumpbin ships with it), or pass -DumpbinPath / set `$env:PARAMUX_DUMPBIN. Candidates: {1}" -f $candidates.Count, $candidateList)
}

$textStartAbs = [uint64]$imageBase + [uint64]$textSection.VirtualAddress
$textEndAbs = $textStartAbs + [uint64]$textSection.RawSize
$candidateAbs = @($candidates | ForEach-Object { [uint64]$_.Abs })

$instructionStarts = Get-InstructionStartsForCandidates `
    -Dumpbin $dumpbin `
    -ExePath $fullPath `
    -CandidateAbs $candidateAbs `
    -TextStartAbs $textStartAbs `
    -TextEndAbs $textEndAbs

$violations = Select-BoundaryViolations -Candidates $candidates -InstructionStarts $instructionStarts

if ($violations.Count -gt 0) {
    $details = ($violations | ForEach-Object {
            "RVA 0x{0:X8}, abs 0x{1:X}, opcode {2}" -f $_.Rva, $_.Abs, $_.Bytes
        }) -join [Environment]::NewLine
    throw "Windows x64 baseline check failed: found AMD-only SSE4a EXTRQ/INSERTQ instruction(s) at .text instruction boundaries:$([Environment]::NewLine)$details"
}

$suppressed = $candidates.Count
Write-Host "CPU baseline check: passed for $fullPath ($suppressed coincidental byte-pattern match(es) confirmed to be operand data, not SSE4a instructions)"
