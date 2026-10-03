# T3 Code Remote Development Stack

A Coolify-deployed Docker Compose application: T3 Code server, SSH, the full
chezmoi CLI toolset, and the agent CLIs — reachable only over Tailscale.

## Three-environment topology

The T3 client connects to three independent environments. Chezmoi deliberately
keeps their agent behavior consistent, while T3 keeps each environment's
threads, projects, provider instances, OAuth sessions, and API keys local to
the server that owns them.

| Environment | Chezmoi preset | T3 lifecycle | Gateway route |
|---|---|---|---|
| macOS | `workstation` | T3 desktop app, or `npx t3@latest serve --tailscale-serve` | local CLIProxyAPI at `127.0.0.1:8317` |
| Ubuntu WSL | `workstation` | `npx t3@latest service install` when systemd is enabled; otherwise run `npx t3@latest serve --tailscale-serve` | local CLIProxyAPI at `127.0.0.1:8317` |
| Coolify | `t3` | Compose/Supervisord, managed by this directory | `cliproxyapi:8317` sidecar |

Pair each server separately in **Settings → Connections**. Provider login and
the instance matrix below must also be completed once per environment; a T3
client connection does not copy server credentials. Use the HTTPS MagicDNS
endpoint produced by Tailscale Serve for browser clients. Plain Tailnet HTTP is
usable by native clients but is blocked as mixed content by `app.t3.codes`.

The repository does not enroll personal machines into a tailnet or create their
T3 pairing credentials. Those operations create external account state and are
intentionally left to `tailscale up` and T3's one-time pairing flow.

## Services

| Service | Role | Ingress | Limits |
|---|---|---|---|
| `tailscale` | Own tailnet node (`t3-dev`), terminates HTTPS on :443 | UDP 41642 only | 256M / 0.5 |
| `t3code` | `t3 serve` on :3773, `sshd`, chezmoi toolset, agents | via the sidecar's namespace | 4G / 1.5 |
| `cliproxyapi` | Model gateway for `ax`, **opt-in** | none | 512M / 0.5 |
| `t3-control` | Tailscale discovery, private app routes, diagnostics, and Gitea API over Unix sockets | none | 128M / 0.25 |

**No Coolify domain is assigned to this application.** T3 Code's only
authentication is a pairing token, and upstream advises against exposing a
development server to the public internet on that basis. The Tailscale sidecar
is the entire ingress surface.

`t3-control` runs the Tailscale and Gitea APIs in one Python process. Its
healthcheck verifies the protected T3 route and the Gitea socket; failure of
either API stops the process so Docker can restart it. Gitea requests run in
worker threads so they cannot block route management. The development container
receives both client sockets, while the Gitea token and Tailscale daemon socket
stay inside the control service.

When upgrading from the separate `tailscale-control` and `tea-sidecar` services,
redeploy the complete Compose stack and remove the obsolete service containers.
The existing `tea-socket`, `t3-share-socket`, and `t3-share-state` volumes are
reused; keep the volumes when removing old containers. Stop the old helpers
before starting `t3-control` so they cannot compete for the shared sockets.

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

## Sharing development apps

Inside T3, start an HTTP app on `127.0.0.1:3000` (or `0.0.0.0:3000`), then run:

```bash
t3-share hostname
t3-share check 3000
t3-share 3000
```

The last command prints the actual URL, such as
`https://t3-dev.example.ts.net:8443`. It discovers the hostname from Tailscale
rather than assuming the requested node name was available. The first free
listener from 8443–8499 is assigned; repeated sharing returns the same URL.
Up to 57 app routes can be registered at once.
`t3-share share 3000 --listen 9443` selects an external port explicitly.
The backend stays HTTP while Tailscale terminates HTTPS. Configure the app's
allowed hosts and WebSocket/HMR origin for the returned hostname and port.

| Command | Purpose |
|---|---|
| `t3-share status` | Connection state, actual hostname, IPs, certificate domains, and health warnings |
| `t3-share hostname` / `t3-share ip` | Print the discovered hostname or tailnet addresses |
| `t3-share ports` | List listening TCP ports in the shared network namespace |
| `t3-share check 3000` | Test TCP reachability at localhost; exits nonzero when unavailable |
| `t3-share list` / `t3-share url 3000` | List the platform and app routes, or print one app URL |
| `t3-share share 5432 --tcp` | Forward raw TCP to a local service; prints a `tcp://` endpoint |
| `t3-share remove 3000` | Remove an app route without stopping the app |
| `t3-share peers` | List visible peers, online state, relay region, and current direct address |
| `t3-share doctor` | Check node health, applied routes, T3 backend, and shared app backends |
| `t3-share --json <command>` | Return JSON for agent automation |

Routes are private to the tailnet and require ACL/grant access to their external
listener ports. Backend checks verify TCP reachability only; test the returned
URL from a permitted tailnet device to verify HTTP, HTTPS, and access rules.
UDP and HTTPS backends are not supported by this helper. Remove routes when an
app is stopped or abandoned: routes survive restarts and a reused local port
would otherwise become reachable through its previous route.

The control broker shares the sidecar's network namespace and owns the entire
Serve configuration, including the protected `443 → localhost:3773` T3 route.
It reconciles routes at startup and every five seconds, using the discovered
certificate domain, and checks them in its healthcheck. HTTPS must be enabled
in the tailnet. Only the broker and Tailscale mount the daemon socket; T3 mounts
a separate control socket with group access matching `REMOTE_GID`.
The broker allows localhost targets, reserves platform ports, never enables
Funnel, and accepts no arbitrary Tailscale or Docker commands. It does not mount
the node identity state or Docker socket. Existing agent context sources teach
the T3-only workflow, and `ax` grants the helper socket to sandboxed agents.

Validate changes with `python3 -m unittest discover -s t3code/tests -p 'test_*.py'`
and `bash t3code/tests/test_stack.sh`. A deployment rebuild is required to ship
the command and broker; chezmoi provisioning updates the shared agent context.

## Persistence

| Volume | Path | Losing it costs |
|---|---|---|
| `ts-state` | `/var/lib/tailscale` | node identity — a new MagicDNS name every redeploy |
| `t3-share-state` | `/var/lib/t3-share` | registered app routes |
| `t3-state` | `/home/ubuntu/.t3` | every T3 session, pairing, and the state database |
| `t3-home` | `/home/ubuntu` | shell, chezmoi, and agent state |
| `npm-global` | `/home/ubuntu/.npm-global` | rebuild-free `t3` upgrades |
| `ssh-host-keys` | `/etc/ssh/host-keys` | stable SSH fingerprints |
| `cliproxy-auth` | gateway auth dir | provider OAuth logins |
| host bind | `/home/ubuntu/dev` | nothing — it lives on the host |

`/home/ubuntu/dev` is the only host path bound in. That container boundary — not
T3 Code — is what limits agents to the workspace.

## Upgrading without a rebuild

On each container start, provisioning checks the npm `latest` release against
the version in the persistent npm volume. When a newer release exists, it
installs that version and restarts only the T3 server. An unavailable registry
leaves the installed server running and records a provisioning failure. Updates
can interrupt active threads, so enable **Settings → General → Continue threads
after restarts** if you want supported threads to resume.

For an immediate update without restarting the container:

```bash
docker exec -u ubuntu <t3code> npm i -g t3@latest
docker exec <t3code> supervisorctl -c /etc/supervisor/conf.d/t3code.conf restart t3code
```

Only base tooling changes need an image rebuild.

## Gateway is opt-in

```bash
docker compose --profile gateway up -d
```

In Coolify, set `COMPOSE_PROFILES=gateway` on the Compose application to make
the same opt-in profile start during deploy. Without it, plain agents and
`ax --sandbox` still work, but gateway launches intentionally have no service
to contact.

Direct agent commands never touch it. `ax <agent>` keeps the compatibility
default of Nono plus gateway; the boundaries can also be selected separately:

```bash
ax --sandbox codex          # or: ax -s codex
ax --gateway codex          # or: ax -g codex
ax --sandbox --gateway codex # or: ax -sg codex
```

`ax` intentionally supports only `claude`, `codex`, `opencode`, and `omp`.
Adding a gateway provider later
needs no rebuild, because auth lives in a writable volume:

```bash
docker exec -it <cliproxyapi> /CLIProxyAPI/CLIProxyAPI \
  -config /config/config.yaml -no-browser -antigravity-login
docker exec -it <cliproxyapi> /CLIProxyAPI/CLIProxyAPI \
  -config /config/config.yaml -no-browser -codex-login
```

Set `OPENROUTER_API_KEY` in Coolify before starting the gateway profile; it is
the third and only key-based gateway channel.

## T3 provider instances

Do not edit T3's SQLite state from chezmoi. In **Settings → Providers**, add
instances using the managed configuration below; T3 persists the choices and
sensitive environment variables in its own state volume.

| T3 instance | Driver | Configuration |
|---|---|---|
| Codex — ChatGPT Plus | Codex | Binary `codex`; default `CODEX_HOME`; run `codex login` |
| Codex — OpenRouter | Codex | Binary `codex`; `CODEX_HOME=~/.config/t3-code/codex/openrouter`; sensitive `OPENROUTER_API_KEY` |
| Codex — Pioneer | Codex | Binary `codex`; `CODEX_HOME=~/.config/t3-code/codex/pioneer`; sensitive `PIONEER_API_KEY` |
| Codex — CLIProxy | Codex | Binary `codex`; `CODEX_HOME=~/.config/t3-code/codex/cliproxy`; sensitive `CLIPROXY_CLIENT_KEY` |
| OpenCode — ChatGPT | OpenCode | Binary `opencode`; authenticate with `opencode auth login` |
| OpenCode — OpenRouter | OpenCode | A second instance with sensitive `OPENROUTER_API_KEY`; select OpenRouter models |
| OpenCode — Pioneer | OpenCode | A second instance; `/connect` → Pioneer, or sensitive `PIONEER_API_KEY`; choose Pioneer Auto |
| Antigravity | Antigravity | Use T3's managed runtime and Google sign-in |
| Cursor | Cursor | Binary `cursor-agent`; authenticate with `agent login` |
| Grok | Grok Build | Binary `grok`; authenticate with `grok login` |

ChatGPT Plus is used only by Codex/OpenCode flows that explicitly implement
OpenAI account OAuth. It is not a credential for Cursor or Grok, so those two
instances use their own vendor logins.

T3 currently has no first-class Oh My Pi or Crush provider driver. They remain
available in the terminal as `omp` and `crush`, but making either a native T3
thread type requires an upstream T3 provider adapter. There is no settings-only
or chezmoi-only way to add that thread type without maintaining code.

## Validation

```bash
bash t3code/tests/test_stack.sh
```
