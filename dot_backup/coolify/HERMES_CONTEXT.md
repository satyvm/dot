# Hermes Remote Development Context

## Purpose

This document is the operating context for the Hermes remote development environment. Use it when answering questions, modifying projects, running development tools, or diagnosing the platform.

Do not expose credentials, tokens, private keys, authentication files, or environment-variable values. Do not weaken sandboxing to work around missing access. Ask for an exact narrow grant instead.

## Platform Summary

This is a persistent remote development environment deployed through Coolify as a Docker Compose application. It combines:

- Hermes WebUI and Hermes Agent
- An SSH-accessible Ubuntu development container
- CLIProxyAPI for centralized model routing and provider authentication
- `ax` as the policy gateway for coding agents
- Nono as the filesystem and network sandbox
- Herdr for agent session orchestration and resume support
- A private Gitea sidecar exposed through the `gitea-ai` CLI
- Chezmoi-managed shell, tools, agent configuration, and dotfiles

The primary development workspace is:

```text
/home/ubuntu/dev
```

Always create, clone, and modify project repositories under this directory.

## Services and Network Architecture

The Compose stack has three services:

### `hermes-dev`

Runs:

- Hermes WebUI on container port `8787`
- SSH on container port `22`, published only on host loopback
- The Ubuntu development shell and coding agents

Important runtime paths:

```text
HOME=/home/ubuntu
HERMES_HOME=/home/ubuntu/.hermes
HERMES_WEBUI_STATE_DIR=/home/ubuntu/.hermes/webui
HERMES_WEBUI_DEFAULT_WORKSPACE=/home/ubuntu/dev
HERMES_WEBUI_AGENT_DIR=/opt/hermes-agent
HERMES_WEBUI_PYTHON=/opt/hermes-venv/bin/python
```

Pinned Hermes versions:

```text
Hermes WebUI: 0.51.92
Hermes Agent: 0.18.2
```

### `cliproxyapi`

Internal model proxy available to containers at:

```text
http://cliproxyapi:8317
http://cliproxyapi:8317/v1
```

It is not publicly exposed. Provider credentials and proxy keys must never be printed or copied into project files.

### `tea-sidecar`

Provides controlled access to the Gitea API over this Unix socket:

```text
/run/tea/tea.sock
```

Use the `gitea-ai` CLI rather than reading its token or contacting its credential storage directly.

## Persistence Model

Persistent data is split deliberately:

| Data | Path | Storage | Survives recreation? |
|---|---|---|---|
| Project repositories | `/home/ubuntu/dev` | Host bind mount | Yes |
| User home and dotfiles | `/home/ubuntu` | Docker volume `remote-home` | Yes |
| Hermes config and state | `/home/ubuntu/.hermes` | Docker volume `hermes-state` | Yes |
| Provider OAuth state | CLIProxyAPI auth directory | Docker volume `cliproxy-auth` | Yes |
| SSH host identity | `/etc/ssh/host-keys` | Docker volume | Yes |
| Hermes WebUI application code | `/apptoo` | Container image | No |
| Installed image dependencies | Image filesystem | Container image | No |

Important consequence: changes made directly to Hermes WebUI code under `/apptoo` are temporary and disappear when the container is recreated. Permanent WebUI changes must be committed to the image source or Docker build configuration and deployed through a rebuilt image.

Hermes settings, sessions, and files under `/home/ubuntu/.hermes` persist, but generated configuration may also be managed by Chezmoi. Make durable configuration changes in the dotfiles repository when appropriate.

## Hermes Configuration

Hermes configuration is stored at:

```text
/home/ubuntu/.hermes/config.yaml
/home/ubuntu/.hermes/.env
```

The managed provider is CLIProxyAPI:

```yaml
model:
  default: balanced
  provider: custom:cliproxyapi
  base_url: http://cliproxyapi:8317/v1
  api_mode: chat_completions
```

The custom provider uses `OPENAI_API_KEY` from the environment. Never place the actual key in documentation, chat responses, source code, commits, or logs.

Hermes model aliases include the four canonical roles:

- `frontier` — strongest model for difficult reasoning and complex implementation
- `balanced` — normal default for general work
- `fast` — faster model for routine tasks
- `light` — lightweight model for inexpensive background work

Hermes MCP definitions and provider/model settings share the same mutable YAML file. Chezmoi updates merge managed MCP definitions into the existing file rather than replacing unrelated Hermes settings.

## Coding Agents and `ax`

Available coding agents:

```text
claude
pi
opencode
crush
```

Their native command names are managed shims that delegate to `ax`. Normal usage:

```bash
claude
pi
opencode
crush
```

Equivalent explicit usage:

```bash
ax claude
ax pi
ax opencode
ax crush
```

Useful `ax` commands:

```bash
ax doctor
ax models show
ax models live
ax models validate
ax auth setup
ax clear --dry-run
```

Override the canonical model role for one launch:

```bash
AX_MODEL=frontier claude
AX_MODEL=fast opencode
```

Do not bypass `ax`. Do not invoke real agent binaries by manipulating `PATH`. Normal agent launches must run through Nono.

`--direct` is an explicit sandbox escape reserved only for a user-requested diagnostic. Never use or recommend it as a routine workaround.

## Nono Sandbox Policy

Nono is mandatory for coding-agent launches. The sandbox grants:

- Read/write access to the current project workspace
- Narrow access to each agent's required state files
- Read access to managed skills and universal context
- Developer network access through the configured policy
- Access to CLIProxyAPI on port `8317`
- Dynamically granted Herdr and Gitea sidecar sockets when present

The sandbox denies sensitive locations, including:

- `~/.ssh`
- `~/.gnupg`
- `~/.aws`
- Cargo credentials
- GitHub CLI authentication
- CLIProxyAPI credentials
- Shell history
- Browser profiles and keychains

Linux Landlock is allow-list based and cannot enforce a child deny beneath a broadly allowed parent. Therefore:

- Never grant all of `/home/ubuntu` to an agent.
- Run agents from `/home/ubuntu/dev` or a project beneath it.
- Add exact Linux-only paths when a legitimate runtime file is missing.
- Do not solve access prompts by granting broad parent directories.

If Nono asks for a system path, record the exact path and requested access. A narrow shared or agent-specific profile grant may be added after review. For example, Linux agents have a narrow read grant for:

```text
/usr/share/locale/locale.alias
```

## Working Directory Rules

Preferred workflow:

```bash
cd /home/ubuntu/dev/project
ax doctor
opencode
```

When an agent is launched from `/home/ubuntu` on Linux, `ax` moves the launch workspace to `/home/ubuntu/dev` before applying `--allow-cwd`. This prevents the entire home directory from conflicting with credential denies.

Open an individual project directory whenever possible rather than giving an agent the whole `/home/ubuntu/dev` tree.

## Chezmoi and Configuration Ownership

The environment is managed from the dotfiles source checkout:

```text
/home/ubuntu/.local/share/chezmoi
```

Important commands:

```bash
chezmoi diff
chezmoi apply
chezmoi update
```

On container startup, the entrypoint refreshes the existing dotfiles checkout with a fast-forward-only pull and applies it. This keeps persistent volumes aligned with the deployed dotfiles source.

Configuration ownership rules:

- Project code changes: edit and commit inside the project repository.
- Shell, agent, Nono, and user configuration: change the Chezmoi source repository.
- System packages, pinned tools, Hermes runtime, and WebUI code: change Dockerfile or Compose source and redeploy.
- Runtime secrets: manage through Coolify/environment configuration, never source control.

Chezmoi source filenames use attribute prefixes such as `dot_`, `private_`, `executable_`, and `run_`. They are not always literal deployed filenames.

## Herdr

Herdr integrations are installed for Claude, Pi, and OpenCode. Herdr can orchestrate and resume agent sessions.

When `HERDR_SOCKET_PATH` is set, `ax` dynamically grants that exact Unix socket to Nono. Preserve Herdr resume arguments unchanged when launching an agent.

Do not grant a broad socket directory when one exact socket path is available.

## Gitea Workflow

The remote environment uses a self-hosted Gitea instance and an `ai` user. Git SSH transport uses a dedicated key generated inside the persistent remote home.

Use normal Git commands for repository work. Use `gitea-ai` for controlled forge API actions:

```bash
gitea-ai ping
gitea-ai list-repos
gitea-ai create-repo <name> [description]
gitea-ai create-issue <repo> <title> [body]
gitea-ai create-pr <repo> <title> <head> [base] [body]
```

Never attempt to read the Gitea API token. The sidecar owns it and exposes only approved operations over the Unix socket.

Never commit or push unless the user explicitly requests it.

## SSH and Remote Editing

The container is normally reached through the local SSH alias:

```bash
ssh hermes-dev
```

The SSH connection uses ProxyJump through the Coolify host, key-only authentication, no agent forwarding, and a loopback-only published container SSH port.

Zed can open the persistent remote workspace through:

```text
ssh://hermes-dev/home/ubuntu/dev
```

Remote editor terminals, tasks, formatters, and language servers execute inside `hermes-dev`.

Available language tooling includes:

- `vtsls` for JavaScript and TypeScript
- Pyright for Python
- `gopls` for Go
- `rust-analyzer` for Rust

## Safe Development Workflow

Before changing code:

1. Identify the project under `/home/ubuntu/dev`.
2. Read its nearest `AGENTS.md` if present.
3. Inspect existing conventions and dependencies before editing.
4. Keep credentials and agent state out of project files.
5. Make the smallest durable change at the correct ownership layer.

After changing code:

1. Run the project's tests.
2. Run its lint and typecheck commands when available.
3. Inspect the diff.
4. Do not commit or push unless explicitly asked.

For the dotfiles/platform repository, run:

```bash
bash dot_local/bin/tests/test_ax.sh
bash dot_backup/coolify/tests/test_stack.sh
git diff --check
```

Also validate Nono profiles after policy changes:

```bash
nono profile validate --strict ~/.config/nono/profiles/default-agent.json
nono profile validate --strict ~/.config/nono/profiles/default-claude.json
nono profile validate --strict ~/.config/nono/profiles/default-pi.json
nono profile validate --strict ~/.config/nono/profiles/default-opencode.json
nono profile validate --strict ~/.config/nono/profiles/default-crush.json
```

## Deployment and Update Rules

A Coolify rebuild/redeploy is required for changes to:

- Dockerfile packages
- Pinned application versions
- Hermes WebUI source or image-layer code
- Compose service definitions
- Entrypoint or Supervisor configuration copied into the image

A Chezmoi update/apply is sufficient for changes to:

- Shell configuration
- `ax`
- Nono profiles
- Agent configuration
- Managed MCP configuration
- User-level Git/editor configuration

Common remote checks:

```bash
ax doctor
gitea-ai ping
curl --fail --silent http://127.0.0.1:8787/health
```

After deployment, verify all four agents:

```bash
claude
pi
opencode
crush
```

## Troubleshooting Principles

### Agent fails with Landlock deny-overlap

Cause: a broad allowed parent contains denied credential paths.

Action:

- Confirm the launch directory is under `/home/ubuntu/dev`.
- Remove or platform-limit the broad parent grant.
- Add only exact required Linux paths.
- Never remove credential denies merely to start an agent.

### Agent asks for additional filesystem access

Action:

- Capture the exact path and access mode.
- Determine whether it is a non-secret runtime dependency.
- Add the narrowest platform-specific grant.
- Add a regression test.
- Validate all profiles and rerun agent tests.

### Hermes UI modification disappears

Cause: `/apptoo` belongs to the container image.

Action: implement the change in image source or the Docker build, then rebuild and redeploy. Do not rely on live edits inside the container.

### Dotfiles appear stale

Run:

```bash
chezmoi update
```

If diagnosing startup synchronization, inspect whether the persistent source checkout successfully completed `git pull --ff-only` and `chezmoi apply`.

### Model or provider failure

Run:

```bash
ax doctor
ax models live
ax models validate
```

Provider authentication is managed through CLIProxyAPI. Use `ax auth setup` when interactive provider authentication is required. Never print proxy credentials.

### Gitea API operation fails

Run:

```bash
gitea-ai ping
```

Then verify the sidecar socket exists and the service is healthy. Do not bypass the sidecar by extracting its token.

## Behavioral Rules for Hermes

When assisting in this environment:

- Treat `/home/ubuntu/dev` as the only normal project workspace.
- Distinguish persistent configuration from image-layer files before editing.
- Prefer durable source changes over live container modifications.
- Use `ax`-managed agent commands and preserve the Nono boundary.
- Never expose secrets or inspect denied credential paths.
- Never broaden Linux home access to solve Landlock conflicts.
- Use the exact Gitea sidecar commands for forge actions.
- Never commit, push, create a repository, issue, or pull request unless explicitly requested.
- Run relevant tests, lint, and typechecks after modifications.
- When uncertain whether a change belongs in project code, Chezmoi, or the Docker image, ask before modifying it.
