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
rm -f "$BACKUP_DIR/BACKUP_COMPLETE"
trap 'status=$?; if ((status != 0)); then printf "❌ Backup incomplete: %s. No final omission report was produced; do not erase the Mac or use this as a complete restore source.\n" "$BACKUP_DIR" >&2; fi' EXIT
not_included=()

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
    not_included+=("$label ($src): source not found")
  fi
}

# ── 1. Personal files ────────────────────────────────────────────────
backup "Documents Directory" "$HOME/Documents" "Documents" true
backup "Downloads Directory" "$HOME/Downloads" "Downloads" true
backup "Desktop Directory" "$HOME/Desktop" "Desktop" true
backup "SSH Keys (~/.ssh)" "$HOME/.ssh" "ssh" true
backup "Developer Directory" "$HOME/Developer" "Developer" true
backup "Pictures Directory" "$HOME/Pictures" "Pictures"
backup "Music Directory" "$HOME/Music" "Music"
backup "Movies Directory" "$HOME/Movies" "Movies"
backup "Screenshots Directory" "$HOME/Screenshots" "Screenshots"
backup "Study Directory" "$HOME/Study" "Study"
backup "Work Directory" "$HOME/Work" "Work"

# ── 2. Zen Browser ──────────────────────────────────────────────────
backup "Zen Browser" \
  "$HOME/Library/Application Support/zen" \
  "zen" true

# ── 3. Google Chrome ────────────────────────────────────────────────
backup "Google Chrome" \
  "$HOME/Library/Application Support/Google/Chrome" \
  "chrome"

# ── 4. Helium Browser ───────────────────────────────────────────────
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

# ── 5. T3 Code ───────────────────────────────────────────────────────
backup "T3 Code (~/.t3)" "$HOME/.t3" "t3"

# ── 6. Zotero ────────────────────────────────────────────────────────
# Data directory — try the default location; user may have moved it
ZOTERO_DATA="$HOME/Zotero"
if [[ -d "$ZOTERO_DATA" ]]; then
  backup "Zotero (Data Directory)" "$ZOTERO_DATA" "zotero/data"
else
  echo "⚠️  Zotero Data Directory — default location not found: $ZOTERO_DATA"
  echo "   ℹ️  Check Settings > Advanced > Files and Folders in Zotero for the actual path."
  not_included+=("Zotero data ($ZOTERO_DATA): source not found; check Zotero's configured data location")
fi

# ── 7. macOS app settings ────────────────────────────────────────────
backup "Velja container" "$HOME/Library/Containers/com.sindresorhus.Velja" "apps/velja/container"
backup "Shottr container" "$HOME/Library/Containers/cc.ffitch.shottr" "apps/shottr/container"
backup "Boring Notch container" "$HOME/Library/Containers/theboringteam.boringnotch" "apps/boringnotch/container"

for entry in \
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
    not_included+=("$app preferences ($domain): not found")
  fi
done

echo ""
echo "📦 Raycast settings require a manual export."
echo "   In Raycast, open Settings > Advanced > Export and save a .rayconfig file."
echo "   Keep its export password separately. The script will copy the file to the SSD."
raycast_export=""
if [[ -t 0 ]]; then
  while true; do
    read -r -p "Path to the exported .rayconfig file (Enter to skip): " raycast_export || raycast_export=""
    [[ -z "$raycast_export" ]] && break
    if [[ -f "$raycast_export" && "$raycast_export" == *.rayconfig ]]; then
      break
    fi
    echo "   ⚠️  Enter an existing .rayconfig file, or press Enter to skip."
  done
else
  echo "   ⚠️  No interactive terminal; Raycast export skipped."
fi

if [[ -n "$raycast_export" ]]; then
  raycast_dest="$BACKUP_DIR/manual/raycast/$(basename "$raycast_export")"
  mkdir -p "$(dirname "$raycast_dest")"
  if [[ "$raycast_export" != "$raycast_dest" ]]; then
    rsync -aP "$raycast_export" "$raycast_dest"
  fi
  if [[ -n "$(rsync -aicn --out-format='%i %n' "$raycast_export" "$raycast_dest")" ]]; then
    printf '❌ Raycast export checksum verification failed: %s\n' "$raycast_dest" >&2
    exit 1
  fi
  echo "   ✅ Raycast export copied and checksum verified: $raycast_dest"
else
  not_included+=("Raycast settings: no .rayconfig export selected during this run")
fi

date -u +'%Y-%m-%dT%H:%M:%SZ' > "$BACKUP_DIR/BACKUP_COMPLETE"
trap - EXIT

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Backup and checksum verification complete!"
echo "  📂 $BACKUP_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
du -sh "$BACKUP_DIR" 2>/dev/null || true
echo ""
echo "Not included in this backup:"
for item in "${not_included[@]}"; do
  printf '  - %s\n' "$item"
done
printf '  - %s\n' \
  'Gemini (~/.gemini): not copied by this run' \
  'Live Raycast app data: not copied by this run; use the manual .rayconfig export' \
  'macOS Keychain and unlisted app data' \
  'Chezmoi saved answers (~/.config/chezmoi/chezmoi.json)' \
  'Other home folders not explicitly listed by this script'

for old_path in gemini apps/raycast; do
  if [[ -e "$BACKUP_DIR/$old_path" ]]; then
    printf '⚠️  Older excluded data remains in this reused snapshot: %s\n' "$BACKUP_DIR/$old_path"
  fi
done
if [[ -z "$raycast_export" && -d "$BACKUP_DIR/manual/raycast" ]]; then
  printf '⚠️  Previous Raycast exports may remain in %s; none was selected this run.\n' "$BACKUP_DIR/manual/raycast"
fi
