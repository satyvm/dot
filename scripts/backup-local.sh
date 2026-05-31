#!/usr/bin/env bash
#
# backup-local.sh — Back up local app data to an external drive.
#
# Usage:
#   ./backup-local.sh                     # auto-detects the first external volume
#   ./backup-local.sh /Volumes/MyDrive    # use a specific external drive
#
set -euo pipefail

# ── Resolve external drive ───────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
  EXT_DRIVE="$1"
else
  # Auto-detect: pick the first non-system volume under /Volumes
  EXT_DRIVE=""
  for vol in /Volumes/*; do
    [[ "$vol" == "/Volumes/Macintosh HD" ]] && continue
    [[ "$vol" == "/Volumes/Macintosh HD - Data" ]] && continue
    if [[ -d "$vol" ]]; then
      EXT_DRIVE="$vol"
      break
    fi
  done
  if [[ -z "$EXT_DRIVE" ]]; then
    echo "❌ No external drive detected. Plug one in or pass the path as an argument."
    exit 1
  fi
fi

if [[ ! -d "$EXT_DRIVE" ]]; then
  echo "❌ Drive not found: $EXT_DRIVE"
  exit 1
fi

DATE_STAMP=$(date +"%d%m%y")
BACKUP_DIR="$EXT_DRIVE/mac_backup/local_${DATE_STAMP}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Backup destination: $BACKUP_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$BACKUP_DIR"

# ── Helper ───────────────────────────────────────────────────────────
backup() {
  local label="$1"
  local src="$2"
  local dest="$BACKUP_DIR/$3"

  if [[ -e "$src" ]]; then
    echo "📦 $label"
    echo "   $src → $dest"
    mkdir -p "$(dirname "$dest")"
    rsync -a --delete "$src/" "$dest/"
    echo "   ✅ Done"
  else
    echo "⚠️  $label — source not found, skipping: $src"
  fi
}

# ── 1. Zen Browser ──────────────────────────────────────────────────
backup "Zen Browser" \
  "$HOME/Library/Application Support/zen" \
  "zen"

# ── 2. Helium Browser ───────────────────────────────────────────────
# Check both known paths
HELIUM_PATH=""
for candidate in \
  "$HOME/Library/Application Support/net.imput.helium" \
  "$HOME/Library/Application Support/helium"; do
  if [[ -d "$candidate" ]]; then
    HELIUM_PATH="$candidate"
    break
  fi
done

if [[ -n "$HELIUM_PATH" ]]; then
  backup "Helium Browser" "$HELIUM_PATH" "helium"
else
  echo "⚠️  Helium Browser — no profile directory found, skipping"
fi

# ── 4. Antigravity / Gemini ─────────────────────────────────────────
backup "Gemini / Antigravity (~/.gemini)" \
  "$HOME/.gemini" \
  "gemini"

# ── 5. Zotero ────────────────────────────────────────────────────────
# Data directory — try the default location; user may have moved it
ZOTERO_DATA="$HOME/Zotero"
if [[ -d "$ZOTERO_DATA" ]]; then
  backup "Zotero (Data Directory)" "$ZOTERO_DATA" "zotero/data"
else
  echo "⚠️  Zotero Data Directory — default location not found: $ZOTERO_DATA"
  echo "   ℹ️  Check Settings > Advanced > Files and Folders in Zotero for the actual path."
fi

# ── 6. Velja ─────────────────────────────────────────────────────────
echo "📦 Velja (preferences plist)"
VELJA_PLIST="$BACKUP_DIR/velja/VeljaBackup.plist"
mkdir -p "$BACKUP_DIR/velja"
if defaults read com.sindresorhus.Velja &>/dev/null; then
  defaults export com.sindresorhus.Velja "$VELJA_PLIST"
  echo "   ✅ Exported to $VELJA_PLIST"
else
  echo "   ⚠️  No Velja preferences found, skipping"
fi

# ── 7. Personal Directories ──────────────────────────────────────────
backup "SSH Keys (~/.ssh)" "$HOME/.ssh" "ssh"
backup "Developer Directory" "$HOME/Developer" "Developer"
backup "Downloads Directory" "$HOME/Downloads" "Downloads"
backup "Pictures Directory" "$HOME/Pictures" "Pictures"
backup "Study Directory" "$HOME/Study" "Study"
backup "Work Directory" "$HOME/Work" "Work"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Backup complete!"
echo "  📂 $BACKUP_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
du -sh "$BACKUP_DIR" 2>/dev/null || true
