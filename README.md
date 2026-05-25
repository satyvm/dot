# 🌌 satyvm / dot

A modular, secure, and modern macOS/Linux dotfiles repository managed with [chezmoi](https://chezmoi.io) and secured via [age](https://github.com/FiloSottile/age) and [1Password](https://1password.com).

## 🚀 Bootstrap Installation

To set up a fresh machine, open your terminal and run the following command.

> [!CAUTION]
> **DO NOT** prefix this command with `sudo`. 
> * Homebrew explicitly forbids running as `root` and will fail immediately.
> * Running with `sudo` will cause chezmoi and your SSH/gpg keys to install inside `/var/root` instead of your home directory (`/Users/yourname`), causing major permission errors.
> * The installation script will prompt you for `sudo` only when absolutely required (e.g., package managers on Linux).

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

## 🔒 Secrets Management (`age` & `1Password`)

This repository uses modern asymmetric encryption (`age`) to secure sensitive configuration files (like private shell aliases).

### Fresh Machine Setup

Before running the bootstrap script on a new machine, ensure your existing `age` private key is backed up in your **1Password** vault:

1. Open your 1Password App.
2. Create a new **Secure Note** named exactly **`chezmoi-key`**.
3. Copy the **entire** text of your age private key (from `~/.config/chezmoi/key.txt` on your active machine).
4. Paste it directly into the main **Notes** field of the `chezmoi-key` secure note.

When the bootstrap script runs, it will sign into your 1Password CLI and **automatically download and restore** your private key securely. No manual file transfers required!

---

## 🛠️ Repository Layout

```
.
├── dot_config/              # Application configurations (~/.config/)
│   ├── ghostty/             # Ghostty terminal configurations
│   ├── git/                 # Git user configuration & templates
│   ├── starship/            # Prompt settings
│   └── tmux/                # Tmux multiplexer config
├── dot_dotfiles/            # Shell and environment configuration (~/.dotfiles/)
│   ├── dot_aliases.tmpl     # Shell aliases (conditionally decrypted)
│   ├── dot_exports          # Environment variables
│   └── dot_functions.tmpl   # Custom shell helpers
└── dot_zshrc                # Main Zsh entrypoint (~/.zshrc)
```
