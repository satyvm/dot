#!/usr/bin/env bash
set -euo pipefail

readonly remote_user="ubuntu"
readonly remote_home="/home/ubuntu"
readonly dev_root="/home/ubuntu/dev"
readonly bootstrap_marker="$remote_home/.local/state/hermes-dev/bootstrap-v1"
readonly chezmoi_source="$remote_home/.local/share/chezmoi"
readonly chezmoi_config="$remote_home/.config/chezmoi/chezmoi.toml"

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
    die "$dev_root is not a bind mount; set SERVER_DEV_PATH=/home/ubuntu/dev"

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

write_chezmoi_config() {
  install -d -o ubuntu -g ubuntu -m 0700 "$(dirname "$chezmoi_config")"
  if [[ -s "$chezmoi_config" ]]; then
    return
  fi

  local git_name="${REMOTE_GIT_NAME:-Satyam}"
  local git_email="${REMOTE_GIT_EMAIL:-75127014+satyvm@users.noreply.github.com}"
  {
    printf '%s\n' '[data]'
    printf '%s\n' 'setupCli = true'
    printf '%s\n' 'setupDeveloper = true'
    printf '%s\n' 'setupAi = true'
    printf '%s\n' 'aiMode = "remote"'
    printf '%s\n' 'guiTier = "none"'
    printf '%s\n' 'setupMacos = false'
    printf '%s\n' 'setupLinuxHardening = false'
    printf '%s\n' 'setupSshKey = false'
    printf 'name = %s\n' "$(jq -Rn --arg value "$git_name" '$value')"
    printf 'email = %s\n' "$(jq -Rn --arg value "$git_email" '$value')"
  } >"$chezmoi_config"
  chown ubuntu:ubuntu "$chezmoi_config"
  chmod 0600 "$chezmoi_config"
}

bootstrap_dotfiles() {
  if [[ -e "$bootstrap_marker" ]]; then
    return
  fi

  local repository="${REMOTE_DOTFILES_REPO:-https://github.com/satyvm/dot.git}"
  if [[ ! -d "$chezmoi_source/.git" ]]; then
    if [[ -e "$chezmoi_source" ]]; then
      die "$chezmoi_source exists but is not a Git checkout"
    fi
    install -d -o ubuntu -g ubuntu -m 0755 "$(dirname "$chezmoi_source")"
    log "cloning dotfiles from $repository"
    run_as_ubuntu git clone --depth=1 "$repository" "$chezmoi_source"
  fi

  write_chezmoi_config
  log "applying remote-dev dotfiles"
  run_as_ubuntu chezmoi apply \
    --config "$chezmoi_config" \
    --source "$chezmoi_source"

  install -d -o ubuntu -g ubuntu -m 0755 "$(dirname "$bootstrap_marker")"
  run_as_ubuntu touch "$bootstrap_marker"
}

prepare_runtime_directories() {
  # The named home volume is root-owned on first creation. Change only the mount
  # root and directories owned by this service; never recurse into the dev bind.
  chown ubuntu:ubuntu "$remote_home"
  chmod 0755 "$remote_home"
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.hermes"
  install -d -o ubuntu -g ubuntu -m 0755 \
    "$remote_home/.hermes/webui" \
    "$remote_home/.local/state/hermes-dev"
}

main() {
  prepare_runtime_directories
  validate_development_mount
  install_ssh_host_keys
  install_authorized_key
  install_proxy_client_key
  bootstrap_dotfiles

  /usr/sbin/sshd -t
  exec /usr/bin/supervisord -c /etc/supervisor/conf.d/hermes-dev.conf
}

main "$@"
