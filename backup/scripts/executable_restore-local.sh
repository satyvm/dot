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
  local merge_only="${4:-false}"
  local src="$BACKUP_DIR/$src_sub"

  if [[ -e "$src" ]]; then
    echo "📦 $label"
    if [[ -e "$dest" ]] && [[ "$merge_only" != "true" ]]; then
      local timestamp
      timestamp=$(date +%Y%m%d_%H%M%S)
      local backup_dest="${dest}.bak_${timestamp}"
      echo "   ⚠️  Original exists, backing up to $backup_dest"
      mv "$dest" "$backup_dest"
    elif [[ -e "$dest" ]] && [[ "$merge_only" == "true" ]]; then
      local contents
      contents=$(ls -A "$dest" 2>/dev/null | grep -vE '^\.DS_Store$|^\.localized$' || true)
      if [[ -n "$contents" ]]; then
        echo "   ⚠️  Directory $dest is not empty. Skipping restore."
        return 0
      else
        echo "   ℹ️  Directory $dest is empty. Restoring into it."
      fi
    fi
    echo "   $src → $dest"
    mkdir -p "$(dirname "$dest")"
    rsync -aP "$src/" "$dest/"
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
  if defaults read com.sindresorhus.Velja &>/dev/null; then
    local_velja_bak="$HOME/Desktop/Velja_backup_$(date +%Y%m%d_%H%M%S).plist"
    echo "   ⚠️  Existing Velja preferences found, backing up to $local_velja_bak"
    defaults export com.sindresorhus.Velja "$local_velja_bak"
  fi
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

restore "Developer Directory" "Developer" "$HOME/Developer" true
restore "Downloads Directory" "Downloads" "$HOME/Downloads" true
restore "Pictures Directory" "Pictures" "$HOME/Pictures" true
restore "Study Directory" "Study" "$HOME/Study" true
restore "Work Directory" "Work" "$HOME/Work" true
restore "Documents Directory" "Documents" "$HOME/Documents" true
restore "Desktop Directory" "Desktop" "$HOME/Desktop" true

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Restore complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
