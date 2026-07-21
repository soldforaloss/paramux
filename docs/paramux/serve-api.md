# `paramux serve` — local HTTP API

`paramux serve [--port=7877]` bridges the running instance's fleet
state to plain HTTP on `127.0.0.1` only. It exists so dashboards,
scripts, and Stream Deck-style tooling can read fleet state without
speaking the binary IPC protocol. It never binds a non-loopback
address and serves no mutation endpoints — the write path stays on
the token-gated IPC pipe.

## Endpoints

### `GET /status` (alias `GET /`)

Fleet structure as JSON — the same `paramux.windows.v2` payload that
`paramux list-windows` prints: windows → workspaces → panes with
titles, ids, attention states, and reported token totals.
Unauthenticated by design: it is structure-only and the listener is
loopback-only. No pane text ever appears here.

```
curl http://127.0.0.1:7877/status
```

`/status` also carries a content-hash `ETag` and honors
`If-None-Match` with `304`, same as the pane-text route.

### `GET /panes/<id>/text`

The pane's full text (screen + scrollback) as `text/plain; charset=utf-8`.
Pane CONTENT crosses a privacy line that structure does not, so this
route requires the instance token:

```
Authorization: Bearer <token>
```

The token is the same per-instance secret the IPC pipe uses, read
from `%LOCALAPPDATA%\paramux\` (or `PARAMUX_TOKEN` inside a pane).
The comparison is constant-time; a missing or wrong token returns
`401` with no body detail.

```powershell
$token = Get-Content "$env:LOCALAPPDATA\paramux\paramux-ipc-token"
curl -H "Authorization: Bearer $token" http://127.0.0.1:7877/panes/42/text
```

Unknown pane ids return `404`.

Responses carry a content-hash `ETag`; send `If-None-Match` to get
`304 Not Modified` with no body when the pane hasn't changed —
recommended for pollers.

## Non-goals

- **No remote access.** Binding is hardcoded to loopback; put a
  reverse proxy with real auth in front if you must bridge machines,
  per `remote-design.md` (notify-only inbound remains the rule).
- **No mutations.** Splitting, sending input, and notifications go
  through the IPC pipe with its token gate, not HTTP.
- **No streaming.** Poll `/status`; the payload is small. Recording a
  pane over time is `paramux record`'s job.

## Stability

The `/status` payload shape follows the frozen `paramux.windows.v2`
wire contract (see `config-deprecation-policy.md`): additive-only.
`/panes/<id>/text` returns opaque text with no format promises.
