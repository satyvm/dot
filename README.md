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
4. Prompt for a **machine profile**, then apply dotfiles

### Already have chezmoi?

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
chezmoi init --apply satyvm/dot
```

Git name/email are read from your global git config — configure those before the first apply.

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

### Repo-only (not deployed to `~/`)

These live in the git repo but chezmoi does **not** sync them to your home directory:

| Path | Purpose |
|------|---------|
| `scripts/backup-local.sh` | Back up local app data to external SSD |
| `scripts/restore-local.sh` | Restore from external SSD backup |
| `cursor-default.code-profile` | Cursor profile export — imported by `run_onchange_import-cursor-profile` on **dev** macOS |

Run backup/restore from the source directory:

```bash
"$(chezmoi source-path)/scripts/backup-local.sh"
"$(chezmoi source-path)/scripts/restore-local.sh" /Volumes/MyDrive/mac_backup/local_310526
```

### Setup Scripts

| Script | When | What |
|--------|------|------|
| `run_onchange_brew-packages` | On change | Installs Homebrew packages (profile-aware) |
| `run_onchange_apt-packages` | On change | Installs apt packages + Docker (profile-aware) |
| `run_onchange_import-cursor-profile` | On change | Imports `cursor-default.code-profile` (dev macOS) |
| `run_once_after_install-rustup-uv` | First run | Installs Rust (rustup) and Python (uv) |
| `run_once_after_setup-macos-defaults` | First run | macOS system preferences + Finder sidebar pins |
| `run_once_after_cleanup-macos-apps` | First run | Removes stock macOS bloatware |
| `run_once_after_setup-linux` | First run | UFW, fail2ban, zsh (Linux dev + server) |

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
├── .chezmoi.json.tmpl           # chezmoi config (profile prompt only)
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
