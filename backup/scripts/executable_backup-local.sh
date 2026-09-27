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
if [[ "$EXT_DRIVE" != /Volumes/* ]] ||
  [[ "$(stat -f %d "$EXT_DRIVE")" == "$(stat -f %d /Volumes)" ]]; then
  echo "❌ Destination is not a mounted volume under /Volumes: $EXT_DRIVE"
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
  local required="${4:-false}"

  if [[ -d "$src" ]]; then
    echo "📦 $label"
    echo "   $src → $dest"
    mkdir -p "$(dirname "$dest")"
    rsync -aP --delete "$src/" "$dest/"
    local differences
    differences=$(rsync -aicn --delete --out-format='%i %n' "$src/" "$dest/")
    if [[ -n "$differences" ]]; then
      printf '❌ Checksum verification failed for %s:\n%s\n' "$label" "$differences" >&2
      return 1
    fi
    echo "   ✅ Copied and checksum verified"
  elif [[ "$required" == "true" ]]; then
    printf '❌ Required source not found: %s\n' "$src" >&2
    return 1
  else
    echo "⚠️  $label — source not found, skipping: $src"
  fi
}

# ── 1. Zen Browser ──────────────────────────────────────────────────
backup "Zen Browser" \
  "$HOME/Library/Application Support/zen" \
  "zen" true

# ── 2. Google Chrome ────────────────────────────────────────────────
backup "Google Chrome" \
  "$HOME/Library/Application Support/Google/Chrome" \
  "chrome"

# ── 3. Helium Browser ───────────────────────────────────────────────
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
  backup "Helium Browser" "$HELIUM_PATH" "helium" true
else
  echo "❌ Helium Browser — no profile directory found" >&2
  exit 1
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

# ── 6. macOS app settings ────────────────────────────────────────────
backup "Raycast data" "$HOME/Library/Application Support/com.raycast.macos" "apps/raycast/support"
backup "Raycast shared data" "$HOME/Library/Application Support/com.raycast.shared" "apps/raycast/shared"
backup "Raycast group data" "$HOME/Library/Group Containers/SY64MV22J9.com.raycast.macos.shared" "apps/raycast/group"
backup "Velja container" "$HOME/Library/Containers/com.sindresorhus.Velja" "apps/velja/container"
backup "Shottr container" "$HOME/Library/Containers/cc.ffitch.shottr" "apps/shottr/container"
backup "Boring Notch container" "$HOME/Library/Containers/theboringteam.boringnotch" "apps/boringnotch/container"

for entry in \
  "raycast:com.raycast.macos" \
  "ice:com.jordanbaird.Ice" \
  "velja:com.sindresorhus.Velja" \
  "shottr:cc.ffitch.shottr" \
  "dockdoor:com.ethanbills.DockDoor" \
  "boringnotch:theboringteam.boringnotch" \
  "hyperkey:com.knollsoft.Hyperkey"; do
  app="${entry%%:*}"
  domain="${entry#*:}"
  if defaults read "$domain" &>/dev/null; then
    pref="$BACKUP_DIR/apps/preferences/$app.plist"
    mkdir -p "$(dirname "$pref")"
    defaults export "$domain" "$pref"
    plutil -lint "$pref" >/dev/null
    echo "   ✅ Exported $app preferences"
  else
    echo "   ⚠️  No $app preferences found, skipping"
  fi
done

# ── 7. Personal Directories ──────────────────────────────────────────
backup "SSH Keys (~/.ssh)" "$HOME/.ssh" "ssh" true
backup "Developer Directory" "$HOME/Developer" "Developer" true
backup "Downloads Directory" "$HOME/Downloads" "Downloads" true
backup "Pictures Directory" "$HOME/Pictures" "Pictures"
backup "Study Directory" "$HOME/Study" "Study"
backup "Work Directory" "$HOME/Work" "Work"
backup "Documents Directory" "$HOME/Documents" "Documents" true
backup "Desktop Directory" "$HOME/Desktop" "Desktop"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Backup and checksum verification complete!"
echo "  📂 $BACKUP_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
du -sh "$BACKUP_DIR" 2>/dev/null || true
