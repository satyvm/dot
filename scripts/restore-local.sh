#!/usr/bin/env bash
#
# restore-local.sh — Restore local app data from an external drive backup.
#
# Usage:
#   ./restore-local.sh /Volumes/MyDrive/mac_backup/local_310526
#
set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "❌ Please provide the path to the specific backup folder."
  echo "Usage: $0 /Volumes/MyDrive/mac_backup/local_310526"
  exit 1
fi

BACKUP_DIR="$1"

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "❌ Backup directory not found: $BACKUP_DIR"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Restore source: $BACKUP_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Helper ───────────────────────────────────────────────────────────
restore() {
  local label="$1"
  local src_sub="$2"
  local dest="$3"
  local src="$BACKUP_DIR/$src_sub"

  if [[ -e "$src" ]]; then
    echo "📦 $label"
    echo "   $src → $dest"
    mkdir -p "$(dirname "$dest")"
    rsync -a "$src/" "$dest/"
    echo "   ✅ Done"
  else
    echo "⚠️  $label — backup not found, skipping: $src"
  fi
}

# ── 1. Zen Browser ──────────────────────────────────────────────────
restore "Zen Browser" "zen" "$HOME/Library/Application Support/zen"

# ── 2. Helium Browser ───────────────────────────────────────────────
restore "Helium Browser" "helium" "$HOME/Library/Application Support/net.imput.helium"

# ── 4. Gemini / Antigravity ─────────────────────────────────────────
restore "Gemini / Antigravity (~/.gemini)" "gemini" "$HOME/.gemini"

# ── 5. Zotero ────────────────────────────────────────────────────────
restore "Zotero (Data Directory)" "zotero/data" "$HOME/Zotero"

# ── 6. Velja ─────────────────────────────────────────────────────────
echo "📦 Velja (preferences plist)"
VELJA_PLIST="$BACKUP_DIR/velja/VeljaBackup.plist"
if [[ -f "$VELJA_PLIST" ]]; then
  defaults import com.sindresorhus.Velja "$VELJA_PLIST"
  echo "   ✅ Imported from $VELJA_PLIST"
else
  echo "   ⚠️  No Velja preferences backup found, skipping"
fi

# ── 7. Personal Directories ──────────────────────────────────────────
restore "SSH Keys (~/.ssh)" "ssh" "$HOME/.ssh"
# Ensure secure permissions for ssh keys
if [[ -d "$HOME/.ssh" ]]; then
  chmod 700 "$HOME/.ssh"
  find "$HOME/.ssh" -type f -exec chmod 600 {} \;
fi

restore "Developer Directory" "Developer" "$HOME/Developer"
restore "Downloads Directory" "Downloads" "$HOME/Downloads"
restore "Pictures Directory" "Pictures" "$HOME/Pictures"
restore "Study Directory" "Study" "$HOME/Study"
restore "Work Directory" "Work" "$HOME/Work"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Restore complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
