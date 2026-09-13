#!/usr/bin/env bash
set -euo pipefail

readonly remote_user="ubuntu"
readonly remote_home="/home/ubuntu"
readonly dev_root="/home/ubuntu/dev"
readonly chezmoi_source="$remote_home/.local/share/chezmoi"
readonly chezmoi_config="$remote_home/.config/chezmoi/chezmoi.json"
readonly bootstrap_marker="$remote_home/.local/state/t3code/bootstrap-v1"

log() { printf 't3code: %s\n' "$*"; }
die() { printf 't3code: error: %s\n' "$*" >&2; exit 1; }

run_as_ubuntu() {
  runuser -u "$remote_user" -- env \
    HOME="$remote_home" USER="$remote_user" SHELL=/bin/zsh PATH="$PATH" "$@"
}

prepare_runtime_directories() {
  chown ubuntu:ubuntu "$remote_home"
  chmod 0755 "$remote_home"
  install -d -o ubuntu -g ubuntu -m 0755 \
    "$remote_home/.cache" "$remote_home/.config" "$remote_home/.local" \
    "$remote_home/.local/bin" "$remote_home/.local/share" \
    "$remote_home/.local/state" "$remote_home/.local/state/t3code" \
    "$remote_home/.npm-global" "$remote_home/.t3"
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.cache/chezmoi"

  # The Docker-managed home may carry image-layer ownership after a rebuild.
  # The bind mount is pruned: its ownership is the host's business.
  local marker="$remote_home/.local/state/t3code/home-owner-v1"
  if [[ ! -e "$marker" ]]; then
    log "normalizing Docker-managed home ownership"
    find "$remote_home" -path "$dev_root" -prune -o \
      -exec chown -h "$remote_user:$remote_user" {} +
    run_as_ubuntu touch "$marker"
  fi
}

validate_development_mount() {
  mountpoint -q "$dev_root" ||
    die "$dev_root is not a bind mount; bind the host's /home/ubuntu/dev to $dev_root"
  local expected_uid expected_gid actual_uid actual_gid
  expected_uid="$(id -u "$remote_user")"; expected_gid="$(id -g "$remote_user")"
  actual_uid="$(stat -c '%u' "$dev_root")"; actual_gid="$(stat -c '%g' "$dev_root")"
  if [[ "$actual_uid" != "$expected_uid" || "$actual_gid" != "$expected_gid" ]]; then
    die "$dev_root is owned by ${actual_uid}:${actual_gid}; expected ${expected_uid}:${expected_gid}. Fix ownership on the host rather than recursively changing it here."
  fi
}

install_ssh_host_keys() {
  install -d -m 0700 /etc/ssh/host-keys
  if [[ ! -s /etc/ssh/host-keys/ssh_host_ed25519_key ]]; then
    ssh-keygen -q -t ed25519 -f /etc/ssh/host-keys/ssh_host_ed25519_key -N ""
  fi
  chmod 0600 /etc/ssh/host-keys/*_key
  chmod 0644 /etc/ssh/host-keys/*.pub
}

install_authorized_key() {
  [[ -n "${DEV_SSH_PUBLIC_KEY:-}" ]] || die "DEV_SSH_PUBLIC_KEY is required"
  [[ "$DEV_SSH_PUBLIC_KEY" == ssh-* ]] ||
    die "DEV_SSH_PUBLIC_KEY does not look like an OpenSSH public key"
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.ssh"
  printf '%s\n' "$DEV_SSH_PUBLIC_KEY" >"$remote_home/.ssh/authorized_keys"
  chown ubuntu:ubuntu "$remote_home/.ssh/authorized_keys"
  chmod 0600 "$remote_home/.ssh/authorized_keys"
}

install_gateway_client_key() {
  local shared_key="/run/platform-secrets/client-key"
  if [[ ! -s "$shared_key" ]]; then
    log "no gateway client key present; ax will run without a model gateway"
    return 0
  fi
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.config/cli-proxy-api"
  install -o ubuntu -g ubuntu -m 0600 "$shared_key" \
    "$remote_home/.config/cli-proxy-api/client-key"
}

setup_forge_ssh() {
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.ssh"
  local key
  for key in gitea_ai_ed25519 github_ai_ed25519; do
    if [[ ! -s "$remote_home/.ssh/$key" ]]; then
      log "generating $key"
      run_as_ubuntu ssh-keygen -q -t ed25519 -f "$remote_home/.ssh/$key" -N "" -C "t3code-$key"
    fi
  done

  local config_file="$remote_home/.ssh/config"
  if ! grep -q "Host gitea.satyvm.com" "$config_file" 2>/dev/null; then
    {
      printf '\nHost gitea.satyvm.com\n'
      printf '    HostName gitea.satyvm.com\n    User git\n    Port 22222\n'
      printf '    IdentityFile ~/.ssh/gitea_ai_ed25519\n    IdentitiesOnly yes\n'
    } >>"$config_file"
  fi
  if ! grep -q "Host github.com" "$config_file" 2>/dev/null; then
    {
      printf '\nHost github.com\n'
      printf '    HostName github.com\n    User git\n'
      printf '    IdentityFile ~/.ssh/github_ai_ed25519\n    IdentitiesOnly yes\n'
    } >>"$config_file"
  fi
  chown ubuntu:ubuntu "$config_file"
  chmod 0600 "$config_file"
}

bootstrap_dotfiles() {
  local repository="${REMOTE_DOTFILES_REPO:-https://github.com/satyvm/dot.git}"
  if [[ ! -d "$chezmoi_source/.git" ]]; then
    [[ -e "$chezmoi_source" ]] && die "$chezmoi_source exists but is not a Git checkout"
    install -d -o ubuntu -g ubuntu -m 0755 "$(dirname "$chezmoi_source")"
    log "cloning dotfiles from $repository"
    run_as_ubuntu git clone --depth=1 "$repository" "$chezmoi_source"
  else
    log "refreshing the dotfiles checkout"
    run_as_ubuntu git -C "$chezmoi_source" pull --ff-only ||
      log "warning: fast-forward pull failed; applying the existing checkout"
  fi

  install -d -o ubuntu -g ubuntu -m 0700 "$(dirname "$chezmoi_config")"
  log "regenerating the t3 chezmoi profile"
  run_as_ubuntu chezmoi init \
    --source "$chezmoi_source" --config-path "$chezmoi_config" \
    --cache "$remote_home/.cache/chezmoi" --no-tty --force \
    --promptChoice "Machine preset=t3" \
    --promptBool "Customize preset features=false" \
    --promptString "Git user name=${REMOTE_GIT_NAME:-Satyam}" \
    --promptString "Git email address=${REMOTE_GIT_EMAIL:-75127014+satyvm@users.noreply.github.com}"

  log "applying dotfiles"
  run_as_ubuntu chezmoi apply --force --no-tty --refresh-externals=never \
    --config "$chezmoi_config" --source "$chezmoi_source" \
    --cache "$remote_home/.cache/chezmoi"
  run_as_ubuntu touch "$bootstrap_marker"
}

register_projects() {
  # The GUI cannot add projects to a remote environment; only the CLI can.
  local project
  for project in "$dev_root"/*/; do
    [[ -d "$project" ]] || continue
    run_as_ubuntu t3 project add "${project%/}" >/dev/null 2>&1 || true
  done
}

main() {
  prepare_runtime_directories
  validate_development_mount
  install_ssh_host_keys
  install_authorized_key
  install_gateway_client_key
  setup_forge_ssh
  bootstrap_dotfiles
  register_projects
  /usr/sbin/sshd -t
  exec /usr/bin/supervisord -c /etc/supervisor/conf.d/t3code.conf
}

main "$@"
