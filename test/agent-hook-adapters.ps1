param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$hooksRoot = Join-Path $repoRoot 'contrib\paramux\hooks'
$maxHookInputBytes = 1024 * 1024
$nodeExecutable = (Get-Command node.exe -ErrorAction Stop).Source

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message (expected='$Expected', actual='$Actual')"
    }
}

function Assert-Sequence {
    param(
        [object[]] $Actual,
        [object[]] $Expected,
        [string] $Message
    )

    Assert-Equal $Actual.Count $Expected.Count "$Message count"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-Equal $Actual[$index] $Expected[$index] "$Message item $index"
    }
}

function Read-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing expected JSON file: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Invoke-NodeHook {
    param(
        [string] $Path,
        [string] $Payload,
        [string[]] $NodeArguments = @()
    )

    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $stdoutLines = $Payload | & $script:nodeExecutable @NodeArguments $Path 2> $stderrPath
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        return [pscustomobject]@{
            ExitCode = $exitCode
            Stdout = ($stdoutLines -join [Environment]::NewLine)
            Stderr = Get-Content -LiteralPath $stderrPath -Raw
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function New-FakeParamux {
    param([string] $Directory)

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $compiledPath = Join-Path $Directory 'fake-paramux.exe'
    $commandPath = Join-Path $Directory 'paramux.com'
    $source = @'
using System;
using System.IO;
using System.Text;

public static class FakeParamux
{
    public static int Main(string[] args)
    {
        string logPath = Environment.GetEnvironmentVariable("PARAMUX_FAKE_LOG");
        if (String.IsNullOrEmpty(logPath))
        {
            Console.Error.WriteLine("PARAMUX_FAKE_LOG is required");
            return 99;
        }

        string[] encoded = Array.ConvertAll(args, delegate(string value)
        {
            return Convert.ToBase64String(Encoding.UTF8.GetBytes(value));
        });
        File.AppendAllText(logPath, String.Join("\t", encoded) + Environment.NewLine);
        Console.Out.Write("fake child stdout must be suppressed");

        int exitCode;
        return Int32.TryParse(Environment.GetEnvironmentVariable("PARAMUX_FAKE_EXIT_CODE"), out exitCode)
            ? exitCode
            : 0;
    }
}
'@
    # Add-Type -OutputType ConsoleApplication is a terminating error on
    # PowerShell 7.1+, and CI runs this script under `shell: pwsh`. The .NET
    # Framework C# compiler produces a standalone exe under both hosts.
    $sourcePath = Join-Path $Directory 'fake-paramux.cs'
    [System.IO.File]::WriteAllText($sourcePath, $source, (New-Object System.Text.UTF8Encoding($false)))
    $cscPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $cscPath)) {
        throw "Missing .NET Framework C# compiler: $cscPath"
    }
    & $cscPath /nologo /target:exe "/out:$compiledPath" $sourcePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "fake paramux compile failed with exit code $LASTEXITCODE"
    }
    Copy-Item -LiteralPath $compiledPath -Destination $commandPath -Force
    Copy-Item -LiteralPath $compiledPath -Destination (Join-Path $Directory 'paramux.exe') -Force
    return $commandPath
}

function Read-FakeCalls {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $Path | ForEach-Object {
            $arguments = if ($_.Length -eq 0) {
                @()
            }
            else {
                @(
                    $_ -split "`t" | ForEach-Object {
                        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
                    }
                )
            }
            [pscustomobject]@{ Arguments = $arguments }
        }
    )
}

function Assert-HookCommand {
    param(
        $Hook,
        [string] $ExpectedState,
        [string] $ExpectedMessage,
        [switch] $MessageFromStdin
    )

    Assert-Equal $Hook.type 'command' 'Claude hook type'
    Assert-Equal $Hook.command '__PARAMUX_EXECUTABLE__?RUN_INSTALL_PARAMUX_PS1' 'Claude hook template executable'
    $expectedArgs = if ($MessageFromStdin) {
        @('notify', "--state=$ExpectedState", '--message-from-stdin', $ExpectedMessage)
    } else {
        @('notify', "--state=$ExpectedState", $ExpectedMessage)
    }
    Assert-Sequence @($Hook.args) $expectedArgs 'Claude hook args'
}

$claudePath = Join-Path $hooksRoot 'claude-code.settings.json'
$codexConfigPath = Join-Path $hooksRoot 'codex\hooks.json'
$codexAdapterPath = Join-Path $hooksRoot 'codex\paramux-hook.cjs'
$geminiRoot = Join-Path $hooksRoot 'gemini-paramux'
$geminiManifestPath = Join-Path $geminiRoot 'gemini-extension.json'
$geminiHooksPath = Join-Path $geminiRoot 'hooks\hooks.json'
$geminiAdapterPath = Join-Path $geminiRoot 'scripts\notify.cjs'
$geminiHookLauncherPath = Join-Path $geminiRoot 'scripts\notify.cmd'
$openCodePath = Join-Path $hooksRoot 'opencode\paramux.js'
$codexHookLauncherPath = Join-Path $repoRoot 'dist\windows\paramux-codex-hook.cmd'
$hookConfiguratorPath = Join-Path $repoRoot 'dist\windows\configure-paramux-hooks.ps1'
$installerPath = Join-Path $repoRoot 'dist\windows\install-paramux.ps1'

$claudeTemplate = Get-Content -LiteralPath $claudePath -Raw
$codexTemplate = Get-Content -LiteralPath $codexConfigPath -Raw
$codexAdapterSource = Get-Content -LiteralPath $codexAdapterPath -Raw
$geminiAdapterSource = Get-Content -LiteralPath $geminiAdapterPath -Raw
$openCodeSource = Get-Content -LiteralPath $openCodePath -Raw
$codexLauncherSource = Get-Content -LiteralPath $codexHookLauncherPath -Raw
$installerSource = Get-Content -LiteralPath $installerPath -Raw

Assert-True $claudeTemplate.Contains('__PARAMUX_EXECUTABLE__') 'Claude template must fail closed until the installer writes an absolute executable path'
Assert-True $codexTemplate.Contains('__PARAMUX_CODEX_COMMAND_WINDOWS__') 'Codex template must fail closed until the installer writes an absolute launcher command'
Assert-True (Test-Path -LiteralPath $geminiHookLauncherPath -PathType Leaf) 'Gemini must enter through an extension-rooted launcher'
Assert-True (Test-Path -LiteralPath $hookConfiguratorPath -PathType Leaf) 'Portable install must include the hook configurator'
foreach ($source in @($codexAdapterSource, $geminiAdapterSource, $openCodeSource)) {
    Assert-True $source.Contains('PARAMUX_HOME') 'Every Node adapter must resolve Paramux from PARAMUX_HOME'
    Assert-True $source.Contains('isAbsolute') 'Every Node adapter must reject a relative PARAMUX_HOME'
}
Assert-True $codexLauncherSource.Contains('pushd "%~dp0"') 'Codex launcher must leave the untrusted session cwd before resolving Node'
Assert-True $installerSource.Contains('PARAMUX_HOME') 'Installer must persist PARAMUX_HOME for copied agent adapters'

$claude = Read-JsonFile $claudePath
Assert-Sequence @($claude.PSObject.Properties.Name) @('hooks') 'Claude top-level keys'
Assert-Sequence @($claude.hooks.PSObject.Properties.Name) @('UserPromptSubmit', 'PermissionRequest', 'Elicitation', 'Stop', 'StopFailure', 'SessionEnd') 'Claude events'
Assert-HookCommand $claude.hooks.UserPromptSubmit[0].hooks[0] 'working' 'Claude Code is working'
Assert-HookCommand $claude.hooks.PermissionRequest[0].hooks[0] 'waiting' 'Claude Code needs your approval' -MessageFromStdin
Assert-HookCommand $claude.hooks.Elicitation[0].hooks[0] 'waiting' 'Claude Code needs your input' -MessageFromStdin
Assert-HookCommand $claude.hooks.Stop[0].hooks[0] 'done' 'Claude Code finished responding'
Assert-HookCommand $claude.hooks.StopFailure[0].hooks[0] 'error' 'Claude Code stopped with an error' -MessageFromStdin
Assert-HookCommand $claude.hooks.SessionEnd[0].hooks[0] 'none' 'Claude Code session ended'

$codex = Read-JsonFile $codexConfigPath
Assert-Sequence @($codex.PSObject.Properties.Name) @('hooks') 'Codex top-level keys'
Assert-Sequence @($codex.hooks.PSObject.Properties.Name) @('UserPromptSubmit', 'PermissionRequest', 'Stop', 'SessionEnd') 'Codex events'
$codexPosixCommand = "printf '%s\n' 'Paramux Codex hooks require Windows and a configured portable install.' >&2; exit 1"
foreach ($eventName in @('UserPromptSubmit', 'PermissionRequest', 'Stop', 'SessionEnd')) {
    $handler = $codex.hooks.$eventName[0].hooks[0]
    Assert-Equal $handler.type 'command' "Codex $eventName hook type"
    Assert-Equal $handler.command $codexPosixCommand "Codex $eventName POSIX command"
    Assert-Equal $handler.commandWindows '__PARAMUX_CODEX_COMMAND_WINDOWS__?RUN_INSTALL_PARAMUX_PS1' "Codex $eventName Windows template"
    Assert-Equal $handler.timeout 10 "Codex $eventName timeout"
}

$geminiManifest = Read-JsonFile $geminiManifestPath
Assert-Equal $geminiManifest.name 'paramux-notifications' 'Gemini extension name'
Assert-Equal $geminiManifest.version '1.0.0' 'Gemini extension version'
$geminiHooks = Read-JsonFile $geminiHooksPath
Assert-Sequence @($geminiHooks.hooks.PSObject.Properties.Name) @('BeforeAgent', 'Notification', 'AfterAgent', 'SessionEnd') 'Gemini events'
Assert-Equal $geminiHooks.hooks.Notification[0].matcher 'ToolPermission' 'Gemini Notification matcher'
foreach ($eventName in @('BeforeAgent', 'Notification', 'AfterAgent', 'SessionEnd')) {
    $handler = $geminiHooks.hooks.$eventName[0].hooks[0]
    Assert-Equal $handler.type 'command' "Gemini $eventName hook type"
    Assert-Equal $handler.command 'call "${extensionPath}/scripts/notify.cmd"' "Gemini $eventName command"
    Assert-Equal $handler.timeout 10000 "Gemini $eventName timeout"
}

foreach ($scriptPath in @($codexAdapterPath, $geminiAdapterPath, $openCodePath)) {
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Missing expected adapter script: $scriptPath"
    }
}
& $nodeExecutable --check $codexAdapterPath
if ($LASTEXITCODE -ne 0) { throw 'Codex adapter failed node --check.' }
& $nodeExecutable --check $geminiAdapterPath
if ($LASTEXITCODE -ne 0) { throw 'Gemini adapter failed node --check.' }
$openCodeSource = Get-Content -LiteralPath $openCodePath -Raw
$openCodeSource | & $nodeExecutable --input-type=module --check
if ($LASTEXITCODE -ne 0) { throw 'OpenCode adapter failed node --check.' }

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("paramux-agent-hooks-{0}" -f [guid]::NewGuid().ToString('N'))
$trustedRoot = Join-Path $tempRoot 'portable install'
$trustedHooksRoot = Join-Path $trustedRoot 'agent-hooks'
$hostileRoot = Join-Path $tempRoot 'hostile repo'
$fakeLog = Join-Path $tempRoot 'calls.log'
$hostileLog = Join-Path $tempRoot 'hostile.log'
$oldPath = $env:PATH
$oldParamuxHome = $env:PARAMUX_HOME
$oldFakeLog = $env:PARAMUX_FAKE_LOG
$oldFakeExitCode = $env:PARAMUX_FAKE_EXIT_CODE
$oldHostileLog = $env:PARAMUX_HOSTILE_LOG

try {
    New-Item -ItemType Directory -Path $trustedRoot, $trustedHooksRoot, $hostileRoot -Force | Out-Null
    New-FakeParamux $trustedRoot | Out-Null
    Get-ChildItem -LiteralPath $hooksRoot -Force |
        Copy-Item -Destination $trustedHooksRoot -Recurse -Force
    Copy-Item -LiteralPath $codexHookLauncherPath -Destination (Join-Path $trustedRoot 'paramux-codex-hook.cmd')
    Copy-Item -LiteralPath $hookConfiguratorPath -Destination (Join-Path $trustedRoot 'configure-paramux-hooks.ps1')

    [System.IO.File]::WriteAllLines(
        (Join-Path $hostileRoot 'paramux-codex-hook.cmd'),
        @('@echo off', 'echo codex-launcher>>"%PARAMUX_HOSTILE_LOG%"', 'exit /b 91')
    )
    [System.IO.File]::WriteAllLines(
        (Join-Path $hostileRoot 'node.cmd'),
        @('@echo off', 'echo node>>"%PARAMUX_HOSTILE_LOG%"', 'exit /b 92')
    )
    [System.IO.File]::WriteAllLines(
        (Join-Path $hostileRoot '__PARAMUX_CODEX_COMMAND_WINDOWS__.cmd'),
        @('@echo off', 'echo codex-template>>"%PARAMUX_HOSTILE_LOG%"', 'exit /b 95')
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $hostileRoot 'paramux.com'),
        'This deliberately invalid executable must never run.'
    )
    Copy-Item -LiteralPath (Join-Path $trustedRoot 'paramux.exe') -Destination (Join-Path $hostileRoot '__PARAMUX_EXECUTABLE__.exe')

    & (Join-Path $trustedRoot 'configure-paramux-hooks.ps1')
    $configuredClaude = Read-JsonFile (Join-Path $trustedHooksRoot 'claude-code.settings.json')
    $configuredCodex = Read-JsonFile (Join-Path $trustedHooksRoot 'codex\hooks.json')
    $configuredParamux = Join-Path $trustedRoot 'paramux.com'
    foreach ($eventName in @('UserPromptSubmit', 'PermissionRequest', 'Elicitation', 'Stop', 'StopFailure', 'SessionEnd')) {
        $handler = $configuredClaude.hooks.$eventName[0].hooks[0]
        Assert-Equal $handler.command $configuredParamux "Configured Claude $eventName absolute executable"
        Assert-True ([System.IO.Path]::IsPathRooted($handler.command)) "Configured Claude $eventName path must be absolute"
    }
    $configuredCodexCommand = $configuredCodex.hooks.Stop[0].hooks[0].commandWindows
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Assert-True $configuredCodexCommand.StartsWith($windowsPowerShell) 'Configured Codex command must use absolute Windows PowerShell'
    Assert-True $configuredCodexCommand.Contains('-EncodedCommand') 'Configured Codex command must safely encode its trusted launcher path'
    foreach ($eventName in @('UserPromptSubmit', 'PermissionRequest', 'Stop', 'SessionEnd')) {
        Assert-Equal $configuredCodex.hooks.$eventName[0].hooks[0].commandWindows $configuredCodexCommand "Configured Codex $eventName launcher"
    }

    $env:PATH = $oldPath
    $env:PARAMUX_HOME = $trustedRoot
    $env:PARAMUX_FAKE_LOG = $fakeLog
    $env:PARAMUX_FAKE_EXIT_CODE = '0'
    $env:PARAMUX_HOSTILE_LOG = $hostileLog

    Push-Location $hostileRoot
    try {
        $sourceClaudeHandler = $claude.hooks.Stop[0].hooks[0]
        $sourceTemplateProbe = @'
const { spawnSync } = require("node:child_process");
const result = spawnSync(
  process.argv[2],
  process.argv.slice(4),
  { cwd: process.argv[3], shell: false, stdio: "ignore" },
);
if (!result.error) process.exit(93);
if (!["ENOENT", "EINVAL"].includes(result.error.code)) process.exit(94);
'@
        $sourceTemplateProbePath = Join-Path $tempRoot 'source-template-probe.cjs'
        [System.IO.File]::WriteAllText($sourceTemplateProbePath, $sourceTemplateProbe)
        & $nodeExecutable $sourceTemplateProbePath $sourceClaudeHandler.command $hostileRoot @($sourceClaudeHandler.args)
        Assert-Equal $LASTEXITCODE 0 'Unconfigured Claude template must be intrinsically unresolvable'

        $sourceCodexHandler = $codex.hooks.Stop[0].hooks[0]
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $null = & $env:ComSpec /d /s /c $sourceCodexHandler.commandWindows 2>$null
        $sourceCodexExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        Assert-True ($sourceCodexExitCode -ne 0) 'Unconfigured Codex template must fail'
        Assert-True (-not (Test-Path -LiteralPath $hostileLog)) 'Unconfigured Codex template must not resolve a cwd decoy'

        foreach ($eventName in @('UserPromptSubmit', 'PermissionRequest', 'Elicitation', 'Stop', 'StopFailure', 'SessionEnd')) {
            $handler = $configuredClaude.hooks.$eventName[0].hooks[0]
            $null = '{"message":"probe"}' | & $handler.command @($handler.args)
            Assert-Equal $LASTEXITCODE 0 "Claude $eventName hostile-cwd execution"
        }
        Assert-Equal (Read-FakeCalls $fakeLog).Count 6 'Claude absolute command smoke calls'
        Remove-Item -LiteralPath $fakeLog -Force

        $shellPayload = '{"hook_event_name":"Stop"}'
        $cmdStdout = $shellPayload | & $env:ComSpec /d /s /c $configuredCodexCommand
        Assert-Equal $LASTEXITCODE 0 'Codex commandWindows runs under cmd.exe'
        Assert-Equal ($cmdStdout -join [Environment]::NewLine) '{}' 'Codex cmd.exe stdout protocol'
        $powershellStdout = $shellPayload | & powershell -NoProfile -Command $configuredCodexCommand
        Assert-Equal $LASTEXITCODE 0 'Codex commandWindows runs under PowerShell'
        Assert-Equal ($powershellStdout -join [Environment]::NewLine) '{}' 'Codex PowerShell stdout protocol'
        Assert-Equal (Read-FakeCalls $fakeLog).Count 2 'Codex configured command hostile-cwd calls'
        Remove-Item -LiteralPath $fakeLog -Force

        $extensionToken = '$' + '{extensionPath}'
        $trustedGeminiRoot = Join-Path $trustedHooksRoot 'gemini-paramux'
        $geminiCommand = $geminiHooks.hooks.BeforeAgent[0].hooks[0].command.Replace(
            $extensionToken,
            $trustedGeminiRoot.Replace('\', '/')
        )
        $geminiStdout = '{"hook_event_name":"BeforeAgent"}' |
            & $env:ComSpec /d /s /c $geminiCommand
        Assert-Equal $LASTEXITCODE 0 'Gemini extension-rooted launcher hostile-cwd execution'
        Assert-Equal ($geminiStdout -join [Environment]::NewLine) '{}' 'Gemini launcher stdout protocol'
        Assert-Equal @(Read-FakeCalls $fakeLog).Count 1 'Gemini extension-rooted launcher call'
        Remove-Item -LiteralPath $fakeLog -Force
    }
    finally {
        Pop-Location
    }

    $codexCases = @(
        @{ Payload = @{ hook_event_name = 'UserPromptSubmit' }; State = 'working'; Message = 'Codex CLI is working' },
        @{ Payload = @{ hook_event_name = 'PermissionRequest' }; State = 'waiting'; Message = 'Codex CLI needs your approval' },
        # PermissionRequest passes the payload's real request text through.
        @{ Payload = @{ hook_event_name = 'PermissionRequest'; message = 'Allow shell: git push?' }; State = 'waiting'; Message = 'Allow shell: git push?' },
        # ... but a non-string payload message keeps the canned fallback.
        @{ Payload = @{ hook_event_name = 'PermissionRequest'; message = 42 }; State = 'waiting'; Message = 'Codex CLI needs your approval' },
        # UserPromptSubmit ignores payload text (working is not a question).
        @{ Payload = @{ hook_event_name = 'UserPromptSubmit'; message = 'ignored' }; State = 'working'; Message = 'Codex CLI is working' },
        @{ Payload = @{ hook_event_name = 'Stop' }; State = 'done'; Message = 'Codex CLI finished responding' },
        @{ Payload = @{ hook_event_name = 'SessionEnd' }; State = 'none'; Message = 'Codex CLI session ended' }
    )
    foreach ($case in $codexCases) {
        $result = Invoke-NodeHook $codexAdapterPath (ConvertTo-Json $case.Payload -Compress)
        Assert-Equal $result.ExitCode 0 "Codex $($case.Payload.hook_event_name) exit code"
        Assert-Equal $result.Stdout '{}' "Codex $($case.Payload.hook_event_name) stdout protocol"
    }
    $calls = Read-FakeCalls $fakeLog
    Assert-Equal $calls.Count $codexCases.Count 'Codex fake call count'
    for ($index = 0; $index -lt $codexCases.Count; $index++) {
        Assert-Sequence @($calls[$index].Arguments) @('notify', "--state=$($codexCases[$index].State)", $codexCases[$index].Message) "Codex call $index args"
    }

    Remove-Item -LiteralPath $fakeLog -Force
    $geminiCases = @(
        @{ Payload = @{ hook_event_name = 'BeforeAgent' }; State = 'working'; Message = 'Gemini CLI is working' },
        @{ Payload = @{ hook_event_name = 'Notification'; notification_type = 'ToolPermission' }; State = 'waiting'; Message = 'Gemini CLI needs your approval' },
        # ToolPermission notifications pass the payload's request text through.
        @{ Payload = @{ hook_event_name = 'Notification'; notification_type = 'ToolPermission'; message = 'Run shell command?' }; State = 'waiting'; Message = 'Run shell command?' },
        @{ Payload = @{ hook_event_name = 'AfterAgent' }; State = 'done'; Message = 'Gemini CLI finished responding' },
        @{ Payload = @{ hook_event_name = 'SessionEnd' }; State = 'none'; Message = 'Gemini CLI session ended' }
    )
    foreach ($case in $geminiCases) {
        $result = Invoke-NodeHook $geminiAdapterPath (ConvertTo-Json $case.Payload -Compress)
        Assert-Equal $result.ExitCode 0 "Gemini $($case.Payload.hook_event_name) exit code"
        Assert-Equal $result.Stdout '{}' "Gemini $($case.Payload.hook_event_name) stdout protocol"
    }
    $calls = Read-FakeCalls $fakeLog
    Assert-Equal $calls.Count $geminiCases.Count 'Gemini fake call count'
    for ($index = 0; $index -lt $geminiCases.Count; $index++) {
        Assert-Sequence @($calls[$index].Arguments) @('notify', "--state=$($geminiCases[$index].State)", $geminiCases[$index].Message) "Gemini call $index args"
    }

    foreach ($adapterPath in @($codexAdapterPath, $geminiAdapterPath)) {
        $invalid = Invoke-NodeHook $adapterPath 'not-json'
        Assert-True ($invalid.ExitCode -ne 0) "$adapterPath must reject invalid JSON"
        Assert-Equal $invalid.Stdout '' "$adapterPath invalid JSON stdout"

        $unsupported = Invoke-NodeHook $adapterPath '{"hook_event_name":"toString"}'
        Assert-True ($unsupported.ExitCode -ne 0) "$adapterPath must reject inherited event names"
        Assert-Equal $unsupported.Stdout '' "$adapterPath unsupported event stdout"

        $oversizedPayload = '{"hook_event_name":"Stop","padding":"' + ('x' * ($maxHookInputBytes + 1)) + '"}'
        $oversized = Invoke-NodeHook $adapterPath $oversizedPayload
        Assert-True ($oversized.ExitCode -ne 0) "$adapterPath must reject oversized input"
        Assert-Equal $oversized.Stdout '' "$adapterPath oversized stdout"
        Assert-True ($oversized.Stderr -match 'exceeds') "$adapterPath oversized error message"

        $env:PARAMUX_HOME = 'relative-install'
        $relativePayload = if ($adapterPath -eq $geminiAdapterPath) {
            '{"hook_event_name":"BeforeAgent"}'
        } else {
            '{"hook_event_name":"Stop"}'
        }
        $relativeHome = Invoke-NodeHook $adapterPath $relativePayload
        Assert-True ($relativeHome.ExitCode -ne 0) "$adapterPath must reject relative PARAMUX_HOME"
        Assert-True ($relativeHome.Stderr -match 'absolute path') "$adapterPath relative PARAMUX_HOME error"
        $env:PARAMUX_HOME = $trustedRoot
    }
    Assert-Equal (Read-FakeCalls $fakeLog).Count $geminiCases.Count 'Rejected payloads and paths must not call paramux'

    $env:PARAMUX_FAKE_EXIT_CODE = '7'
    $failed = Invoke-NodeHook $codexAdapterPath '{"hook_event_name":"Stop"}'
    Assert-Equal $failed.ExitCode 7 'Codex propagates paramux failure'
    Assert-Equal $failed.Stdout '' 'Codex failure does not emit success JSON'
    $env:PARAMUX_FAKE_EXIT_CODE = '0'

    Remove-Item -LiteralPath $fakeLog -Force
    $openCodeModule = Join-Path $tempRoot 'paramux.mjs'
    [System.IO.File]::WriteAllText($openCodeModule, $openCodeSource)
    $pluginUri = [Uri]::new($openCodeModule).AbsoluteUri
    $openCodeHarness = Join-Path $tempRoot 'opencode-harness.mjs'
    $harnessSource = @"
import { ParamuxPlugin } from "$pluginUri";
const plugin = await ParamuxPlugin({ client: { app: { log: async () => {} } } });
await plugin.event({ event: { type: "session.status", properties: { sessionID: "one", status: { type: "busy" } } } });
await plugin.event({ event: { type: "permission.asked", properties: { sessionID: "one" } } });
await plugin.event({ event: { type: "session.status", properties: { sessionID: "one", status: { type: "idle" } } } });
await plugin.event({ event: { type: "session.error", properties: { sessionID: "two", error: {} } } });
await plugin.event({ event: { type: "session.status", properties: { sessionID: "two", status: { type: "idle" } } } });
"@
    [System.IO.File]::WriteAllText($openCodeHarness, $harnessSource)
    Push-Location $hostileRoot
    try {
        & $nodeExecutable $openCodeHarness
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) { throw 'OpenCode adapter harness failed.' }
    $openCodeCases = @(
        @{ State = 'working'; Message = 'OpenCode is working' },
        @{ State = 'waiting'; Message = 'OpenCode needs your approval' },
        @{ State = 'done'; Message = 'OpenCode finished responding' },
        @{ State = 'error'; Message = 'OpenCode stopped with an error' }
    )
    $calls = Read-FakeCalls $fakeLog
    Assert-Equal $calls.Count 4 'OpenCode fake call count and error precedence'
    for ($index = 0; $index -lt $openCodeCases.Count; $index++) {
        Assert-Sequence @($calls[$index].Arguments) @('notify', "--state=$($openCodeCases[$index].State)", $openCodeCases[$index].Message) "OpenCode call $index args"
    }

    Assert-True (-not (Test-Path -LiteralPath $hostileLog)) 'No hostile working-directory launcher may execute'
}
finally {
    $env:PATH = $oldPath
    $env:PARAMUX_HOME = $oldParamuxHome
    $env:PARAMUX_FAKE_LOG = $oldFakeLog
    $env:PARAMUX_FAKE_EXIT_CODE = $oldFakeExitCode
    $env:PARAMUX_HOSTILE_LOG = $oldHostileLog
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
        $isWithinTemp = $resolvedTempRoot.StartsWith(
            $resolvedTempBase,
            [System.StringComparison]::OrdinalIgnoreCase
        )
        $hasExpectedName = (Split-Path -Leaf $resolvedTempRoot) -like 'paramux-agent-hooks-*'
        if (-not $isWithinTemp -or -not $hasExpectedName) {
            throw "Refusing to remove unexpected adapter test path: $resolvedTempRoot"
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

$requiredHookFiles = @(
    'README.md',
    'claude-code.settings.json',
    'codex/hooks.json',
    'codex/paramux-hook.cjs',
    'gemini-paramux/gemini-extension.json',
    'gemini-paramux/hooks/hooks.json',
    'gemini-paramux/scripts/notify.cjs',
    'gemini-paramux/scripts/notify.cmd',
    'opencode/paramux.js'
)
$packageScriptPath = Join-Path $repoRoot 'scripts\package-windows.ps1'
$packageScript = Get-Content -LiteralPath $packageScriptPath -Raw
foreach ($relativePath in $requiredHookFiles) {
    $matchCount = [regex]::Matches($packageScript, [regex]::Escape($relativePath)).Count
    Assert-True ($matchCount -ge 2) "Package script must stage and ZIP-assert $relativePath"
}
Assert-True ($packageScript.Contains('paramux-codex-hook.cmd')) 'Package script must stage the Codex hook launcher'
Assert-True ($packageScript.Contains('configure-paramux-hooks.ps1')) 'Package script must stage the hook configurator'

$portableTestPath = Join-Path $repoRoot 'test\windows\package-portable-cli.ps1'
$portableTest = Get-Content -LiteralPath $portableTestPath -Raw
foreach ($relativePath in $requiredHookFiles) {
    $windowsPath = $relativePath.Replace('/', '\')
    Assert-True ($portableTest.Contains($windowsPath)) "Portable package test must assert $windowsPath"
}
Assert-True ($portableTest.Contains('paramux-codex-hook.cmd')) 'Portable package test must assert the Codex hook launcher'
Assert-True ($portableTest.Contains('configure-paramux-hooks.ps1')) 'Portable package test must assert the hook configurator'

Write-Host 'agent hook adapter validation: PASS'
