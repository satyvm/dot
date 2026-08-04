#!/usr/bin/env bash
set -euo pipefail

readonly remote_user="ubuntu"
readonly remote_home="/home/ubuntu"
readonly dev_root="/home/ubuntu/dev"
readonly bootstrap_marker="$remote_home/.local/state/hermes-dev/bootstrap-v2"
readonly chezmoi_source="$remote_home/.local/share/chezmoi"
readonly chezmoi_config="$remote_home/.config/chezmoi/chezmoi.json"
readonly legacy_chezmoi_config="$remote_home/.config/chezmoi/chezmoi.toml"

log() {
  printf 'hermes-dev: %s\n' "$*"
}

die() {
  printf 'hermes-dev: error: %s\n' "$*" >&2
  exit 1
}

run_as_ubuntu() {
  runuser -u "$remote_user" -- env \
    HOME="$remote_home" \
    USER="$remote_user" \
    SHELL=/bin/zsh \
    PATH="$PATH" \
    "$@"
}

install_ssh_host_keys() {
  install -d -m 0700 /etc/ssh/host-keys
  if [[ ! -s /etc/ssh/host-keys/ssh_host_ed25519_key ]]; then
    ssh-keygen -q -t ed25519 \
      -f /etc/ssh/host-keys/ssh_host_ed25519_key -N ""
  fi
  if [[ ! -s /etc/ssh/host-keys/ssh_host_rsa_key ]]; then
    ssh-keygen -q -t rsa -b 4096 \
      -f /etc/ssh/host-keys/ssh_host_rsa_key -N ""
  fi
  chmod 0600 /etc/ssh/host-keys/*_key
  chmod 0644 /etc/ssh/host-keys/*.pub
}

install_authorized_key() {
  [[ -n "${DEV_SSH_PUBLIC_KEY:-}" ]] ||
    die "DEV_SSH_PUBLIC_KEY is required"
  [[ "$DEV_SSH_PUBLIC_KEY" == ssh-* ]] ||
    die "DEV_SSH_PUBLIC_KEY does not look like an OpenSSH public key"

  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.ssh"
  printf '%s\n' "$DEV_SSH_PUBLIC_KEY" >"$remote_home/.ssh/authorized_keys"
  chown ubuntu:ubuntu "$remote_home/.ssh/authorized_keys"
  chmod 0600 "$remote_home/.ssh/authorized_keys"
}

validate_development_mount() {
  mountpoint -q "$dev_root" ||
    die "$dev_root is not a bind mount; bind the server host's /home/ubuntu/dev to $dev_root"

  local expected_uid expected_gid actual_uid actual_gid
  expected_uid="$(id -u "$remote_user")"
  expected_gid="$(id -g "$remote_user")"
  actual_uid="$(stat -c '%u' "$dev_root")"
  actual_gid="$(stat -c '%g' "$dev_root")"
  if [[ "$actual_uid" != "$expected_uid" || "$actual_gid" != "$expected_gid" ]]; then
    die "$dev_root is owned by ${actual_uid}:${actual_gid}; expected ${expected_uid}:${expected_gid}. Fix ownership on the host instead of recursively changing it in the container."
  fi
}

install_proxy_client_key() {
  local shared_key="/run/platform-secrets/client-key"
  [[ -s "$shared_key" ]] ||
    die "shared CLIProxyAPI client key is missing: $shared_key"

  install -d -o ubuntu -g ubuntu -m 0700 \
    "$remote_home/.config/cli-proxy-api"
  install -o ubuntu -g ubuntu -m 0600 \
    "$shared_key" "$remote_home/.config/cli-proxy-api/client-key"
}

initialize_chezmoi_config() {
  install -d -o ubuntu -g ubuntu -m 0700 "$(dirname "$chezmoi_config")"

  if [[ -e "$legacy_chezmoi_config" ]]; then
    log "preserving the legacy hand-written chezmoi config"
    mv -f "$legacy_chezmoi_config" \
      "$legacy_chezmoi_config.pre-bootstrap-v2"
    chown ubuntu:ubuntu "$legacy_chezmoi_config.pre-bootstrap-v2"
    chmod 0600 "$legacy_chezmoi_config.pre-bootstrap-v2"
  fi

  local git_name="${REMOTE_GIT_NAME:-Satyam}"
  local git_email="${REMOTE_GIT_EMAIL:-75127014+satyvm@users.noreply.github.com}"

  log "initializing remote-dev chezmoi profile"
  run_as_ubuntu chezmoi init \
    --source "$chezmoi_source" \
    --config-path "$chezmoi_config" \
    --cache "$remote_home/.cache/chezmoi" \
    --no-tty \
    --force \
    --promptChoice "Machine preset=container" \
    --promptBool "Customize preset features=false" \
    --promptString "Git user name=$git_name" \
    --promptString "Git email address=$git_email"
}

setup_gitea_ssh() {
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.ssh"

  if [[ ! -s "$remote_home/.ssh/gitea_ai_ed25519" ]]; then
    log "generating dedicated Gitea SSH key"
    run_as_ubuntu ssh-keygen -q -t ed25519 \
      -f "$remote_home/.ssh/gitea_ai_ed25519" -N "" -C "ai@gitea.satyvm.com"
  fi

  local config_file="$remote_home/.ssh/config"
  if ! grep -q "Host gitea.satyvm.com" "$config_file" 2>/dev/null; then
    {
      printf '\nHost gitea.satyvm.com\n'
      printf '    HostName gitea.satyvm.com\n'
      printf '    User git\n'
      printf '    Port 22222\n'
      printf '    IdentityFile ~/.ssh/gitea_ai_ed25519\n'
      printf '    IdentitiesOnly yes\n'
    } >>"$config_file"
    chown ubuntu:ubuntu "$config_file"
    chmod 0600 "$config_file"
  fi
}

bootstrap_dotfiles() {
  if [[ -e "$bootstrap_marker" && (! -d "$chezmoi_source/.git" || ! -s "$chezmoi_config") ]]; then
    log "bootstrap marker is incomplete; rebuilding remote-dev dotfiles"
  fi

  local repository="${REMOTE_DOTFILES_REPO:-https://github.com/satyvm/dot.git}"
  if [[ ! -d "$chezmoi_source/.git" ]]; then
    if [[ -e "$chezmoi_source" ]]; then
      die "$chezmoi_source exists but is not a Git checkout"
    fi
    install -d -o ubuntu -g ubuntu -m 0755 "$(dirname "$chezmoi_source")"
    log "cloning dotfiles from $repository"
    run_as_ubuntu git clone --depth=1 "$repository" "$chezmoi_source"
  else
    log "refreshing the existing dotfiles checkout"
    run_as_ubuntu git -C "$chezmoi_source" pull --ff-only
  fi

  initialize_chezmoi_config
  log "applying remote-dev dotfiles"
  run_as_ubuntu chezmoi apply \
    --force \
    --no-tty \
    --refresh-externals=never \
    --config "$chezmoi_config" \
    --source "$chezmoi_source" \
    --cache "$remote_home/.cache/chezmoi"

  install -d -o ubuntu -g ubuntu -m 0755 "$(dirname "$bootstrap_marker")"
  run_as_ubuntu touch "$bootstrap_marker"
}

normalize_docker_home_ownership() {
  local uid gid home_marker hermes_marker
  uid="$(id -u "$remote_user")"
  gid="$(id -g "$remote_user")"
  home_marker="$remote_home/.local/state/hermes-dev/home-owner-${uid}-${gid}-v1"
  hermes_marker="$remote_home/.hermes/.owner-${uid}-${gid}-v1"

  if [[ ! -e "$home_marker" ]]; then
    log "normalizing Docker-managed home ownership"
    find "$remote_home" \
      -path "$dev_root" -prune -o \
      -path "$remote_home/.hermes" -prune -o \
      -exec chown -h "$remote_user:$remote_user" {} +
  fi

  if [[ ! -e "$hermes_marker" ]]; then
    find "$remote_home/.hermes" \
      -exec chown -h "$remote_user:$remote_user" {} +
  fi

  install -d -o ubuntu -g ubuntu -m 0755 \
    "$(dirname "$home_marker")"
  run_as_ubuntu touch "$home_marker"
  run_as_ubuntu touch "$hermes_marker"
}

prepare_runtime_directories() {
  # Both paths are Docker-managed volumes. The host bind at /home/ubuntu/dev is
  # explicitly pruned by normalize_docker_home_ownership.
  chown ubuntu:ubuntu "$remote_home"
  chmod 0755 "$remote_home"
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.hermes"
  normalize_docker_home_ownership

  install -d -o ubuntu -g ubuntu -m 0755 \
    "$remote_home/.cache" \
    "$remote_home/.config" \
    "$remote_home/.local" \
    "$remote_home/.local/bin" \
    "$remote_home/.local/share" \
    "$remote_home/.local/state"
  install -d -o ubuntu -g ubuntu -m 0700 \
    "$remote_home/.cache/chezmoi"
  install -d -o ubuntu -g ubuntu -m 0755 \
    "$remote_home/.hermes/webui" \
    "$remote_home/.local/state/hermes-dev"
  install -d -o ubuntu -g ubuntu -m 0777 /run/tea
}

main() {
  prepare_runtime_directories
  validate_development_mount
  install_ssh_host_keys
  install_authorized_key
  install_proxy_client_key
  setup_gitea_ssh
  bootstrap_dotfiles

  /usr/sbin/sshd -t
  exec /usr/bin/supervisord -c /etc/supervisor/conf.d/hermes-dev.conf
}

main "$@"
