#!/usr/bin/env bash
# =============================================================================
# sync-apps.sh — Sync VSCode, Raycast, and Browser configs
#
# This script handles exporting/importing app configurations that don't
# natively support plain-text dotfiles well.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  → ${RESET}$*"; }
success() { echo -e "${GREEN}  ✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${RESET}$*"; }
error()   { echo -e "${RED}  ✗ ${RESET}$*" >&2; exit 1; }

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VSCODE_DIR="$DOT_DIR/config/.config/vscode"
VSCODE_MAC_DIR="$HOME/Library/Application Support/Code/User"

mkdir -p "$VSCODE_DIR"

echo ""
echo -e "${BOLD}App Sync (VSCode, Raycast, Browsers)${RESET}"
echo "  1) Backup VSCode settings & extensions to dotfiles"
echo "  2) Restore VSCode settings & extensions from dotfiles"
echo "  3) View info on Raycast & Browser Syncing"
read -r -p "$(echo -e "${YELLOW}  ? Choose [1/2/3]: ${RESET}")" MODE

if [[ "$MODE" == "1" ]]; then
  # ── BACKUP VSCODE ─────────────────────────────────────────────────────────
  if ! command -v code &>/dev/null; then
    error "VSCode 'code' CLI not found. Install VSCode first."
  fi

  info "Exporting VSCode extensions list..."
  code --list-extensions > "$VSCODE_DIR/extensions.txt"
  
  info "Copying VSCode settings.json and keybindings.json..."
  [[ -f "$VSCODE_MAC_DIR/settings.json" ]] && cp "$VSCODE_MAC_DIR/settings.json" "$VSCODE_DIR/"
  [[ -f "$VSCODE_MAC_DIR/keybindings.json" ]] && cp "$VSCODE_MAC_DIR/keybindings.json" "$VSCODE_DIR/"
  [[ -d "$VSCODE_MAC_DIR/snippets" ]] && cp -r "$VSCODE_MAC_DIR/snippets" "$VSCODE_DIR/"

  success "VSCode config successfully backed up to config/.config/vscode/"

elif [[ "$MODE" == "2" ]]; then
  # ── RESTORE VSCODE ────────────────────────────────────────────────────────
  if ! command -v code &>/dev/null; then
    error "VSCode 'code' CLI not found. Install VSCode first."
  fi

  if [[ ! -f "$VSCODE_DIR/extensions.txt" ]]; then
    error "No VSCode backup found in dotfiles."
  fi

  info "Installing VSCode extensions..."
  while read -r ext; do
    [[ -n "$ext" ]] && code --install-extension "$ext" --force
  done < "$VSCODE_DIR/extensions.txt"

  info "Restoring VSCode settings..."
  mkdir -p "$VSCODE_MAC_DIR"
  [[ -f "$VSCODE_DIR/settings.json" ]] && cp "$VSCODE_DIR/settings.json" "$VSCODE_MAC_DIR/"
  [[ -f "$VSCODE_DIR/keybindings.json" ]] && cp "$VSCODE_DIR/keybindings.json" "$VSCODE_MAC_DIR/"
  [[ -d "$VSCODE_DIR/snippets" ]] && cp -r "$VSCODE_DIR/snippets" "$VSCODE_MAC_DIR/"

  success "VSCode config and extensions successfully restored!"

elif [[ "$MODE" == "3" ]]; then
  # ── BROWSER & RAYCAST INFO ────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}Raycast Sync:${RESET}"
  echo "Raycast settings contain sensitive tokens and workflows."
  echo "• Best method: Use Raycast Pro's built-in cloud sync."
  echo "• Manual method: Open Raycast Settings -> Advanced -> Export."
  echo "  Save the .rayconfig file to 1Password or securely outside of git."
  echo ""
  echo -e "${BOLD}Browser Sync (Chrome/Arc/Brave):${RESET}"
  echo "Browser profiles contain encrypted passwords and SQLite databases."
  echo "Do NOT sync '~/Library/Application Support/Google/Chrome' via Git/Stow,"
  echo "as it will cause database corruption and keychain decryption failures."
  echo "• Solution: Always use the browser's native Sync feature (e.g. Chrome Sync)."
  echo ""
else
  error "Invalid choice."
fi
