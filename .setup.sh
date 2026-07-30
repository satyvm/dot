#!/usr/bin/env bash
set -euo pipefail

log() {
  printf 'dotfiles: %s\n' "$*"
}

die() {
  printf 'dotfiles: error: %s\n' "$*" >&2
  exit 1
}

discover_brew() {
  local candidate
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return
  fi
  for candidate in \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew \
    /home/linuxbrew/.linuxbrew/bin/brew \
    "$HOME/.linuxbrew/bin/brew"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

activate_brew() {
  local brew_bin
  brew_bin="$(discover_brew)" || return 1
  eval "$("$brew_bin" shellenv)"
  export HOMEBREW_NO_ANALYTICS=1
}

run_apt() {
  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get "$@"
  else
    die "Debian/Ubuntu bootstrap requires root or sudo"
  fi
}

bootstrap_macos() {
  if ! xcode-select -p >/dev/null 2>&1; then
    log "requesting Xcode Command Line Tools"
    xcode-select --install ||
      die "Xcode Command Line Tools could not be requested; install them and rerun"
    until xcode-select -p >/dev/null 2>&1; do
      sleep 5
    done
  fi

  if ! activate_brew; then
    log "installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    activate_brew || die "Homebrew installed but could not be discovered"
  fi
  brew install age chezmoi
}

bootstrap_linux() {
  [[ "$(id -u)" -ne 0 ]] ||
    die "Linuxbrew does not support running as root; rerun as a regular sudo-capable user"
  [[ -r /etc/os-release ]] ||
    die "cannot identify Linux distribution because /etc/os-release is missing"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-unknown}" in
    debian|ubuntu) ;;
    *) die "unsupported Linux distribution ${ID:-unknown}; only Debian and Ubuntu are supported" ;;
  esac

  log "installing Debian/Ubuntu bootstrap dependencies"
  run_apt update
  run_apt install -y --no-install-recommends \
    age build-essential ca-certificates curl file git procps

  if ! activate_brew; then
    log "installing Linuxbrew for portable CLI packages"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    activate_brew || die "Linuxbrew installed but could not be discovered"
  fi

  if ! command -v chezmoi >/dev/null 2>&1; then
    brew install chezmoi
  fi
}

main() {
  export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$HOME/.linuxbrew/bin:$PATH"
  log "bootstrapping dotfiles"

  case "$(uname -s)" in
    Darwin) bootstrap_macos ;;
    Linux) bootstrap_linux ;;
    *) die "unsupported operating system $(uname -s)" ;;
  esac

  command -v chezmoi >/dev/null 2>&1 ||
    die "chezmoi is unavailable after bootstrap"

  if [[ -n "${DOTFILES_CONFIG:-}" ]]; then
    [[ -r "$DOTFILES_CONFIG" ]] ||
      die "DOTFILES_CONFIG is not readable: $DOTFILES_CONFIG"
    local source_dir="$HOME/.local/share/chezmoi"
    if [[ ! -d "$source_dir/.git" ]]; then
      if [[ -e "$source_dir" ]]; then
        die "$source_dir exists but is not a Git checkout"
      fi
      git clone https://github.com/satyvm/dot.git "$source_dir"
    fi
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi"
    local config_target="$config_dir/chezmoi.json"
    mkdir -p "$config_dir"
    install -m 0600 "$DOTFILES_CONFIG" "$config_target"
    log "applying unattended config $config_target"
    chezmoi apply --config "$config_target" --source "$source_dir"
    log "complete"
    return
  fi

  if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
    log "refreshing and applying the existing source state"
    chezmoi update
  else
    log "initializing satyvm/dot"
    chezmoi init --apply satyvm/dot
  fi
  log "complete"
}

main "$@"
