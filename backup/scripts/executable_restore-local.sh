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
if [[ ! -f "$BACKUP_DIR/BACKUP_COMPLETE" ]]; then
  printf '⚠️  No completion marker in %s. This may be a partial or older backup.\n' "$BACKUP_DIR" >&2
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
    fi
    echo "   $src → $dest"
    mkdir -p "$(dirname "$dest")"
    if [[ "$merge_only" == "true" ]]; then
      mkdir -p "$dest"
      local conflicts
      conflicts=$(rsync -aicn --existing --out-format='%n' "$src/" "$dest/")
      if [[ -n "$conflicts" ]]; then
        printf '   ⚠️  Existing files differ; kept local copies in %s:\n%s\n' "$dest" "$conflicts"
      fi
      rsync -aP --ignore-existing "$src/" "$dest/"
    else
      rsync -aP "$src/" "$dest/"
    fi
    echo "   ✅ Done"
  else
    echo "⚠️  $label — backup not found, skipping: $src"
  fi
}

# ── 1. Zen Browser ──────────────────────────────────────────────────
restore "Zen Browser" "zen" "$HOME/Library/Application Support/zen"

# ── 2. Google Chrome ────────────────────────────────────────────────
restore "Google Chrome" "chrome" "$HOME/Library/Application Support/Google/Chrome"

# ── 3. Helium Browser ───────────────────────────────────────────────
restore "Helium Browser" "helium" "$HOME/Library/Application Support/net.imput.helium"

# ── 4. T3 Code ───────────────────────────────────────────────────────
if [[ -d "$BACKUP_DIR/t3" ]]; then
  restore "T3 Code (~/.t3)" "t3" "$HOME/.t3"
elif [[ -d "$BACKUP_DIR/../common/.t3" ]]; then
  echo "ℹ️  Using legacy T3 Code backup in ../common/.t3"
  restore "T3 Code (~/.t3)" "../common/.t3" "$HOME/.t3"
else
  echo "⚠️  T3 Code backup not found"
fi

# ── 5. Zotero ────────────────────────────────────────────────────────
restore "Zotero (Data Directory)" "zotero/data" "$HOME/Zotero"

# ── 6. macOS app settings ────────────────────────────────────────────
restore "Velja container" "apps/velja/container" "$HOME/Library/Containers/com.sindresorhus.Velja"
restore "Shottr container" "apps/shottr/container" "$HOME/Library/Containers/cc.ffitch.shottr"
restore "Boring Notch container" "apps/boringnotch/container" "$HOME/Library/Containers/theboringteam.boringnotch"

for entry in \
  "ice:com.jordanbaird.Ice" \
  "velja:com.sindresorhus.Velja" \
  "shottr:cc.ffitch.shottr" \
  "dockdoor:com.ethanbills.DockDoor" \
  "boringnotch:theboringteam.boringnotch" \
  "hyperkey:com.knollsoft.Hyperkey"; do
  app="${entry%%:*}"
  domain="${entry#*:}"
  pref="$BACKUP_DIR/apps/preferences/$app.plist"
  if [[ "$app" == "velja" && ! -f "$pref" ]]; then
    pref="$BACKUP_DIR/velja/VeljaBackup.plist"
  fi
  if [[ -f "$pref" ]]; then
    plutil -lint "$pref" >/dev/null
    if defaults read "$domain" &>/dev/null; then
      pref_backup="$HOME/Library/Application Support/dotfiles-restore/preferences/${app}_$(date +%Y%m%d_%H%M%S).plist"
      mkdir -p "$(dirname "$pref_backup")"
      defaults export "$domain" "$pref_backup"
      echo "   ⚠️  Existing $app preferences saved to $pref_backup"
    fi
    defaults import "$domain" "$pref"
    echo "   ✅ Imported $app preferences"
  else
    echo "   ⚠️  No $app preferences backup found, skipping"
  fi
done

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
restore "Music Directory" "Music" "$HOME/Music" true
restore "Movies Directory" "Movies" "$HOME/Movies" true
restore "Screenshots Directory" "Screenshots" "$HOME/Screenshots" true

echo "ℹ️  Import Raycast settings from its manual .rayconfig export."

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Restore complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
