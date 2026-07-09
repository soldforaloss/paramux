# paramux agent-attention hooks

These snippets wire the four supported AI coding agents into paramux's
attention system (FR-4/FR-5). Each agent calls the built-in `+notify` CLI when
its state changes; paramux colors that pane's sidebar row and fires a Windows
toast + taskbar flash.

## How it works

`paramux +notify [--state=<state>] [--title=<t>] <message...>` emits an
OSC 777 desktop-notification escape sequence on the terminal it runs in. Because
the sequence travels the pane's own ConPTY, it **auto-targets the pane the
command ran in** — no window or surface id needed. On Windows the sequence is
written directly to `CONOUT$` rather than stdout, so it still reaches paramux
even though agent hooks capture their child processes' stdout.

`--state` is one of:

| state     | color | meaning                          | alerts? |
|-----------|-------|----------------------------------|---------|
| `working` | blue  | the agent is busy                | no      |
| `waiting` | amber | the agent needs your input       | yes     |
| `done`    | green | the agent finished               | yes     |
| `error`   | red   | the agent errored                | yes     |

A plain `+notify "msg"` with no `--state` defaults to `waiting`.

Prerequisite: `paramux` must be on `PATH` (Windows resolves `paramux` to
`paramux.com`, the console variant). Otherwise use the full path to
`paramux.com` in the commands below.

## Claude Code

Merge [`claude-code.settings.json`](claude-code.settings.json) into your Claude
Code `settings.json` (`~/.claude/settings.json` for every project, or
`.claude/settings.json` inside one project). It maps Claude Code's lifecycle
hooks — `UserPromptSubmit` → working, `Notification` → waiting, `Stop` → done.

## Codex CLI

Codex runs a program on turn completion via the `notify` setting in
`~/.codex/config.toml`. Point it at a small script that calls `+notify`:

```toml
notify = ["paramux", "+notify", "--state=done", "Codex finished"]
```

Codex appends a JSON argument describing the event; `+notify` ignores extra
trailing args, so the fixed `--state=done` message still fires on completion.
For a richer mapping, wrap it in a script that inspects the JSON `type` field
and picks `--state=waiting` vs `--state=done`.

## Gemini CLI

Gemini CLI has no stable hook surface yet. Two options:

1. **Wrapper alias** — run Gemini through a wrapper that emits
   `paramux +notify --state=working ...` before launch and
   `paramux +notify --state=done ...` after it exits.
2. **OSC fallback** — any tool that emits an OSC 9 or OSC 777 notification
   sequence lights the pane automatically (paramux already listens for these).

## OpenCode

OpenCode exposes a plugin/event system. Add a plugin that shells out to
`paramux +notify --state=<state> ...` on its session-idle / session-complete
events, mirroring the Claude Code mapping.

## Manual test

From inside any paramux pane:

```
paramux +notify --state=waiting testing paramux attention
```

The pane's sidebar dot should turn amber and a Windows toast should appear.
Focusing the pane clears the state.
