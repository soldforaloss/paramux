# Session-state JSON schema

`%LOCALAPPDATA%\paramux\session-state.json` (or
`session-state-<name>.json` under `session-name`) persists window
layout across runs. The same `Tab` shape is the layout-template
format (`layouts.json` slots, `.paramux/layout`,
`export-layout`/`import-layout` files). Source of truth:
`src/apprt/win32_session_state.zig`.

## Policy

- **Additive-only** (see `config-deprecation-policy.md`): fields are
  added with defaults, never renamed or removed; `schema_version`
  stays `1` until a break is unavoidable.
- Parsing is strict for saves (`ignore_unknown_fields = false` on the
  session path) and lenient for templates; every string is owned by
  the parse (`alloc_always`) — nothing borrows the input buffer.
- Writers emit no null optionals; readers tolerate UTF-8 BOMs on the
  template paths.

## Shape

```jsonc
{
  "schema_version": 1,
  "windows": [{
    "x": 78, "y": 78, "width": 1280, "height": 800,   // all four or none
    "state": "normal",                                  // or "maximized"
    "selected_tab": 0,
    "tabs": [{
      "note": "scratch line",          // workspace note (optional)
      "env": ["K=V"],                  // layout templates only: every pane
      "selected_leaf": 0,
      "layout": {
        "root": 2,
        "nodes": [
          { "pane": { "cwd": "C:\\repo",
                       "profile": "pwsh",
                       "title_override": null,
                       "tab_title_override": null,
                       "command": "claude",   // see below
                       "env": ["ROLE=impl"] } },
          { "pane": {} },
          { "split": { "axis": "vertical", "ratio": 0.5,
                        "first": 0, "second": 1 } }
        ]
      }
    }]
  }]
}
```

## Field semantics

- `layout.nodes` is an index-addressed tree: `root` and each split's
  `first`/`second` are node indexes. Validation rejects cycles,
  shared nodes, unreachable nodes, out-of-range indexes, non-finite
  or out-of-[0,1] ratios, and empty layouts.
- `pane.command`: plain saves never emit it; the opt-in
  `restore-commands` capture does (the running child's command line),
  and layout templates may author it. Restore/apply runs it.
- `pane.env` / `tab.env`: layout-templates-only extra environment
  ("KEY=value"); the tab-level entries apply to every pane and a
  pane's own entries win.
- Window rect fields are all-or-nothing; sizes must be positive.

## layouts.json

`%LOCALAPPDATA%\paramux\layouts.json` wraps five optional `Tab`
bodies plus display names (both arrays are additive):

```jsonc
{
  "slots": [ <Tab|null>, null, null, null, null ],
  "names": [ "api-fleet", null, null, null, null ]
}
```

`names` feeds the menus, `open --list`, and `--name=` addressing on
`open` / `import-layout` / `export-layout` (case-insensitive). The
file is hand-editable; readers tolerate a UTF-8 BOM.

## Lifecycle

Saves happen on the ~60s autosave, the `save_session` action, and
quit-with-windows-open. **Closing the last window deletes the file
on purpose** ("forget this session"); named sessions via
`session-name` isolate fleets.
