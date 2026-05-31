# 🌌 satyvm / dot

Personal dotfiles managed with [chezmoi](https://chezmoi.io), secured with [age](https://github.com/FiloSottile/age) encryption and [1Password CLI](https://developer.1password.com/docs/cli/).

Works on **macOS** (primary) and **Linux** (Debian/Ubuntu servers).

---

## ⚡ Quick Start

### One-Line Install (fresh machine)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

This single command will:
1. Install Xcode CLI tools (macOS) or core packages (Linux)
2. Install Homebrew (macOS) or chezmoi directly (Linux)
3. Install `chezmoi`, `age`, and `1password-cli`
4. Sign into 1Password CLI
5. Initialize and apply dotfiles from this repo

### Already have chezmoi?

```bash
chezmoi init --apply satyvm/dot
```

---

## 🔐 Prerequisites (Before First Install)

Your age private key must be stored in **1Password** before running the setup on a new machine:

1. Open your **1Password** app
2. Create a **Secure Note** named exactly **`chezmoi-key`**
3. Paste the entire contents of `~/.config/chezmoi/key.txt` from your active machine into the **Notes** field
4. Save

The bootstrap script will automatically retrieve this key via 1Password CLI. No manual file transfers needed.

---

## 📁 What's Included

### Shell

| File | Purpose |
|------|---------|
| `dot_zshrc` | Main shell config — loads Homebrew, sources dotfiles, inits starship |
| `dot_dotfiles/.exports` | Environment variables, PATH, XDG dirs, history settings |
| `dot_dotfiles/.aliases` | Aliases for eza, bat, zoxide, docker, kubectl, and more |
| `dot_dotfiles/.functions` | Helper functions (mcd, zipf, extract) |
| `dot_dotfiles/.extra` | Tool inits (zsh plugins, fnm, zoxide, fzf, thefuck) |

### Configs

| Path | Tool |
|------|------|
| `dot_config/nvim/` | Neovim (lazy.nvim based) |
| `dot_config/tmux/tmux.conf` | tmux (tpm, vim-tmux-navigator, resurrect) |
| `dot_config/starship/starship.toml` | Starship prompt |
| `dot_config/ghostty/config.ghostty` | Ghostty terminal |
| `dot_config/git/config` | Git (delta, SSH signing, rebase) |
| `dot_config/git/ignore` | Global gitignore |
| `dot_config/agents/` | AI agent skills (Claude, Vercel, etc.) |
| `dot_config/opencode/` | OpenCode config |
| `dot_ssh/config` | SSH config (age-encrypted) |
| `private_Library/` | Cursor settings (macOS only) |

### Setup Scripts

| Script | When | What |
|--------|------|------|
| `run_once_before_install-prerequisites` | First run | Installs 1Password CLI, retrieves age key |
| `run_onchange_brew-packages` | On change | Installs/updates Homebrew packages (macOS) |
| `run_onchange_apt-packages` | On change | Installs/updates apt packages (Linux) |
| `run_once_after_install-rustup-uv` | First run | Installs Rust (rustup) and Python (uv) — both platforms |
| `run_once_after_setup-ssh-key` | First run | Generates SSH key, uploads to GitHub |
| `run_once_after_setup-macos-defaults` | First run | Applies macOS system preferences |
| `run_once_after_cleanup-macos-apps` | First run | Removes stock macOS bloatware |
| `run_once_after_setup-linux` | First run | Configures UFW, fail2ban, zsh (Linux servers) |
| `run_onchange_install-cursor-extensions` | On change | Installs Cursor IDE extensions |

---

## 🖥️ Machine Profiles

During `chezmoi init`, you'll be prompted to select a profile:

| Profile | Platform | What it does |
|---------|----------|-------------|
| `personal` | macOS | Full desktop setup — all apps, configs, and tools |
| `work` | macOS | Same as personal + decrypts `.work_aliases` and `.work_functions` |
| `server` | Linux | CLI-only — no desktop apps, adds UFW + fail2ban hardening |

---

## 🔧 Daily Usage

### Update dotfiles

```bash
# Pull latest and apply
chezmoi update

# Or step by step
chezmoi git pull
chezmoi diff      # preview changes
chezmoi apply     # apply changes
```

### Edit a managed file

```bash
# Edit in chezmoi source, then apply
chezmoi edit ~/.zshrc
chezmoi apply

# Or edit the source directly
cd $(chezmoi source-path)
nvim dot_zshrc
chezmoi apply
```

### Add a new file to be managed

```bash
chezmoi add ~/.config/some-tool/config
chezmoi cd   # opens shell in source dir
git add -A && git commit -m "add some-tool config"
git push
```

### Re-run a setup script

```bash
# Chezmoi tracks run_once scripts by hash. To re-run one:
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

### Check what would change

```bash
chezmoi diff
chezmoi status
```

---

## 🛠️ Key Tools

| Tool | Replaces | Alias |
|------|----------|-------|
| [eza](https://eza.rocks) | `ls` | `ls`, `ll`, `tree` |
| [bat](https://github.com/sharkdp/bat) | `cat` | `cat` |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | `cd` | `cd` (aliased to `z`) |
| [fd](https://github.com/sharkdp/fd) | `find` | `fd` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `grep` | `rg` |
| [fzf](https://github.com/junegunn/fzf) | — | `Ctrl+T`, `Ctrl+R`, `Alt+C` |
| [delta](https://github.com/dandavella/delta) | `diff` | Git pager |
| [lazygit](https://github.com/jesseduffield/lazygit) | — | `lg` |
| [tlrc](https://github.com/tldr-pages/tlrc) | `man` | `tldr` |
| [btop](https://github.com/aristocratos/btop) | `top`/`htop` | `btop` |
| [thefuck](https://github.com/nvbn/thefuck) | — | `fuck`, `fk` |
| [starship](https://starship.rs) | PS1/prompt | auto |
| [fnm](https://github.com/Schniz/fnm) | nvm | auto |
| [uv](https://github.com/astral-sh/uv) | pip/venv | `uv` |

---

## 📂 Directory Structure

```
~/.local/share/chezmoi/          # chezmoi source directory
├── .chezmoi.json.tmpl           # chezmoi config (prompts for name, email, profile)
├── .chezmoiignore.tmpl          # platform-aware ignore rules
├── .setup.sh                    # bootstrap script (curl | bash)
├── dot_zshrc                    # → ~/.zshrc
├── dot_dotfiles/                # → ~/.dotfiles/
│   ├── .exports                 #   env vars, PATH, history
│   ├── .aliases                 #   shell aliases
│   ├── .functions               #   shell functions
│   ├── .extra                   #   tool inits (plugins, fzf, zoxide)
│   └── backup-local.sh          #   local app backup script
├── dot_config/                  # → ~/.config/
│   ├── nvim/                    #   neovim config
│   ├── tmux/                    #   tmux config
│   ├── starship/                #   starship prompt
│   ├── ghostty/                 #   ghostty terminal
│   ├── git/                     #   git config + global ignore
│   ├── agents/                  #   AI agent skills
│   └── opencode/                #   opencode config
├── dot_ssh/                     # → ~/.ssh/ (encrypted)
├── private_Library/             # → ~/Library/ (macOS Cursor settings)
├── run_once_before_*            # first-run setup scripts
├── run_once_after_*             # post-apply setup scripts
└── run_onchange_*               # re-run on content change
```

---

## 🔑 Encryption

Sensitive files (SSH config, work aliases/functions) are encrypted with [age](https://age-encryption.org).

```bash
# The age key is stored at:
~/.config/chezmoi/key.txt

# To encrypt a new file:
chezmoi add --encrypt ~/.ssh/config

# To view encrypted source:
chezmoi cat ~/.ssh/config
```

---

## 🔄 Backup

Use the included backup script to back up local app data to an external drive:

```bash
# Auto-detect external drive
~/.dotfiles/backup-local.sh

# Specify drive
~/.dotfiles/backup-local.sh /Volumes/MyDrive
```

Backs up: Zen Browser, Helium, Raycast, Antigravity, Zotero, Velja.

---

## 📝 License

MIT