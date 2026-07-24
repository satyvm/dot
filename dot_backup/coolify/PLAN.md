# Coolify Hermes Remote Development Platform

## Goal

Build two independent development environments that use the same dotfiles and
agent workflow:

- **MacBook:** the existing local `ax` + Nono + Herdr + Homebrew CLIProxyAPI
  setup, local repositories, local LSPs, and local MCP servers.
- **Coolify server:** a persistent remote development environment with Hermes,
  Hermes WebUI, a separate Docker CLIProxyAPI, the coding agents, `ax`, Nono,
  Herdr, the same MCP/LSP catalog, project repositories, and the chezmoi source
  repository.

Either environment must remain usable when the other one is offline. They share
configuration through Git, not runtime state or credentials.

The MacBook and server use the same versioned MCP and LSP catalog. They do not
share live processes, caches, credentials, or absolute paths. Each environment
runs its own MCP/LSP instances beside its own checkout of the code.

## Correct mental model

Coolify manages the lifecycle of a Docker Compose application. The Compose file
is the deployment source of truth. Coolify:

1. checks out the deployment revision,
2. builds or pulls the declared images,
3. creates a private network for the application,
4. creates resource-scoped persistent volumes,
5. starts the services, and
6. attaches its HTTP proxy to services that have domains.

The Git checkout used to build the application is not the persistent development
workspace. A redeploy may replace application containers and build directories.
The remote home directory, chezmoi source directory, Hermes state, CLIProxyAPI
state, and code workspaces therefore need explicit persistent storage. The
server account is `ubuntu`, its home is `/home/ubuntu`, and
`/home/ubuntu/dev` is the authoritative code directory. That development
directory is bind mounted at the identical path inside the development
container.

Use a **Git-based Docker Compose Application** in Coolify rather than a pasted
one-click/User-Defined Service. This keeps the Dockerfile and Compose definition
versioned in this repository and allows deployments from commits. The source
repository can still be cloned separately into the persistent remote home so it
can be used normally with `chezmoi update`, edited, committed, and pushed.

## Target architecture

```text
MacBook
├── ax + Nono + Herdr
├── local CLIProxyAPI (127.0.0.1:8317)
├── ~/dev + local LSP processes
└── local MCP processes (filesystem, docs, GitHub, browser, productivity)

Coolify Compose application
├── hermes-dev
│   ├── Hermes gateway
│   ├── Hermes WebUI or its in-process agent runtime
│   ├── ax + Nono + Herdr
│   ├── Claude / Pi / OpenCode / Crush
│   ├── SSH or Coolify terminal entry point
│   ├── the same MCP/LSP catalog and development toolchains
│   ├── persistent /home/ubuntu
│   │   └── ~/.local/share/chezmoi (independent Git clone)
│   └── /home/ubuntu/dev -> bind-mounted server-host /home/ubuntu/dev
└── cliproxyapi
    ├── private API on cliproxyapi:8317
    ├── independent server-side provider authentication
    └── persistent config and auth state

Public HTTP route
└── hermes.example.com -> hermes-dev:8787
```

Only the WebUI is routed publicly through Coolify. CLIProxyAPI and the Hermes
gateway API stay on the private Compose network unless a concrete external
client requires them.

### One execution environment, not two accidental ones

The current sample separates `hermes-agent` and `hermes-webui`. That does not
give a single predictable coding environment. The Hermes WebUI project documents
that, in its two-container mode, tools started from the WebUI run in the WebUI
container rather than the agent container.

The production design must therefore use one of these approaches:

1. **Preferred:** build a custom `hermes-dev` image from the WebUI's
   single-container setup and add the remote development toolchain, `ax`, Nono,
   Herdr, and remote access. The browser UI and its tool calls then use the same
   filesystem and binaries that an interactive shell uses.
2. **Fallback:** create a separate persistent `devbox` service and configure
   every Hermes entry point to use that service through Hermes's SSH terminal
   backend. Both gateway and WebUI must target the same devbox and its
   bind-mounted `/home/ubuntu/dev`. This is cleaner operationally, but it is not
   literally a single container.

Do not proceed with the current two-container layout until a smoke test proves
where WebUI-initiated terminal and code tools execute. The acceptance test is
that a file created from the WebUI is immediately visible in the interactive
Herdr shell and vice versa.

Running multiple independent Hermes processes against the same writable state
directory is not an acceptable substitute. If the gateway and WebUI require
separate processes, use a supported single-container launcher/supervisor and
verify state locking, or use separate state directories with one shared
workspace.

## Remote access

Coolify's proxy handles HTTP/HTTPS. It is not an SSH proxy.

Use the access methods in this order:

1. **Initial administration:** Coolify's authenticated container terminal.
2. **Emergency shell access:** SSH to the Coolify host over
   Tailscale/WireGuard and enter the container with a stable helper command such
   as `docker exec -it <resolved-container> zsh`.
3. **Normal development and editor access:** connect directly to the
   `hermes-dev` SSH daemon through the Coolify host with OpenSSH `ProxyJump`.
   Publish the container's port 22 only on the Coolify host's loopback address.

Avoid a hard-coded `container_name`; Coolify scopes and may transform Compose
resources. Any host-side helper should resolve the container from Coolify's
resource/service labels rather than assume a global name.

Interactive Herdr and tmux state can disappear when the container is replaced.
Herdr configuration, agent sessions, and workspaces must persist, but a redeploy
should still be treated as a process restart.

### Container SSH implementation

The `hermes-dev` image must include OpenSSH server plus the basic utilities
required by remote editors: a shell, `curl`, `tar`, `gzip`, Git, and CA
certificates. Create an unprivileged `ubuntu` user with:

- home directory `/home/ubuntu`;
- a numeric UID/GID matching the server host's `ubuntu` account;
- key-only SSH authentication;
- no root login;
- no password or keyboard-interactive authentication;
- no SSH agent forwarding; and
- TCP forwarding enabled for editor development ports.

Use a process supervisor already required by the combined Hermes/WebUI image to
run `sshd` beside the application processes. Do not start a detached SSH daemon
from an entrypoint and then lose its failures.

Persist SSH host keys separately so redeploying the container does not change
the fingerprint stored on developer machines. Install the Mac's dedicated
public key into `/home/ubuntu/.ssh/authorized_keys` at startup with directory
mode `0700` and file mode `0600`. The private key never leaves the Mac.

The Compose service includes:

```yaml
services:
  hermes-dev:
    ports:
      - "127.0.0.1:${DEV_SSH_PORT:-2222}:22"
    volumes:
      - type: bind
        source: ${SERVER_DEV_PATH:?set /home/ubuntu/dev}
        target: /home/ubuntu/dev
      - remote-home:/home/ubuntu
      - ssh-host-keys:/etc/ssh/host-keys
    environment:
      DEV_SSH_PUBLIC_KEY: ${DEV_SSH_PUBLIC_KEY:?}

volumes:
  remote-home:
  ssh-host-keys:
```

Set these in Coolify:

```text
SERVER_DEV_PATH=/home/ubuntu/dev
DEV_SSH_PORT=2222
DEV_SSH_PUBLIC_KEY=ssh-ed25519 AAAA... hermes-dev
```

Port `2222` is reachable only from the Coolify host. Do not assign it a Coolify
domain and do not publish it on `0.0.0.0`. The WebUI remains the only
internet-routed service.

### Mac SSH configuration

Create a dedicated container key:

```bash
ssh-keygen -t ed25519 \
  -f ~/.ssh/hermes_dev_ed25519 \
  -C "hermes-dev"
```

Use separate keys for the Coolify host and development container. Add aliases to
the Mac's `~/.ssh/config`:

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

The Coolify host's SSH daemon must permit TCP forwarding because `ProxyJump`
uses it. Prefer a Tailscale/WireGuard address for the `coolify` alias. Test the
whole path before configuring an editor:

```bash
ssh hermes-dev
whoami
echo "$HOME"
ls /home/ubuntu/dev
command -v zsh
command -v herdr
command -v ax
```

Verify the new container host-key fingerprint out of band before accepting it.

### Zed remote development

Zed should connect to the `hermes-dev` SSH alias, not merely the Coolify host.
This makes the SSH destination the same environment that owns Hermes, Herdr,
`ax`, the MCP processes, language servers, and `/home/ubuntu/dev`.

In Zed's Remote Projects dialog, add:

```text
ssh hermes-dev
```

Then open one repository such as:

```text
/home/ubuntu/dev/my-project
```

Open individual repositories rather than all of `/home/ubuntu` or a very large
development tree. Zed can also store the connection in its local settings:

```json
{
  "ssh_connections": [
    {
      "host": "hermes-dev",
      "nickname": "Coolify Hermes",
      "upload_binary_over_ssh": true,
      "projects": [
        {
          "paths": ["/home/ubuntu/dev/my-project"]
        }
      ]
    }
  ]
}
```

With `upload_binary_over_ssh`, Zed downloads the matching headless server on the
Mac and uploads it through SSH. Persisting `/home/ubuntu` also preserves
`~/.zed_server` between container replacements.

Configuration ownership is:

- Mac Zed settings: UI, fonts, themes, local model credentials, and the SSH
  connection definition;
- remote `/home/ubuntu/.config/zed/settings.json`: remote executable paths,
  proxy settings, MCP commands that must run remotely, and machine-specific
  language-server settings;
- project `.zed/settings.json` and `.editorconfig`: shared formatter, LSP,
  task, and project behavior.

Zed remote terminals, tasks, and LSP processes must run inside `hermes-dev`.
The shared chezmoi MCP/LSP catalog should render the remote Zed settings as well
as the native configs for Hermes and terminal agents. Validate Zed-managed MCPs
separately from native CLI/TUI MCP configuration because the two agent paths
have different configuration boundaries.

## Persistent storage

Use separate volumes or bind mounts with one clear owner:

| Storage | Container path | Purpose |
|---|---|---|
| Remote home | `/home/ubuntu` | chezmoi target files, Herdr state, agent state, shell state |
| Hermes state | the image's supported Hermes data path | config, memory, sessions, skills, cron, credentials |
| Development tree | `/home/ubuntu/dev` | bind mount of the server host's `/home/ubuntu/dev` |
| CLIProxyAPI config | a config directory, not a volume mounted as one file | server-only configuration |
| CLIProxyAPI auth | the image's supported auth directory | provider OAuth/account files |
| WebUI state | its documented state directory | WebUI-only sessions and preferences |

The official Hermes container uses `/opt/data` for its persistent data. Do not
replace that convention with `/home/hermes/.hermes` unless the exact pinned
image documents the alternative.

Do not use this sample mapping:

```yaml
- cliproxy-config:/CLIProxyAPI/config.yaml
```

A named Docker volume is a directory, while the target looks like a file. Mount
a configuration directory, use a Compose `config`, or use a Coolify-managed
file mount.

Do not share an entire writable Hermes home between unrelated containers. Share
only the exact directory required by an upstream-supported multi-container
layout. Keep `/home/ubuntu/dev` as the deliberate cross-process boundary.

### Host `/home/ubuntu/dev` bind mount

Do not put `~/dev` or `${HOME}/dev` in the Coolify Compose file. Tilde and home
expansion depend on the process that launches Compose and are not stable Coolify
contracts. Set the required Coolify variable to the explicit server path:

```yaml
services:
  hermes-dev:
    volumes:
      - type: bind
        source: ${SERVER_DEV_PATH:?set an absolute host path}
        target: /home/ubuntu/dev

```

Set `SERVER_DEV_PATH=/home/ubuntu/dev` in Coolify. Create that directory on the
destination server, make its numeric UID/GID match the container's unprivileged
`ubuntu` user, and back it up separately. Use `/home/ubuntu/dev` in shell,
editor, Hermes, MCP, and LSP configuration.

The bind mount means project files survive container replacement and are also
available from the server host. It does not replace a backup, and it must never
be mounted into CLIProxyAPI.

## Required chezmoi changes

Cloning the repository into Linux is not enough today. The current templates
explicitly restrict the AI agent platform to macOS `dev`:

- `.chezmoiignore.tmpl` omits `ax`, agent shims, Nono profiles, agent configs,
  CLIProxyAPI config, and the setup script on Linux.
- `run_onchange_after_setup-ai-agent-platform.sh.tmpl` only runs on macOS and
  assumes Homebrew services.
- `ax auth setup`, `ax doctor`, and `ax ensure_proxy` contain macOS/Homebrew
  assumptions.
- the canonical model registry hard-codes
  `http://127.0.0.1:8317`.
- the base Nono profile describes a macOS developer boundary.

Add a distinct `remote-dev` profile rather than overloading the current hardened
`server` profile. The profile should:

1. deploy the same agent configs, shims, universal context, and model aliases as
   macOS `dev`;
2. render the proxy URL as `http://cliproxyapi:8317` in the server container and
   `http://127.0.0.1:8317` on the Mac;
3. install or verify pinned Linux builds of Herdr, Nono, Claude, Pi, OpenCode,
   and Crush during the image build;
4. install Herdr integrations for the Linux agent binaries;
5. use Linux-specific Nono runtime paths and permit only the required connection
   to `cliproxyapi:8317`;
6. treat CLIProxyAPI as externally managed by Compose—`ax` must never attempt
   `brew services` on the server;
7. read a mounted server client key but not require the proxy's provider OAuth
   files to exist in the development container;
8. make `ax doctor` report environment-specific recovery instructions; and
9. keep all machine credentials out of Git and out of chezmoi templates.

Image construction installs binaries. Chezmoi installs and updates user
configuration. Keeping those responsibilities separate makes deployments
repeatable and prevents every container start from downloading mutable tools.

## Shared MCP and LSP configuration

Add one canonical catalog to the chezmoi data, for example:

```text
.chezmoidata/ai-tools.yaml
├── mcp.servers
├── mcp.clientBindings
├── lsp.servers
├── lsp.filetypes
└── versions
```

Chezmoi templates render that catalog into the native configuration used by
Hermes, Claude, Pi, OpenCode, Crush, Neovim, and any other supported editor.
Do not maintain unrelated hand-written MCP lists in every client.

Each MCP entry should declare:

- command or remote transport;
- pinned package/image version;
- enabled environments (`mac-dev`, `remote-dev`, or both);
- required credential names;
- filesystem roots it may access;
- network policy; and
- which clients receive it.

The default target is parity: an MCP enabled on the Mac is also enabled on the
server. Environment overrides are allowed only where the capability is
platform-specific. Path variables map the same logical root to the appropriate
location:

```yaml
paths:
  devRoot:
    mac-dev: /Users/s/dev
    remote-dev: /home/ubuntu/dev
```

Filesystem MCPs receive only `devRoot`, not the whole home directory. GitHub,
documentation, browser, and productivity MCPs use independent credentials in
each environment even though their server definitions are the same. Prefer
local stdio MCP processes inside `hermes-dev`; use a sidecar only when a server
is naturally long-running, requires a browser, or is shared by several clients.
Sidecars remain private on the Compose network and are never exposed merely for
convenience.

For LSPs, keep one version manifest and install the same server versions in the
Mac and remote image where the platform supports them. Neovim/editor
configuration is shared, while executable paths and installation mechanisms may
differ. LSP processes always run in the environment that owns the files:

- Mac LSPs index `/Users/s/dev`;
- remote LSPs index `/home/ubuntu/dev`.

Add validation commands that compare the rendered MCP server names and pinned
LSP versions on both profiles. Secrets, OAuth tokens, caches, indexes, and MCP
process state are deliberately not synchronized through chezmoi.

## Coolify Compose rules

Replace the sample Compose file only after the image and profile design above
are settled.

The final Compose file should:

- omit the obsolete top-level `version`;
- omit fixed `container_name` values;
- build `hermes-dev` from a pinned base image and a repository Dockerfile;
- pin every external image by immutable version or digest;
- use `${VARIABLE:?}` for required Coolify environment variables;
- use `SERVICE_URL_..._8787` or assign `https://hermes.example.com:8787` to the
  WebUI service in Coolify;
- avoid host `ports` for HTTP services that Coolify proxies;
- expose no domain and no host port for `cliproxyapi`;
- connect internally with `http://cliproxyapi:8317`;
- enable the Hermes API only when the chosen WebUI topology requires it, bind it
  to the Compose network, and protect it with an API key;
- use health checks that test real readiness endpoints rather than only checking
  whether a binary or directory exists;
- express CPU and memory limits in a form supported by the selected Coolify
  destination;
- run application processes as an unprivileged UID/GID; and
- avoid mounting `/var/run/docker.sock`.

The current localhost mappings for CLIProxyAPI OAuth callback ports do not make
those ports reachable through Coolify's proxy. Do not leave provider callback
ports published permanently. For initial server-side CLIProxyAPI authentication,
temporarily reach the required callback through an authenticated SSH tunnel or a
short-lived protected route, finish the provider login, verify that the auth
files landed in the server volume, and remove the temporary exposure.

## Secrets and identity

The Mac and server have independent credentials:

- separate CLIProxyAPI client keys;
- separate CLIProxyAPI management keys;
- separate provider OAuth/account files;
- separate SSH host/user keys;
- separate GitHub credentials or deploy keys; and
- separate Hermes/WebUI/API secrets.

Enter required secrets as Coolify runtime environment variables or mount them
from server-only files. Do not pass secrets as Docker build arguments. Do not
copy the Mac's CLIProxyAPI auth directory to the server.

Use a dedicated GitHub identity or fine-grained token on the remote environment
with only the repository permissions it needs. Keep commit signing optional on
the server until a server-specific signing key is configured; the Mac SSH
signing key must not be copied into the container.

## Daily workflows

### Local development

1. Open a local repository under `~/dev`.
2. Start an agent through `ax` and Herdr.
3. Use the local instances of the shared MCP/LSP catalog.
4. Test, commit, and push normally.

No request depends on Coolify.

### Remote development

1. Enter `hermes-dev` through the private shell path or open the WebUI.
2. Open a repository under `/home/ubuntu/dev`, backed by the identical server
   host path.
3. Start or resume an agent through the same `ax` and Herdr commands.
4. `ax` connects to the private server CLIProxyAPI service.
5. The server instances of the same MCP/LSP catalog operate on
   `/home/ubuntu/dev`.
6. Commit and push from the server's independent Git identity.

No request depends on the Mac or its MCP processes. The server runs equivalent
MCP processes with its own credentials and access to `/home/ubuntu/dev`.

### Dotfiles synchronization

The two chezmoi source repositories are normal independent Git clones:

1. change and test dotfiles on either environment;
2. commit and push the change;
3. run `chezmoi update` on the other environment; and
4. run `ax doctor` after agent-platform changes.

Never share one live Git working tree between the Mac and server through a
network filesystem.

## Updates, backups, and recovery

There are two independent update tracks:

- **Application image:** a commit changes the Dockerfile or Compose file,
  Coolify builds the new revision, health checks it, and replaces the container.
- **User configuration and projects:** `chezmoi update` and normal Git commands
  update the persistent remote home and the bind-mounted
  `/home/ubuntu/dev`.

Before an application update:

1. back up Hermes, WebUI, `/home/ubuntu`, `/home/ubuntu/dev`, and CLIProxyAPI
   state;
2. record the currently deployed image digests and Git revision;
3. build and deploy the new revision;
4. verify WebUI login, Hermes gateway health, proxy model listing, an `ax`
   launch, a Herdr resume, Git access, and one representative LSP; and
5. retain the previous image locally until the new revision is accepted.

Coolify preserving a named volume is not a backup. Send encrypted backups to
storage outside the Coolify host and test a restore into a disposable
application before relying on it.

## Implementation phases

### Phase 0 — Prove the execution topology

- Deploy the pinned upstream Hermes/WebUI examples without real credentials.
- Determine exactly where WebUI terminal and code tools execute.
- Choose the custom single-container `hermes-dev` design unless that test proves
  it cannot support the required gateway workflow.
- Prove bidirectional file visibility between WebUI actions and an interactive
  shell.

### Phase 1 — Make the dotfiles portable

- Add the `remote-dev` profile.
- Render local and Compose-network proxy URLs correctly.
- make `ax` service management and diagnostics platform-aware;
- add Linux Nono profiles and Herdr integration setup;
- add the canonical MCP/LSP catalog and environment-specific path rendering;
- add deterministic tests for Mac local mode and Linux remote mode; and
- validate with `chezmoi execute-template`, `chezmoi apply --dry-run`, and
  `bash dot_local/bin/tests/test_ax.sh`.

### Phase 2 — Build the remote development image

- Add a Dockerfile with pinned system and agent dependencies.
- Create an unprivileged `ubuntu` user whose UID/GID match the server account.
- bootstrap the persistent home and clone chezmoi only when absent;
- bind-mount the server's `/home/ubuntu/dev` at the identical container path;
- persist all remaining state directories;
- install the pinned remote MCP and LSP dependencies from the shared catalog;
- install and harden `sshd`, persist its host keys, and supervise it with the
  application processes;
- verify the container `ubuntu` UID/GID against the server host; and
- add a health check plus a stable shell-entry procedure.

### Phase 3 — Replace the sample Compose file

- Use the Git-based Coolify Docker Compose application flow.
- Correct volume and config mounts.
- keep CLIProxyAPI private;
- expose only the password-protected WebUI through a Coolify domain;
- add required secrets, health checks, resource limits, and update pins; and
- document the one-time provider login flow.

### Phase 4 — Validate parity

- Run `ax doctor` in both environments.
- Launch all four agents through Nono and Herdr.
- verify the same model aliases through different CLIProxyAPI instances;
- clone, edit, test, commit, and push a disposable repository remotely;
- compare the rendered MCP list and pinned LSP versions on both machines;
- exercise filesystem, documentation, GitHub, and browser MCPs remotely;
- verify representative remote LSPs; and
- connect Zed through the `hermes-dev` ProxyJump alias, open a repository, and
  verify its terminal, task runner, formatter, and LSP execute in the container;
- stop the Mac and confirm the server workflow still works, then stop the
  Coolify stack and confirm the Mac workflow still works.

### Phase 5 — Operationalize

- Add encrypted off-host backups and a restore drill.
- add deployment and rollback runbooks;
- add log retention, disk alerts, and health monitoring;
- document credential rotation; and
- schedule periodic image and dependency updates instead of using `latest`.

## Acceptance criteria

- MacBook and Coolify CLIProxyAPI installations are independently configured,
  authenticated, updated, and recoverable.
- The same canonical MCP catalog renders on the Mac and server.
- MCP processes and credentials remain independent per environment.
- Filesystem MCPs are restricted to `/Users/s/dev` on the Mac and
  `/home/ubuntu/dev` remotely.
- Remote coding works without the MacBook online.
- Local coding works without Coolify online.
- The remote chezmoi clone and bind-mounted `/home/ubuntu/dev` survive
  container replacement.
- WebUI-originated tools and interactive Herdr sessions operate on the same
  remote workspace.
- `ax`, Nono, Herdr, and all four coding agents pass their remote Linux checks.
- Matching pinned LSPs work against Mac and server-side files.
- Zed connects to `hermes-dev` through the Coolify SSH jump host and its
  terminals, tasks, formatters, and LSPs execute inside that container.
- Only the WebUI has a public HTTP route.
- CLIProxyAPI, provider callback ports, and the Hermes API are not unintentionally
  public.
- SSH is private, key-only, and independent of the Coolify HTTP proxy.
- No Docker socket, Mac credentials, or broad host filesystem is mounted into
  the development container.
- A tested backup can restore all persistent state.
- A failed deployment can be rolled back without losing the remote home or
  `/home/ubuntu/dev`.
