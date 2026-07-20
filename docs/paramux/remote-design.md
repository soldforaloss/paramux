# Remote fleets (design — not scheduled)

Could one paramux window conduct agents on other machines? This
document pins the shape such a feature must take before any code
lands, so drive-by PRs have something to be measured against. Nothing
here is committed work; the 1.0 roadmap explicitly lists remote panes
as post-1.0.

## What already works today

- A pane is just a ConPTY running a command — `ssh host` in a pane IS
  a remote shell, and Ghostty's shell-integration-over-SSH machinery
  (`ssh-cache`, terminfo forwarding) rides along.
- Agent hooks on the REMOTE machine cannot reach the local pipe, so
  attention states don't flow back. That is the entire gap: **remote
  attention**, not remote terminals.

## The smallest honest design: attention forwarding

1. On the remote host, agents call a tiny `paramux-relay notify ...`
   (or `paramux notify --stdout-frame`) that writes a single framed
   line to stdout instead of a pipe.
2. The LOCAL pane's shell integration recognizes the frame in the
   output stream (exactly how OSC 777 notifications already travel)
   and the existing parser flags the pane.

In fact **OSC 777 already crosses SSH**: `paramux notify` falls back
to writing the escape sequence to the terminal when no pipe answers —
which is precisely the remote case. So v1 may be: document that
installing the paramux CLI remotely and letting the console fallback
fire is ALREADY remote attention, then fix whatever gaps testing
reveals (state markers survive tmux-free SSH; message length limits;
`--tokens` riders).

## What is out of scope by design

- A network protocol of our own, agents dialing home, or any listener
  beyond the local pipe (see the security posture: the control surface
  is strictly local, `PIPE_REJECT_REMOTE_CLIENTS`).
- Cloud relays. If two machines need to meet, SSH is the transport.

## Acceptance bar for any implementation PR

- Threat model paragraph (what the remote end can and cannot trigger —
  notify-only; never send/read-pane/perform-action inbound).
- Works over plain `ssh host` in a pane with the CLI installed
  remotely; no daemon.
- Documented in the capability matrix with a truthful Partial row.
