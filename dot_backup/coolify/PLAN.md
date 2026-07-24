# Coolify Hermes Remote Development Platform

## Implemented architecture

The Mac and Coolify server are independent development environments connected
only through Git:

- Mac: `/Users/s/dev`, local CLIProxyAPI on `127.0.0.1:8317`, local agents,
  MCPs, LSPs, Nono, and Herdr.
- Server: host `/home/ubuntu/dev` bind-mounted at the identical path inside
  `hermes-dev`, a persistent `/home/ubuntu`, a private server-only CLIProxyAPI,
  and the same agents, MCP catalog, LSPs, Nono, and Herdr.

The Compose application contains:

1. `cliproxy-init`, a one-shot service that creates the server-only proxy config
   and shared client key with restrictive permissions.
2. `cliproxyapi`, which is reachable only as `http://cliproxyapi:8317` on the
   private Compose network.
3. `hermes-dev`, a custom image containing Hermes Agent, Hermes WebUI, OpenSSH,
   chezmoi, `ax`, Nono, Herdr, Claude Code, Pi, OpenCode, Crush, MCP runtimes,
   and the shared LSP toolchain.

Only WebUI port `8787` receives a Coolify domain. Container SSH is published on
the host loopback address only. CLIProxyAPI has neither a host port nor a
Coolify domain.

## Persistence contract

| Storage | Container path | Owner |
|---|---|---|
| `remote-home` | `/home/ubuntu` | shell, chezmoi, editor and agent state |
| host bind | `/home/ubuntu/dev` | project repositories |
| `hermes-state` | `/home/ubuntu/.hermes` | Hermes and WebUI state |
| `ssh-host-keys` | `/etc/ssh/host-keys` | stable SSH fingerprints |
| `cliproxy-auth` | `/root/.cli-proxy-api` | server provider authentication |
| `cliproxy-config` | `/config` | generated server proxy configuration |

The entrypoint verifies that `/home/ubuntu/dev` is a real mount and that its
numeric owner matches the container `ubuntu` UID/GID. It never recursively
changes project ownership. The chezmoi repository is cloned once into
`/home/ubuntu/.local/share/chezmoi` and applied with `aiMode = "remote"`.

## Shared MCP and LSP catalog

`.chezmoidata/ai-tools.yaml` is the shared inventory. Chezmoi renders it into:

- Hermes' `mcp_servers` key in `~/.hermes/config.yaml`, merged without
  replacing provider or WebUI settings;
- OpenCode `~/.config/opencode/opencode.json`;
- Crush `~/.config/crush/crush.json`;
- Claude Code's user `mcpServers` while preserving all unrelated
  `~/.claude.json` state; and
- Zed settings on macOS and Linux.

Filesystem MCP access is limited to `/Users/s/dev` locally and
`/home/ubuntu/dev` remotely. Credentials remain environment variables and are
not rendered into the repository. Pi receives the shared model/provider and
Herdr configuration but is omitted from MCP rendering because its current
upstream client does not have native MCP configuration.

The catalog declares vtsls, Pyright, gopls, and rust-analyzer. Zed remote
projects run their terminals, tasks, and language servers inside the
`hermes-dev` SSH destination, against server-side files and binaries.

## Deploy in Coolify

Use a Git-based Docker Compose application whose base directory is
`dot_backup/coolify` and whose Compose file is
`hermes_docker_compose.yaml`.

Before the first deployment, run on the host:

```bash
sudo install -d -o ubuntu -g ubuntu -m 0755 /home/ubuntu/dev
id ubuntu
stat -c '%u:%g %n' /home/ubuntu/dev
```

Set the values listed in `.env.example` in Coolify. `REMOTE_UID` and
`REMOTE_GID` must equal the host `ubuntu` numeric IDs. Use distinct random
values for the proxy client key, proxy management key, and WebUI password.
`DEV_SSH_PUBLIC_KEY` must be a dedicated container public key, not the Coolify
host key.

Assign a domain only to `hermes-dev:8787`. Do not assign domains or ports to
`cliproxyapi`. Keep the Compose SSH mapping exactly loopback-bound:

```yaml
ports:
  - "127.0.0.1:${DEV_SSH_PORT:-2222}:22"
```

The first deployment clones and applies the dotfiles, so it takes longer than a
normal restart. Later image replacements reuse all persistent volumes.

## Server-side CLIProxyAPI authentication

The Mac and server proxy states are intentionally unrelated. Authenticate
providers into the server's `cliproxy-auth` volume through the Coolify terminal
or a short-lived SSH tunnel required by that provider. Do not copy the Mac auth
directory and do not permanently publish callback ports.

After authentication:

```bash
curl -H "Authorization: Bearer $CLIPROXY_CLIENT_KEY" \
  http://cliproxyapi:8317/v1/models
```

Run that command inside the Compose network, then remove any temporary callback
route.

## SSH and Zed

Create a dedicated key on the Mac:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/hermes_dev_ed25519 -C hermes-dev
```

Put its public half in Coolify as `DEV_SSH_PUBLIC_KEY`. Keep the private half
only on the Mac. Add this to the Mac's existing `~/.ssh/config`, replacing the
host and host-key path:

```sshconfig
Host coolify
    HostName your-server.example.com
    User ubuntu
    IdentityFile ~/.ssh/coolify_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host hermes-dev
    HostName 127.0.0.1
    Port 2222
    User ubuntu
    ProxyJump coolify
    IdentityFile ~/.ssh/hermes_dev_ed25519
    IdentitiesOnly yes
    ForwardAgent no
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

The Coolify host SSH daemon must allow TCP forwarding. Validate the path before
opening Zed:

```bash
ssh hermes-dev 'whoami; printf "%s\n" "$HOME"; command -v ax herdr zsh'
ssh hermes-dev 'test -d /home/ubuntu/dev && ax doctor'
```

The managed macOS Zed settings register `hermes-dev` and
`/home/ubuntu/dev`. Open Zed's Remote Projects dialog and select that
connection, or use:

```bash
zed ssh://hermes-dev/home/ubuntu/dev
```

Open an individual repository when possible. Zed uploads its matching headless
binary over SSH and persists it under `/home/ubuntu/.zed_server`. In the remote
session, terminals, tasks, formatters, and LSPs execute inside `hermes-dev`.

## Daily operation

Local work:

```bash
cd /Users/s/dev/project
ax doctor
ax opencode
```

Remote work:

```bash
ssh hermes-dev
cd /home/ubuntu/dev/project
ax doctor
ax opencode
```

Update the persistent remote dotfiles independently:

```bash
ssh hermes-dev 'chezmoi update'
```

Application dependencies change through a committed Dockerfile/Compose update
and a Coolify redeploy. User configuration changes through `chezmoi update`.
Project code changes through normal Git operations.

## Validation and acceptance

Before committing:

```bash
bash dot_local/bin/tests/test_ax.sh
bash dot_backup/coolify/tests/test_stack.sh
chezmoi diff
```

After deployment, verify:

1. WebUI login and `/health`.
2. `ssh hermes-dev` and stable host fingerprint across a redeploy.
3. `/home/ubuntu/dev` file visibility from the host, SSH shell, and WebUI.
4. `ax doctor`, all four agent launchers, and a Herdr resume.
5. Filesystem, fetch, and GitHub MCP availability with server credentials.
6. vtsls, Pyright, gopls, and rust-analyzer from a Zed remote project.
7. Mac workflow while Coolify is stopped, and server workflow while the Mac is
   offline.
8. Restore of `remote-home`, `hermes-state`, `cliproxy-auth`, and the separately
   backed-up `/home/ubuntu/dev`.

The stack is ready for deployment when both local test scripts pass. Actual
image-build, provider OAuth, WebUI-to-shell file visibility, SSH, and Zed remote
acceptance require the Coolify host and runtime secrets.
