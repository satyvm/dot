# T3 Code Remote Development Stack

A Coolify-deployed Docker Compose application: T3 Code server, SSH, the full
chezmoi CLI toolset, and the agent CLIs — reachable only over Tailscale.

## Services

| Service | Role | Ingress | Limits |
|---|---|---|---|
| `tailscale` | Own tailnet node (`t3-dev`), terminates HTTPS on :443 | UDP 41642 only | 256M / 0.5 |
| `t3code` | `t3 serve` on :3773, `sshd`, chezmoi toolset, agents | via the sidecar's namespace | 8G / 4.0 |
| `cliproxyapi` | Model gateway for `ax`, **opt-in** | none | 512M / 0.5 |
| `tea-sidecar` | Gitea API over a unix socket | none | 256M / 0.25 |

**No Coolify domain is assigned to this application.** T3 Code's only
authentication is a pairing token, and upstream advises against exposing a
development server to the public internet on that basis. The Tailscale sidecar
is the entire ingress surface.

## Why the sidecar owns its own tailnet node

Coolify's Traefik binds `0.0.0.0:443`, which includes the host's Tailscale
address, so `tailscale serve` on the *host* would collide with it. Giving the
container its own node sidesteps that: it gets its own tailnet IP where :443 is
free. Two tailnet nodes on one machine do not conflict — separate network
namespaces mean separate port spaces — and the host's tailscaled stays dedicated
to exit-node duty.

Three settings make this work, and all three are load-bearing:

- `TS_ACCEPT_DNS=false` — otherwise tailscaled overwrites `/etc/resolv.conf` in
  the shared namespace, replacing Docker's embedded resolver at `127.0.0.11`,
  and `http://cliproxyapi:8317` stops resolving. This is a name-resolution
  setting, not a security control.
- `--advertise-tags=tag:t3` — untagged nodes have key expiry and would silently
  drop off the tailnet. Tagged nodes do not expire.
- `--port=41642` — the host's tailscaled already uses 41641; a distinct port
  lets this node negotiate direct connections instead of falling back to DERP.

## Persistence

| Volume | Path | Losing it costs |
|---|---|---|
| `ts-state` | `/var/lib/tailscale` | node identity — a new MagicDNS name every redeploy |
| `t3-state` | `/home/ubuntu/.t3` | every T3 session, pairing, and the state database |
| `t3-home` | `/home/ubuntu` | shell, chezmoi, and agent state |
| `npm-global` | `/home/ubuntu/.npm-global` | rebuild-free `t3` upgrades |
| `ssh-host-keys` | `/etc/ssh/host-keys` | stable SSH fingerprints |
| `cliproxy-auth` | gateway auth dir | provider OAuth logins |
| host bind | `/home/ubuntu/dev` | nothing — it lives on the host |

`/home/ubuntu/dev` is the only host path bound in. That container boundary — not
T3 Code — is what limits agents to the workspace.

## Upgrading without a rebuild

```bash
docker exec -u ubuntu <t3code> npm i -g t3@latest
docker restart <t3code>
```

Only base tooling changes need an image rebuild.

## Gateway is opt-in

```bash
docker compose --profile gateway up -d
```

Direct `claude`/`codex` never touch it; only `ax` does. Adding a provider later
needs no rebuild, because auth lives in a writable volume:

```bash
docker exec -it <cliproxyapi> /CLIProxyAPI/CLIProxyAPI \
  -config /config/config.yaml -no-browser -antigravity-login
```

## Validation

```bash
bash t3code/tests/test_stack.sh
```
