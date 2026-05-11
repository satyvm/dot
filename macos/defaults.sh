#!/usr/bin/env bash
# =============================================================================
# defaults.sh — macOS system preferences
# Idempotent: safe to re-run at any time
# =============================================================================

set -euo pipefail

echo "→ Applying macOS defaults..."

# ── General ───────────────────────────────────────────────────────────────────
# Enable key repeat (essential for Neovim navigation)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Dark mode
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# Show all file extensions in Finder
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Use metric units
defaults write NSGlobalDomain AppleMeasurementUnits -string "Centimeters"
defaults write NSGlobalDomain AppleMetricUnits -bool true

# ── Finder ────────────────────────────────────────────────────────────────────
# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show status bar and path bar
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowPathbar -bool true

# Default to list view
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Show full POSIX path in title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Disable .DS_Store on network and USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# ── Dock ──────────────────────────────────────────────────────────────────────
# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.3

# Minimise windows using the Scale effect
defaults write com.apple.dock mineffect -string "scale"

# Don't show recent apps in Dock
defaults write com.apple.dock show-recents -bool false

# ── Trackpad ─────────────────────────────────────────────────────────────────
# Enable tap-to-click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true

# ── Keyboard ──────────────────────────────────────────────────────────────────
# Full keyboard access in dialogs (Tab through all controls)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# ── Screenshots ───────────────────────────────────────────────────────────────
mkdir -p ~/Desktop/Screenshots
defaults write com.apple.screencapture location -string "~/Desktop/Screenshots"
defaults write com.apple.screencapture type -string "png"
defaults write com.apple.screencapture disable-shadow -bool true

# ── Activity Monitor ──────────────────────────────────────────────────────────
# Show all processes
defaults write com.apple.ActivityMonitor ShowCategory -int 0
# Sort by CPU usage
defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
defaults write com.apple.ActivityMonitor SortDirection -int 0

# ── Restart affected apps ─────────────────────────────────────────────────────
for app in "Finder" "Dock" "SystemUIServer"; do
  killall "$app" &>/dev/null || true
done

echo "✓ macOS defaults applied (some changes require a logout/restart)"
