#!/usr/bin/env bash
# =============================================================================
#  install.sh — dotfiles bootstrap
#  One-liner: curl -fsSL https://raw.githubusercontent.com/satyvm/dot/main/install.sh | bash
# =============================================================================

set -euo pipefail

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  → ${RESET}$*"; }
success() { echo -e "${GREEN}  ✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${RESET}$*"; }
error()   { echo -e "${RED}  ✗ ${RESET}$*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}══════ $* ══════${RESET}\n"; }

# ── helpers ───────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "$(echo -e "${YELLOW}  ? ${prompt} [y/N] ${RESET}")" reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ── OS check ─────────────────────────────────────────────────────────────────
header "Dotfiles Bootstrap — satyvm/dot"
info "Detected OS: $OS"
info "Dotfiles dir: $DOT_DIR"

case "$OS" in
  Darwin|Linux) ;;
  *) error "Unsupported OS: $OS"; exit 1 ;;
esac

# ── Homebrew ─────────────────────────────────────────────────────────────────
header "Homebrew"
if ! command_exists brew; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH for this session on Linux / Apple Silicon
  if [[ "$OS" == "Linux" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  elif [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  success "Homebrew installed"
else
  info "Homebrew already installed — updating..."
  brew update --quiet
  success "Homebrew up to date"
fi

# ── GNU Stow ──────────────────────────────────────────────────────────────────
header "GNU Stow"
if ! command_exists stow; then
  info "Installing stow..."
  brew install stow
fi
success "stow available"

# ── Packages ─────────────────────────────────────────────────────────────────
header "Packages"
case "$OS" in
  Darwin)
    info "Installing from macos/Brewfile..."
    brew bundle --file="$DOT_DIR/macos/Brewfile" --no-lock
    ;;
  Linux)
    info "Installing from linux/packages.sh..."
    bash "$DOT_DIR/linux/packages.sh"
    ;;
esac
success "Packages installed"

# ── Symlink configs ───────────────────────────────────────────────────────────
header "Symlinking configs"

# Back up anything that would conflict, then stow
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

stow_pkg() {
  local pkg="$1"
  local target="${2:-$HOME}"
  info "Stowing $pkg → $target"
  # Adopt existing files into the stow dir, then restow cleanly
  stow --dir="$DOT_DIR" --target="$target" --adopt "$pkg" 2>/dev/null || true
  stow --dir="$DOT_DIR" --target="$target" --restow "$pkg"
}

stow_pkg "home"          # → ~/.zshrc, ~/.gitconfig, ~/.gitignore_global
stow_pkg "config" "$HOME" # → ~/.config/nvim, ~/.config/git, etc.

success "Configs symlinked"

# ── Shell ─────────────────────────────────────────────────────────────────────
header "Default shell"
ZSH_PATH="$(which zsh)"
if [[ "$SHELL" != "$ZSH_PATH" ]]; then
  if ! grep -q "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" | sudo tee -a /etc/shells
  fi
  info "Setting default shell to zsh..."
  chsh -s "$ZSH_PATH"
  success "Default shell → $ZSH_PATH"
else
  success "Already using zsh"
fi

# ── 1Password CLI + SSH keys ──────────────────────────────────────────────────
header "1Password CLI & SSH keys"
bash "$DOT_DIR/scripts/setup-ssh.sh"

# ── macOS system defaults ─────────────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then
  header "macOS defaults"
  if confirm "Apply macOS system defaults?"; then
    bash "$DOT_DIR/macos/defaults.sh"
    success "macOS defaults applied"
  else
    warn "Skipped macOS defaults"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}  ✓ Bootstrap complete!${RESET}"
echo -e "${CYAN}  Restart your terminal or run: source ~/.zshrc${RESET}\n"
