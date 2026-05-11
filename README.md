# dot — satyvm's dotfiles

Personal dotfiles for macOS (primary) and Linux, managed with **GNU Stow** and bootstrapped with a single script.

## One-liner install

```bash
git clone https://github.com/satyvm/dot ~/Developer/personal/dot
cd ~/Developer/personal/dot && bash install.sh
```

> Or if you trust the internet: `curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/install.sh | bash`

---

## What's inside

```
dot/
├── install.sh              # bootstrap everything (run this first)
├── update.sh               # pull + restow + brew bundle
│
├── home/                   # stow → $HOME
│   ├── .zshrc
│   ├── .gitconfig
│   └── .stow-local-ignore
│
├── config/                 # stow → $HOME (produces ~/.config/…)
│   └── .config/
│       ├── nvim/           # Neovim (lazy.nvim)
│       ├── vscode/         # VSCode settings/extensions backup
│       ├── git/            # global gitignore & work email config
│       └── starship.toml   # oh-my-zsh style prompt
│
├── macos/
│   ├── Brewfile            # all packages (brew + casks + fonts)
│   └── defaults.sh         # macOS system preferences
│
├── linux/
│   └── packages.sh         # apt + Homebrew on Linux
│
└── scripts/
    ├── setup-ssh.sh        # 1Password CLI SSH key setup
    ├── setup-ubuntu-server.sh
    └── scp-speed-test.sh
```

---

## How stow works here

Two **stow packages**:

| Package | Stow target | Installs to |
|---------|-------------|-------------|
| `home/` | `$HOME` | `~/.zshrc`, `~/.gitconfig` |
| `config/` | `$HOME` | `~/.config/nvim/`, `~/.config/git/`, `~/.config/starship.toml` |

Stow creates symlinks from `~` back into this repo. Edit files here; changes reflect everywhere.

## 1Password Secure SSH Sync

SSH keys and configs (including hostnames/IPs) shouldn't be exposed in git. We use 1Password Documents to store them securely.

1. **Backup**: Run `bash scripts/setup-ssh.sh` → Choose `1`
   - Archives `~/.ssh` and creates a secure document `dotfiles-ssh-backup` in your 1Password Personal vault.
2. **Restore**: Run `bash scripts/setup-ssh.sh` → Choose `2`
   - Downloads and extracts the archive onto a new machine.

## Syncing Other Apps

Run `bash scripts/sync-apps.sh` to handle syncing of apps that don't play nicely with standard dotfiles (VSCode, Browsers, Raycast).

### VSCode
- We use the `sync-apps.sh` script to export `extensions.txt`, `settings.json`, and `keybindings.json` to `config/.config/vscode/`. 
- You can run the same script on a new machine to automatically restore them.

### Raycast & Browsers
- **Browsers (Chrome/Brave/Arc):** ALWAYS use native browser sync features. Do not attempt to symlink browser profiles in dotfiles, as this will break SQLite databases and keychain decryptions.
- **Raycast:** Use Raycast Pro cloud sync, OR manually export from `Raycast Settings -> Advanced -> Export` and save the `.rayconfig` file securely.

---

## Shell

- **zsh** + **Starship** prompt (matching the classic `robbyrussell` oh-my-zsh aesthetic, but 10x faster)
- **fzf** for fuzzy history / file search
- **zoxide** as a smart `cd` replacement
- **eza** / **bat** replacing `ls` / `cat`

---

## Neovim

Config lives natively in `config/.config/nvim/` — structured by concern using **lazy.nvim**:
- `ui.lua`: tokyonight, lualine, dashboard
- `lsp.lua`: mason, lspconfig, cmp, formatting, linting
- `editor.lua`: telescope, treesitter, surround, substitute
- `tools.lua`: file explorer, git, terminal

---

## Docker (Colima)

Docker runs via **Colima** (no Docker Desktop or OrbStack UI). 
- Start the daemon: `colima start`
- Stop the daemon: `colima stop`
- All docker CLI aliases (`d`, `dc`, `dps`) work normally.

---

## Updating

```bash
# From anywhere
cd ~/Developer/personal/dot && bash update.sh
```