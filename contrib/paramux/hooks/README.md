# paramux agent-attention hooks

These snippets wire the four supported AI coding agents into paramux's
attention system (FR-4/FR-5). Each agent calls the built-in `notify` CLI when
its state changes; paramux colors that pane's sidebar row and fires a Windows
toast + taskbar flash.

## How it works

`paramux notify [--state=<state>] [--title=<t>] <message...>` prefers the
authenticated local IPC route using the `PARAMUX_SURFACE_ID` and
`PARAMUX_TOKEN` that Paramux injects into every pane. This **auto-targets the
pane the command ran in** — no window or surface id needed — and still works
when an agent hook hides or captures its child console. If IPC is unavailable,
the CLI falls back to an OSC 777 notification through the pane's `CONOUT$`.

`--state` is one of:

| state     | color | meaning                          | alerts? |
|-----------|-------|----------------------------------|---------|
| `working` | blue  | the agent is busy                | no      |
| `waiting` | amber | the agent needs your input       | yes     |
| `done`    | green | the agent finished               | yes     |
| `error`   | red   | the agent errored                | yes     |

A plain `notify "msg"` with no `--state` defaults to `waiting`.

Run `install-paramux.cmd` before installing these adapters. It adds Paramux to
`PATH`, sets the absolute `PARAMUX_HOME` used by copied plugins, and replaces
the deliberately non-executable Claude/Codex template values with paths rooted
in that verified portable install. Restart each agent after installation so it
inherits `PARAMUX_HOME`. Codex and Gemini also require Node on `PATH`; their
launchers leave the project directory before resolving Node, validate each
payload, call the absolute `PARAMUX_HOME\paramux.com` with fixed arguments,
suppress child stdout, and return the JSON their hook protocols require.

## Claude Code

After running the portable installer, merge
[`claude-code.settings.json`](claude-code.settings.json) into your Claude Code
`settings.json` (`~/.claude/settings.json` for every project, or
`.claude/settings.json` inside one project). The installer writes the absolute
`paramux.com` path into this exec-form configuration. Do not copy the source
template while it still contains
`__PARAMUX_EXECUTABLE__?RUN_INSTALL_PARAMUX_PS1`. The settings map:

- `UserPromptSubmit` to `working`
- `Notification` to `waiting`, limited to
  `permission_prompt|elicitation_dialog` (the 60-second `idle_prompt`
  notification is deliberately excluded so it cannot overwrite a `done` pane)
- `Stop` to `done`
- `StopFailure` to `error`

## Codex CLI

After running the portable installer, copy
[`codex/hooks.json`](codex/hooks.json) to `~/.codex/hooks.json`. If
`hooks.json` already exists, merge the three event arrays instead of replacing
the file. Do not copy a source template that still contains
`__PARAMUX_CODEX_COMMAND_WINDOWS__?RUN_INSTALL_PARAMUX_PS1`. The installer
writes an absolute, encoded first-hop command; the packaged
`paramux-codex-hook.cmd` then anchors
itself to the portable root before resolving the adjacent bounded Node helper.
A repository working directory therefore cannot shadow either launcher. Run
this from the installed `agent-hooks` folder, not a repository checkout:

```powershell
New-Item -ItemType Directory -Path "$HOME\.codex" -Force | Out-Null
if (Test-Path "$HOME\.codex\hooks.json") {
    Write-Warning 'hooks.json already exists; merge the three event arrays from .\codex\hooks.json instead of overwriting.'
} else {
    Copy-Item .\codex\hooks.json "$HOME\.codex\hooks.json"
}
```

Restart Codex, then review and trust the commands through `/hooks`. The adapter
maps `UserPromptSubmit` to `working`, `PermissionRequest` to `waiting`, and
`Stop` to `done`. Codex has no stable generic turn-error event, so this adapter
does not guess at an `error` transition. The helper emits exactly `{}` on
stdout after a successful notification because Codex `Stop` parses hook stdout
as JSON. The legacy `notify` config is completion-only and is not used here.

## Gemini CLI

[`gemini-paramux`](gemini-paramux) is an installable Gemini CLI extension:

```powershell
gemini extensions install .\gemini-paramux
```

Restart Gemini after installation so the extension inherits `PARAMUX_HOME`.
The extension maps `BeforeAgent` to
`working`, `Notification` with matcher `ToolPermission` to `waiting`, and
`AfterAgent` to `done`. Its bounded helper validates stdin and emits exactly
`{}` on successful completion. Gemini has no stable generic agent-error event,
so the extension does not infer one from individual tool failures.

## OpenCode

Copy [`opencode/paramux.js`](opencode/paramux.js) to the project plugin directory
`.opencode/plugins/paramux.js`, or to the global plugin directory
`~/.config/opencode/plugins/paramux.js`. OpenCode loads local plugins at
startup. Restart OpenCode after `PARAMUX_HOME` is installed. The plugin uses
the absolute `PARAMUX_HOME\paramux.com` path with a no-shell child process and
maps `session.status` busy/idle to `working`/`done`, `permission.asked` to `waiting`,
and `session.error` to `error`. A same-session idle event after an error is
ignored so it cannot immediately overwrite the red error state.

## Manual test

From inside any paramux pane:

```
paramux notify --state=waiting testing paramux attention
```

The pane's sidebar dot should turn amber and a Windows toast should appear.
Focus or pane navigation preserves the alert so it remains readable; typing,
pasting, or clicking inside that terminal acknowledges and clears it.
