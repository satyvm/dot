#!/usr/bin/env bash
# =============================================================================
# packages.sh — Linux package installation
# Supports: Ubuntu/Debian (apt) + Homebrew on Linux for CLI tools
# =============================================================================

set -euo pipefail

echo "→ Updating apt..."
sudo apt update && sudo apt upgrade -y

echo "→ Installing system packages..."
sudo apt install -y \
  curl wget git build-essential \
  zsh tmux htop \
  ca-certificates gnupg lsb-release \
  software-properties-common apt-transport-https \
  unzip zip xclip xdg-utils

# ── Homebrew on Linux ─────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "→ Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

echo "→ Installing CLI tools via Homebrew..."
brew install \
  neovim \
  git-delta gh jj stow \
  fzf ripgrep fd bat eza zoxide \
  starship zsh-autosuggestions zsh-syntax-highlighting \
  btop jq yq tree \
  python@3.12 node go rustup lua luarocks \
  kubectl kubectx kind helm \
  1password-cli

echo "✓ Linux packages installed"
