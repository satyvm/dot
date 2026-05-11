#!/usr/bin/env bash
# =============================================================================
# setup-ssh.sh — 1Password full ~/.ssh Backup and Restore
#
# This script uses 1Password CLI to securely store your entire ~/.ssh
# folder (including private keys and SSH config with IPs) as an encrypted
# archive in your 1Password vault.
#
# On a new machine, it downloads and extracts the archive.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  → ${RESET}$*"; }
success() { echo -e "${GREEN}  ✓ ${RESET}$*"; }
warn()    { echo -e "${YELLOW}  ⚠ ${RESET}$*"; }
error()   { echo -e "${RED}  ✗ ${RESET}$*" >&2; exit 1; }

# =============================================================================
# 1. Verify op CLI
# =============================================================================
if ! command -v op &>/dev/null; then
  error "1Password CLI not found. Install: brew install --cask 1password-cli"
fi

info "Checking 1Password session..."
if ! op account list &>/dev/null 2>&1; then
  info "No accounts found — signing in..."
  eval "$(op signin)"
else
  eval "$(op signin 2>/dev/null)" || true
fi
success "1Password authenticated"

echo ""
echo -e "${BOLD}1Password SSH Backup / Restore${RESET}"
echo "  1) Backup current ~/.ssh to 1Password"
echo "  2) Restore ~/.ssh from 1Password"
read -r -p "$(echo -e "${YELLOW}  ? Choose [1/2]: ${RESET}")" MODE

if [[ "$MODE" == "1" ]]; then
  # ── BACKUP ────────────────────────────────────────────────────────────────
  if [[ ! -d "$HOME/.ssh" ]] || [[ -z "$(ls -A "$HOME/.ssh")" ]]; then
    error "~/.ssh is empty or does not exist. Nothing to backup."
  fi

  ARCHIVE_PATH="/tmp/dotfiles-ssh-backup.tar.gz"
  
  info "Creating secure archive of ~/.ssh..."
  # Use tar to preserve file permissions
  tar -czf "$ARCHIVE_PATH" -C "$HOME" .ssh
  
  # Check if document already exists to overwrite/update it, or create new
  DOC_ID=$(op item list --categories "Document" --format json 2>/dev/null | jq -r '.[] | select(.title=="dotfiles-ssh-backup") | .id' || true)

  if [[ -n "$DOC_ID" ]]; then
    info "Found existing 'dotfiles-ssh-backup' in 1Password. Replacing..."
    op document edit "$DOC_ID" "$ARCHIVE_PATH" > /dev/null
    success "SSH backup updated in 1Password!"
  else
    info "Uploading new 'dotfiles-ssh-backup' to 1Password (Personal vault)..."
    op document create "$ARCHIVE_PATH" --title "dotfiles-ssh-backup" --vault "Personal" > /dev/null
    success "SSH backup securely stored in 1Password!"
  fi

  rm -f "$ARCHIVE_PATH"
  info "Done. Your private keys and config are safely stored."

elif [[ "$MODE" == "2" ]]; then
  # ── RESTORE ───────────────────────────────────────────────────────────────
  if [[ -d "$HOME/.ssh" ]] && [[ -n "$(ls -A "$HOME/.ssh" 2>/dev/null)" ]]; then
    warn "~/.ssh already contains files. Restoring will overwrite duplicates."
    read -r -p "$(echo -e "${YELLOW}  ? Continue? [y/N]: ${RESET}")" CONTINUE
    [[ ! "$CONTINUE" =~ ^[Yy]$ ]] && exit 0
  fi

  ARCHIVE_PATH="/tmp/dotfiles-ssh-backup.tar.gz"

  info "Looking for 'dotfiles-ssh-backup' in 1Password..."
  # Download the document
  if ! op document get "dotfiles-ssh-backup" --out-file "$ARCHIVE_PATH" > /dev/null 2>&1; then
    error "Could not find a document named 'dotfiles-ssh-backup' in 1Password."
  fi

  info "Extracting ~/.ssh archive..."
  # Extract back to ~ (tar preserves the .ssh folder and 600/700 permissions)
  tar -xzf "$ARCHIVE_PATH" -C "$HOME"
  
  # Ensure strict permissions just in case
  chmod 700 "$HOME/.ssh"
  find "$HOME/.ssh" -type f -exec chmod 600 {} +
  
  rm -f "$ARCHIVE_PATH"
  success "~/.ssh restored successfully!"
  
  # Try to add keys to agent
  if ! pgrep -u "$USER" ssh-agent &>/dev/null; then
    eval "$(ssh-agent -s)" &>/dev/null
  fi
  for key in "$HOME/.ssh"/id_*; do
    [[ -f "$key" && "${key##*.}" != "pub" ]] && ssh-add "$key" &>/dev/null || true
  done

else
  error "Invalid choice."
fi
