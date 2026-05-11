#!/usr/bin/env bash
# =============================================================================
# update.sh — pull latest dotfiles and re-apply
# =============================================================================

set -euo pipefail

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "→ Pulling latest dotfiles..."
git -C "$DOT_DIR" pull --rebase

echo "→ Re-stowing packages..."
stow --dir="$DOT_DIR" --target="$HOME" --restow home
stow --dir="$DOT_DIR" --target="$HOME" --restow config

echo "→ Updating Homebrew packages..."
brew bundle --file="$DOT_DIR/macos/Brewfile" --no-lock 2>/dev/null || true

echo "✓ Dotfiles updated! Run: source ~/.zshrc"
