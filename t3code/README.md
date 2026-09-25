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

## Isolated Docker builder

T3 Code deliberately has no local Docker socket. Mounting the Coolify host's
socket would give every agent root-equivalent control over the production host.
Use an ordinary Docker SSH context through the Tailscale sidecar's SOCKS5
proxy. No Docker TCP API port, Coolify socket mount, or project-specific CLI is
needed. Keep the default Docker context unchanged; always pass `--context`.

### 1. Provision the builder

Choose a **separate**, persistent Ubuntu 24.04 x86_64 VM with at least 2 vCPU,
4 GiB RAM, and 60–80 GiB disk for ordinary Node/Compose builds. A dedicated
paid VM or existing home machine is more predictable than a tiny free-tier VM;
do not install Coolify on it. Keep provider-console access until SSH over the
tailnet works. On the VM, install OpenSSH, Docker Engine, and Compose v2:

```bash
sudo apt update
sudo apt install -y openssh-server docker.io docker-compose-v2
sudo systemctl enable --now ssh docker
sudo adduser --disabled-password --gecos '' docker-builder
sudo usermod -aG docker docker-builder
sudo install -d -m 700 -o docker-builder -g docker-builder /home/docker-builder/.ssh
```

Install Tailscale using its [official Ubuntu instructions](https://tailscale.com/download/linux/ubuntu),
then configure `tag:docker-builder` ownership in the tailnet policy and join:

```bash
sudo tailscale up --advertise-tags=tag:docker-builder
tailscale ip -4
```

Record that `100.x.y.z` IP. The T3 sidecar has `TS_ACCEPT_DNS=false`, so the SSH
alias below intentionally uses the IP, not MagicDNS. Add this narrow tailnet
grant (merge it with the existing policy, do not replace the policy):

```json
{"src":["tag:t3"],"dst":["tag:docker-builder"],"ip":["tcp:22"]}
```

The builder's Docker group is root-equivalent. Give this VM no production
credentials or mounts, keep it patched, and use a dedicated user/key. The
cloud firewall may close public inbound SSH **after** the tailnet connection
has been verified; do not lock yourself out before that point.

### 2. Deploy the T3 client changes

Deploy this Compose/image revision through Coolify and apply the `t3` chezmoi
preset in the running T3 container. The Tailscale sidecar now listens on
`127.0.0.1:1055` for SOCKS5; the image includes `nc`, and chezmoi installs the
Docker CLI and Compose plugin. In the T3 container, check:

```bash
docker --version
docker compose version
nc -h
```

`docker compose version` must succeed before creating the remote context. The
managed plugin symlink is `~/.docker/cli-plugins/docker-compose` and points to
the Linuxbrew installation.

### 3. Enroll SSH from T3

In the persistent T3 home volume, create a key and print its public half:

```bash
install -d -m 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/t3_builder_ed25519 -C t3-builder
cat ~/.ssh/t3_builder_ed25519.pub
```

From the VM's provider console or existing trusted SSH session, put that
single public-key line in `/home/docker-builder/.ssh/authorized_keys`, owned by
`docker-builder`, mode `600`. Also record the builder's SSH host fingerprint:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

On T3, add this host entry to `~/.ssh/config`, substituting the builder's
Tailscale IP:

```sshconfig
Host t3-builder
    HostName 100.x.y.z
    User docker-builder
    IdentityFile ~/.ssh/t3_builder_ed25519
    IdentitiesOnly yes
    ProxyCommand nc -X 5 -x 127.0.0.1:1055 %h %p
```

Set `~/.ssh/config` to mode `600`. Run `ssh t3-builder`, compare the displayed
host fingerprint with the one obtained on the VM console, and accept it only
if they match. Afterwards add `StrictHostKeyChecking yes` to the host entry.
The SSH key and known-host entry remain in the persistent `t3-home` volume.

### 4. Create and verify the native context

```bash
docker context create t3-builder --docker 'host=ssh://t3-builder'
docker --context t3-builder info
docker --context t3-builder compose version
docker context ls
```

The context metadata is in `~/.docker` within `t3-home`. Do **not** run
`docker context use t3-builder`: an explicit context prevents unrelated agent
commands from silently targeting the remote VM. Do not expose the Docker API
on TCP 2375/2376 or mount either host's `/var/run/docker.sock` into T3.

### 5. Use it safely from agent tasks

For an image build with local source, Docker sends the build context over SSH:

```bash
cd ~/dev/example
docker --context t3-builder compose build
docker --context t3-builder compose up -d
docker --context t3-builder compose ps
```

`compose up` interprets host bind-mount source paths **on the builder**, not in
the T3 container. For a bind-free stack, prefer named volumes. For a project
that bind-mounts source code, clone/check out the project on the builder and
run Compose from that checkout over SSH, or prepare an explicit builder-side
sync workflow. A successful remote build alone does not make local bind mounts
available. Published container ports also live on the builder; reach them by
its Tailscale IP with a narrowly scoped tailnet grant, not via T3 localhost.

Use `docker --context t3-builder compose down` when finished; add `-v` only
when test volumes may be deleted. The builder should have its own disk/log
monitoring and deliberate cleanup policy. `ax --sandbox codex` may additionally
need a Nono profile that grants the specific SSH key/config and proxy access;
plain Codex does not use that extra sandbox. Do not broaden the shared agent
profile merely to make Docker work.

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
