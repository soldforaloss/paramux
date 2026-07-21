# Fleet CLI reference

One page for scripting a paramux fleet. Every verb talks to the
running instance over the local token-gated IPC pipe; nothing here
leaves the machine. `paramux <verb> --help` has the full flag list —
this is the map.

## Watch

```powershell
paramux status                  # one table: workspace, pane, state, tokens
paramux status --watch --interval=5
paramux status --notes          # adds "# workspace N accent: 3 note: ..." lines
paramux status --json           # the raw list-windows v2 payload
paramux attention               # every pane's timeline as JSON (last 8 transitions)
paramux version --json
```

## Drive

```powershell
paramux run "claude -p 'fix the tests'"     # spawn a pane, type the command, print its id
paramux run --workspace=current "npm test"
paramux send --surface-id=<id> "y`n"        # exact input to one pane
paramux send --all-panes "git pull`n"       # active workspace; skips solo (opt-out) panes
paramux read-pane --surface-id=<id>         # pane text back out
paramux perform-action new_split:auto       # any allowlisted keybind action
paramux perform-action restart_pane         # fresh shell in the focused pane's cwd
```

## Signal

```powershell
paramux notify --state=waiting "needs approval"   # from inside a pane (or hooks)
paramux notify --surface-id=<id> --state=done ok  # explicit pane, from anywhere
paramux notify --focused --state=error "look"     # the focused pane
```

States color the sidebar: `working` blue, `waiting` amber, `done`
green, `error` red, `none` clears. Attention timelines export via the
Command Palette (JSON + CSV, per-pane workspace note included) and
over `GET /attention` (see [serve-api.md](serve-api.md)).

## Layouts

```powershell
paramux open --list                    # five slots + project-layout status
paramux open . --name=api-fleet        # open a directory with a saved layout
paramux import-layout grid-2x2         # bundled gallery -> first empty slot
paramux import-layout 2 team.layout.json --name=team
paramux export-layout --name=team team.layout.json
paramux export-layout --all=backups\
```

Bundled gallery names: `agents-with-env`, `grid-2x2`,
`main-plus-side`, `two-column` (see [layouts/README.md](layouts/README.md)).

## Operate

```powershell
paramux doctor --json          # environment + IPC + UIA + session probes
paramux doctor --fire          # test signals + read_attention round-trip
paramux serve --port=7890      # loopback HTTP mirror (ETag/304, Bearer on content)
paramux record --surface-id=<id> --idle-limit=30
paramux update --check         # or --version=X to pin, --rollback to undo
```

All ids on the wire are `u64` — in scripts, regex them out of raw
JSON rather than round-tripping through a float-based JSON parser
(PowerShell's `ConvertFrom-Json` corrupts ids above 2^53).
