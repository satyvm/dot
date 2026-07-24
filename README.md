# 🌌 satyvm / dot

Personal dotfiles managed with [chezmoi](https://chezmoi.io).

Works on **macOS** (primary) and **Linux** (Debian/Ubuntu servers).

Sensitive and large data (SSH keys, app profiles, documents) is synced separately via `scripts/backup-local.sh` and `scripts/restore-local.sh` to an external SSD — not tracked in this repo.

---

## ⚡ Quick Start

### One-Line Install (fresh machine)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

This will:
1. Install Xcode CLI tools (macOS) or core packages (Linux)
2. Install Homebrew (macOS) or chezmoi directly (Linux)
3. Install `chezmoi` and `age`
4. Prompt for **machine profile**, **git name**, and **git email**, then apply dotfiles

### Already have chezmoi?

```bash
chezmoi init --apply satyvm/dot
```

Git `user.name` and `user.email` are set from the values you enter during `chezmoi init`.

---

## 🖥️ Machine Profiles

During `chezmoi init`, choose one profile:

| Profile | macOS | Linux |
|---------|-------|-------|
| `personal` | Essential GUIs only (Chrome, Ghostty, Raycast) + CLI tools | CLI tools only |
| `dev` | Full desktop setup — all apps, Cursor profile import, macOS defaults | CLI tools + Docker + server hardening |
| `server` | CLI tools + Docker (Colima) — no GUIs, no macOS defaults | CLI tools + Docker + UFW/fail2ban |

Docker is installed automatically on **dev** and **server** (Colima on macOS, Docker Engine on Linux).

---

## 📁 What's Included

### Shell

| File | Purpose |
|------|---------|
| `dot_zshrc` | Main shell config — loads Homebrew, sources dotfiles, inits starship |
| `dot_dotfiles/.exports` | Environment variables, PATH, XDG dirs, history settings |
| `dot_dotfiles/.aliases` | Aliases for eza, bat, zoxide, docker, kubectl, and more |
| `dot_dotfiles/.functions` | Helper functions (mcd, zipf, extract, search) |
| `dot_dotfiles/.extra` | Tool inits (zsh plugins, fnm, zoxide, fzf, thefuck) |

### Configs

| Path | Tool |
|------|------|
| `dot_config/nvim/` | Neovim (lazy.nvim based) |
| `dot_config/tmux/tmux.conf` | tmux |
| `dot_config/starship/starship.toml` | Starship prompt |
| `dot_config/ghostty/config.ghostty` | Ghostty terminal |
| `dot_config/git/config` | Git (delta, SSH signing, rebase) |
| `dot_config/git/ignore` | Global gitignore |
| `dot_config/agents/` | AI agent skills |

### Sandboxed AI coding agents (macOS `dev`)

`ax` is the public launcher for Claude Code, Pi, OpenCode, and Crush. Managed
shims make the native command names delegate to it, so direct shell launches
and Herdr restores share the same Nono policy:

```bash
ax claude
ax pi --resume session-id
ax opencode --direct       # explicit emergency sandbox escape
ax crush --continue
ax doctor
```

The stable model roles are `frontier`, `balanced`, `fast`, and `light`.
Edit and deploy their mappings with:

```bash
ax models edit
ax models validate
ax models sync
```

The tracked source of truth is `.chezmoidata/ai-agent-platform.yaml`. Chezmoi
renders client model catalogs and CLIProxyAPI aliases from it. The portable
boundary includes model metadata, defaults, sandbox profiles, proxy settings,
and Herdr setup. Device-local state is deliberately outside Git:

- `~/.config/cli-proxy-api/client-key` and `management-key`
- CLIProxyAPI OAuth/account JSON files
- agent session/state directories and Herdr runtime sockets
- SSH keys, Keychain data, browser profiles, and authenticated Git credentials

On each new Mac, run `ax auth setup` to complete the active provider's
interactive login, then run `ax doctor`. Secrets are inserted only into the
private rendered proxy config and diagnostics never print their values.

The deterministic suite is `bash dot_local/bin/tests/test_ax.sh`. The separate
live smoke test makes real model calls and is opt-in:

```bash
AX_LIVE_SMOKE=1 ~/.local/bin/tests/test_ax_live.sh
```

### Repo-only (not deployed to `~/`)

These live in the git repo but chezmoi does **not** sync them to your home directory:

| Path | Purpose |
|------|---------|
| `scripts/backup-local.sh` | Back up local app data to external SSD |
| `scripts/restore-local.sh` | Restore from external SSD backup |
| `cursor-default.code-profile` | Cursor profile export — imported on **dev** macOS during setup |

Run backup/restore from the source directory:

```bash
"$(chezmoi source-path)/scripts/backup-local.sh"
"$(chezmoi source-path)/scripts/restore-local.sh" /Volumes/MyDrive/mac_backup/local_310526
```

### Setup Scripts

| Script | When | What |
|--------|------|------|
| `run_onchange_brew-packages` | On change | Installs profile-specific Homebrew packages |
| `run_onchange_apt-packages` | On change | Installs profile-specific apt packages |
| `run_once_after_install-tools` | First run | Installs language runtimes (`rustup`, `uv`, `fnm`/Node, global `mise` tools) and cleans up non-essential stock macOS apps |
| `run_once_after_setup-macos` | First run | Applies system defaults (Dock, trackpad, Finder, keyboard) |
| `run_once_after_setup-linux` | First run | Sets up server firewall, default shell, and security (UFW, `fail2ban`) |
| `run_once_after_setup-ssh-key` | First run | Generates SSH keys and registers them via GitHub CLI |
| `run_once_after_setup-zend` | First run | Launches applications (Raycast, Ghostty) for initial setup |

---

## 🔧 Daily Usage

```bash
chezmoi update          # pull and apply
chezmoi diff            # preview changes
chezmoi edit ~/.zshrc   # edit a managed file
chezmoi cd              # open source directory
```

### Re-run a setup script

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

---

## 📂 Directory Structure

```
~/.local/share/chezmoi/
├── .chezmoi.json.tmpl           # chezmoi config (profile, git name/email, SSH key prompts)
├── .chezmoiignore.tmpl          # platform/profile ignore rules
├── .setup.sh                    # bootstrap script
├── cursor-default.code-profile  # Cursor profile (repo-only, dev import)
├── scripts/                     # backup/restore (repo-only)
├── dot_zshrc                    # → ~/.zshrc
├── dot_dotfiles/                # → ~/.dotfiles/
├── dot_config/                  # → ~/.config/
└── run_*                        # setup scripts
```

---

## 🔄 Backup (External SSD)

Use the scripts in `scripts/` to sync sensitive and large data to an external drive:

```bash
"$(chezmoi source-path)/scripts/backup-local.sh"
"$(chezmoi source-path)/scripts/backup-local.sh" /Volumes/MyDrive
```

Backs up: Zen Browser, Helium, Raycast, Antigravity, Zotero, Velja, `~/.ssh`, Developer, Work, Study, Documents, Desktop, Downloads, Pictures.

---

## 📝 License

MIT
