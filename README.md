# satyvm / dot

Personal dotfiles managed with [Chezmoi](https://www.chezmoi.io/) for:

- macOS on Apple Silicon (`arm64`) and Intel (`amd64`);
- Ubuntu and Debian on `arm64` and `amd64`;
- interactive laptop, workstation, server, and container setups.

## Install or update from anywhere

Run this one Bash command from any directory:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

On a new machine it installs the bootstrap dependencies, Homebrew/Linuxbrew,
Chezmoi, and these dotfiles, then asks the initialization questions documented
below and applies the selected setup.

On a machine where this repository already exists at
`~/.local/share/chezmoi`, the same command runs `chezmoi update`: it pulls the
latest source and applies it without asking the initialization questions again.

On Linux, run it as a regular user with `sudo` access, not as `root`, because
Linuxbrew refuses to run as root. The bootstrap stops on unsupported platforms
or real installation errors instead of silently continuing.

## What `chezmoi init` asks

The first run uses the following question flow.

### 1. Machine preset

Choose the closest complete setup:

| Choice | Intended use | CLI | Developer | AI | AI mode | macOS GUI | OS customization | Linux hardening | SSH signing |
|---|---|---:|---:|---:|---|---|---:|---:|---:|
| `laptop` | Portable personal development machine | Yes | Yes | Yes | Local | Minimum | Yes | No | Yes |
| `workstation` | Full development machine | Yes | Yes | Yes | Local | All | Yes | No | Yes |
| `server` | Headless host | Yes | No | No | Local | None | No | Yes | Yes |
| `container` | Image-provisioned remote development environment | Yes | Yes | Yes | Remote | None | No | No | No |

The default is `workstation` on macOS and `server` on Linux.

Platform rules still apply after choosing a preset:

- GUI applications and OS customization are macOS-only.
- UFW/fail2ban hardening is Linux-only and is always disabled in containers.
- The `container` preset manages configuration but skips host package
  installers; its image is expected to provide the required programs.

### 2. Customize preset features

Default: `No`.

- Answer `No` to use the preset exactly as shown in the table.
- Answer `Yes` to replace the preset's feature settings with the answers to the
  remaining feature questions.

This is a full override, not a list of small changes. If you answer `Yes`, the
following prompt defaults are the custom setup defaults, even if the selected
preset normally enables more.

### 3. Custom feature questions

These appear only after answering `Yes` to **Customize preset features**.

| Question | Appears when | Default | What it controls |
|---|---|---|---|
| **Install core CLI setup** | Always | Yes | Installs the shell/CLI package set and manages Zsh, Neovim, tmux, Starship, aliases, functions, and shell environment. |
| **Install developer toolchain** | Core CLI is Yes | No | Installs language runtimes, LSPs, Docker tooling, cloud/Kubernetes tools, database tools, formatters, and build dependencies. It is forced off when core CLI is off. |
| **Install AI setup** | Always | No | Installs and configures Claude Code, PI, OpenCode, Crush, Herdr, Nono, the `ax` gateway, shared model/MCP configuration, and agent skills. |
| **AI deployment mode** | AI setup is Yes | `local` | `local` installs and manages CLIProxyAPI on this host. `remote` points agents at a remote/container proxy and does not manage a local proxy service. |
| **GUI tools** | macOS only | `none` | `none` installs no GUI tier, `minimum` installs the focused app set, and `all` installs both minimum and full GUI sets. |
| **Apply OS customization** | Always | No | Applies the managed macOS Dock, Finder, keyboard, trackpad, Spotlight, and screenshot defaults. It currently resolves to off on Linux. |
| **Configure Linux firewall and fail2ban** | Linux only | No | Installs/configures UFW and fail2ban. UFW denies incoming traffic except SSH, HTTP, and HTTPS. The active/configured SSH port is preserved. |
| **Manage SSH signing when the key exists** | Always | No | Manages Git SSH commit signing and provides `dotfiles-ssh-enroll`. It does not silently create or upload a key. |

### 4. Git identity

These final two questions always appear:

| Question | What to enter |
|---|---|
| **Git user name** | The name to write to Git's `user.name`. |
| **Git email address** | The email to write to Git's `user.email`; a GitHub `noreply` address is fine. |

The answers and detected host facts are stored in
`~/.config/chezmoi/chezmoi.json`. Re-running the one-line bootstrap later
updates the existing setup and does not ask these questions again.

## Recommended answers

- Personal Mac with the full setup: `workstation`, then do not customize.
- Personal Mac with fewer GUI apps: `laptop`, then do not customize.
- Ubuntu/Debian server: `server`, then do not customize.
- Dev container whose image already contains the programs: `container`, then
  do not customize.
- Any mixed setup: choose the closest preset, answer `Yes` to customization,
  and deliberately answer every feature question because the custom answers
  replace the preset values.

## What is included

The exact package source of truth is
[`packages.yaml`](.chezmoidata/packages.yaml). Chezmoi selects entries from it
using the chosen features and the current OS.

### Base bootstrap

Every supported host gets the tools needed to manage the repository:

- Age, Chezmoi, curl, and Git;
- Linux bootstrap dependencies: `build-essential`, `ca-certificates`, `file`,
  and `procps`;
- Homebrew on macOS or Linuxbrew plus apt on Debian/Ubuntu.

### Core CLI and shell

The CLI feature includes:

- Zsh with autosuggestions, syntax highlighting, history substring search,
  deferred fzf initialization, zoxide, thefuck, and Starship;
- Neovim, tmux, GitHub CLI, Jujutsu, Lazygit, Git Delta, and Pet;
- bat, eza, fd, fzf, ripgrep, jq, wget, Glow, tlrc, btop, and Tree-sitter CLI,
  plus `watch` on macOS;
- managed Git, Zsh, Neovim, tmux, Starship, and shell configuration.

Useful shell commands installed by the configuration:

| Command | Purpose |
|---|---|
| `ls`, `lsa` | Detailed eza listing, with `lsa` including hidden files. |
| `lt`, `lta` | Two-level directory tree, with `lta` including hidden files. |
| `cat` | bat without paging. |
| `cd` | zoxide smart directory navigation. |
| `lg` | Lazygit. |
| `tl` | Short help pages through tlrc. |
| `dc`, `dcup`, `dcdown`, `dce` | Docker Compose shortcuts. |
| `k` | `kubectl`. |
| `mcd NAME` | Create a directory and enter it. |
| `extract FILE` | Extract a supported archive. |
| `search QUERY` | Search with ripgrep, select in fzf, and open in the editor. |
| `help COMMAND` | Show colorized `--help` output. |
| `ec`, `vec` | Open the Chezmoi source in `$EDITOR` or `$VISUAL`. |
| `dot` | Run the same remote bootstrap/update command. |

### Developer toolchain

The developer feature includes:

- Go, Gopls, Rust Analyzer, Pyright, VTSLS, ShellCheck, clang-format, and
  Commitizen;
- PostgreSQL 18, Docker CLI/Compose, and Colima on macOS;
- fnm, mise, uv, Node `22.19.0`, Python `3.13.5`, Rust `1.88.0`, and Bun
  `1.2.19`;
- Google Cloud CLI, AWS CLI, kubectl, kubectx, kubens, and k9s;
- pinned Python tools: Black, isort, and Pylint;
- pinned cleanup tools: npkill, cargo-clean-all, cargo-cache, and kondo;
- supporting tools and libraries: freetype, gettext, gperf, imlib2, lcov,
  librsvg, libXfixes, libXft, libXi, libXinerama, libxml2, Lua, pkg-config, and
  the tmux plugin manager.

On macOS, Docker runs through Colima rather than Docker Desktop:

```bash
colima start
docker context use colima
```

### AI agent setup

The AI feature includes:

- Claude Code, PI Coding Agent, OpenCode, and Crush;
- `ax`, the common policy gateway for launching those agents;
- Nono sandbox profiles and Herdr integrations;
- a canonical model registry and shared MCP configuration;
- managed agent skills and CLIProxyAPI for local AI mode.

Normal launches go through `ax` and Nono:

```bash
ax claude
ax pi
ax opencode
ax crush
```

The native commands `claude`, `pi`, `opencode`, and `crush` are managed shims
that also enter `ax`. Use `ax <agent> --direct` only when intentionally
bypassing the sandbox for diagnosis.

Common AI administration:

```bash
ax auth setup             # initialize local proxy keys and provider login
ax auth setup codex       # authenticate one provider channel
ax models show            # show the role-to-model mapping
ax models validate        # validate the model registry
ax models live            # compare it with models advertised by the proxy
ax doctor                 # check authentication and the complete agent setup
```

Credentials, OAuth state, private SSH keys, and mutable agent sessions are not
stored in this repository.

### macOS GUI tiers

`minimum` installs:

- Raycast, Ice, Shottr, Hyperkey, Ghostty, Helium, Notion, Boring Notch, IINA,
  AppCleaner, and WhatsApp;
- JetBrains Mono Nerd Font and `mas`.

`all` includes everything in `minimum`, plus:

- Discord, Telegram, Notion Calendar, Zotero, DockDoor, VeraCrypt, Google
  Drive, Proton VPN, Handy, Zen, and Google Gemini;
- Zed, Antigravity IDE, Alacritty, Yaak, UTM, OnyX, and BasicTeX.

Mac App Store applications are intentionally not installed during an automatic
apply. Install the selected App Store apps later with:

```bash
dotfiles-macos-apps
```

### OS customization and hardening

The macOS customization feature manages:

- Dock layout and behavior;
- Finder visibility, extensions, path bar, status bar, and sorting;
- keyboard repeat and press-and-hold behavior;
- trackpad tap/right-click and scrolling;
- Spotlight suggestions and categories;
- PNG screenshots in `~/Screenshots`.

The Linux hardening feature:

- installs UFW and fail2ban;
- defaults to deny incoming and allow outgoing traffic;
- allows the detected SSH port plus ports 80 and 443;
- enables fail2ban through systemd;
- exits safely without applying firewall rules inside a container.

Set `DOTFILES_SSH_PORT` when applying if SSH uses a port that cannot be
automatically detected:

```bash
DOTFILES_SSH_PORT=2222 chezmoi apply
```

## Everyday Chezmoi workflow

These commands work from any directory:

```bash
chezmoi update                   # pull the repository and apply it
chezmoi diff                     # preview unapplied changes
chezmoi edit ~/.zshrc            # edit the source for one managed file
chezmoi apply                    # apply source changes to the home directory
chezmoi apply --dry-run --verbose
chezmoi managed                  # list managed destination paths
chezmoi source-path              # print ~/.local/share/chezmoi
chezmoi cd                       # open a shell in the source repository
```

A safe edit cycle is:

```bash
chezmoi edit ~/.zshrc
chezmoi diff
chezmoi apply
```

To edit this repository directly:

```bash
chezmoi cd
$EDITOR .
chezmoi diff
chezmoi apply
```

Files ending in `.tmpl` are Go templates. Preview them through `chezmoi diff`
or `chezmoi execute-template`; do not treat them as ordinary static config.

## Commands that require your presence

Automatic `chezmoi apply` does not authenticate accounts, upload SSH keys, or
delete applications. These operations are separate:

```bash
dotfiles-ssh-enroll       # create/add the key, authenticate gh, upload key
dotfiles-macos-apps       # install selected Mac App Store applications
dotfiles-macos-cleanup    # confirm removal of selected stock macOS apps
```

After SSH enrollment, run `chezmoi apply` again so Git signing is enabled when
the SSH feature is selected and `~/.ssh/gh_personal.pub` exists.

## Cleanup command

`one` cleans developer caches and project build artifacts:

```bash
one system --dry-run
one system --yes
one project /path/to/project --dry-run
one project /path/to/project --node
one project /path/to/project --rust
one all /path/to/project --dry-run
one list
one doctor
```

Use `--dry-run` before removing data.

## Change the answers later

First inspect the current persistent config:

```bash
chezmoi data
```

To answer all initialization questions again, back up the config, force
re-initialization from the existing source, and review the result before
applying:

```bash
cp ~/.config/chezmoi/chezmoi.json ~/.config/chezmoi/chezmoi.json.before-reinit
chezmoi init --force --source "$(chezmoi source-path)"
chezmoi diff
chezmoi apply
```

Disabling a feature stops Chezmoi from managing or installing it in the future.
It does not uninstall packages or delete already-created configuration.

Existing pre-machine-model configurations are deliberately kept in a
compatibility lane. Do not reinitialize an existing Mac merely to update it;
use the one-line bootstrap or `chezmoi update` unless migration to the new
machine model is intentional.

## Unattended setup

Example configs are in [`examples/configs`](examples/configs):

- `linux-server-amd64.json`
- `linux-laptop-arm64.json`
- `linux-container-amd64.json`
- `macos-workstation-arm64.json`
- `macos-server-amd64.json`

Copy the closest example and change its identity, host facts, preset, and
overrides. Then run:

```bash
DOTFILES_CONFIG=/absolute/path/to/linux-server-amd64.json \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

The bootstrap installs that file as
`~/.config/chezmoi/chezmoi.json` and applies it without prompts.

To render an example without changing the current machine:

```bash
preview_dir="$(mktemp -d)"
chezmoi managed \
  --config examples/configs/linux-server-amd64.json \
  --config-format json \
  --source . \
  --destination "$preview_dir" \
  --refresh-externals=never
```

## Repository layout

| Path | Purpose |
|---|---|
| [`.chezmoi.json.tmpl`](.chezmoi.json.tmpl) | Initialization questions and persistent machine config. |
| [`.chezmoidata/machine.yaml`](.chezmoidata/machine.yaml) | Preset defaults and supported platforms. |
| [`.chezmoitemplates/machine`](.chezmoitemplates/machine) | Resolves presets, overrides, host facts, and policy predicates. |
| [`.chezmoidata/packages.yaml`](.chezmoidata/packages.yaml) | Canonical package inventory for apt, Homebrew, casks, mise, npm, uv, and cargo. |
| [`dot_dotfiles`](dot_dotfiles) | Zsh exports, aliases, functions, and integrations. |
| [`dot_config`](dot_config) | Managed application configuration under `~/.config`. |
| [`dot_local/bin`](dot_local/bin) | `ax`, agent shims, enrollment helpers, and `one`. |
| [`examples/configs`](examples/configs) | Explicit unattended machine configurations. |
| [`tests/test_machine_matrix.sh`](tests/test_machine_matrix.sh) | macOS/Linux, `amd64`/`arm64`, and preset validation matrix. |

Package choices belong in `.chezmoidata/packages.yaml`. The repository-owned
`add-dotfiles-app` skill under `~/.config/agents/skills/add-dotfiles-app` is the
preferred way to add, remove, or reclassify applications.

## Safety boundaries

- Review `chezmoi diff` before applying important changes.
- Account enrollment, SSH upload, App Store installation, and destructive macOS
  cleanup are never automatic.
- Sensitive authentication material is not committed to this repository.
- An absent local Age identity prevents encrypted backup material from being
  deployed.
- Unsupported operating systems, Linux distributions, architectures, and
  provisioning failures stop the run.
- macOS uses Colima, not Docker Desktop.

## Validate repository changes

```bash
bash tests/test_machine_matrix.sh
bash dot_local/bin/tests/test_ax.sh
bash dot_local/bin/tests/test_one.sh
bash dot_backup/coolify/tests/test_stack.sh
chezmoi managed --refresh-externals=never
chezmoi diff
chezmoi apply --dry-run
```
