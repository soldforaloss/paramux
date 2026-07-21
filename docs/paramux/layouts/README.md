# Layout templates

Drop one of these into your project as `.paramux/layout` and
`paramux open .` recreates the split arrangement as a new workspace:

```powershell
mkdir .paramux
copy path\to\two-column.layout.json .paramux\layout
paramux open .
```

| Template | Arrangement |
| --- | --- |
| `two-column.layout.json` | Two side-by-side panes (the default workspace shape). |
| `grid-2x2.layout.json` | Four panes in a 2x2 grid — one agent per quadrant. |
| `main-plus-side.layout.json` | A large main pane (2/3 width) with two stacked helpers on the right. |

The format is the `layouts.json` slot shape (`win32_session_state.Tab`):
`selected_leaf` picks the focused pane, `layout.nodes` is a flat array of
`pane` / `split` nodes, and `layout.root` indexes the tree's root.
Splits carry `axis` (`horizontal` = side-by-side, `vertical` = stacked),
`ratio` (0..1 toward `first`), and child indexes. Panes may pin a
`cwd`; omitted fields inherit defaults.

You can also author by arranging a workspace live and using
right-click → **Save Layout To** — slot 5 of
`%LOCALAPPDATA%\paramux\layouts.json` is what `paramux open` installs,
so a saved slot is a valid template body.

Templates may also carry a startup `command` and `env` entries per
pane, plus a workspace-level `env` applied to every pane (pane
entries win on conflict) — see `agents-with-env.layout.json`.
