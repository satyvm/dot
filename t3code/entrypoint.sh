#!/usr/bin/env bash
set -euo pipefail

readonly remote_user="ubuntu"
readonly remote_home="/home/ubuntu"
readonly dev_root="/home/ubuntu/dev"
readonly chezmoi_source="$remote_home/.local/share/chezmoi"
readonly chezmoi_config="$remote_home/.config/chezmoi/chezmoi.json"
readonly bootstrap_marker="$remote_home/.local/state/t3code/bootstrap-v1"
readonly failure_log="$remote_home/.local/state/t3code/bootstrap-failures.log"

log() { printf 't3code: %s\n' "$*"; }
die() { printf 't3code: error: %s\n' "$*" >&2; return 1; }

# This container is the only way in. A failed bootstrap step must degrade the
# environment, never withhold the shell needed to repair it, so every step runs
# through `attempt` and the entrypoint always reaches supervisord.
failed_steps=()
# NOTE: bash disables errexit for the whole duration of a call made in a
# condition context, and that suppression is inherited by subshells. Every step
# function below must therefore propagate failure explicitly with `|| return 1`
# rather than relying on `set -e`.
attempt() {
  local label="$1"; shift
  if "$@"; then
    return 0
  fi
  log "STEP FAILED: $label (continuing so the container stays reachable)"
  failed_steps+=("$label")
  return 0
}

run_as_ubuntu() {
  runuser -u "$remote_user" -- env \
    HOME="$remote_home" USER="$remote_user" SHELL=/bin/zsh PATH="$PATH" "$@"
}

prepare_runtime_directories() {
  chown ubuntu:ubuntu "$remote_home" || return 1
  chmod 0755 "$remote_home" || return 1
  install -d -o ubuntu -g ubuntu -m 0755 \
    "$remote_home/.cache" "$remote_home/.config" "$remote_home/.local" \
    "$remote_home/.local/bin" "$remote_home/.local/share" \
    "$remote_home/.local/state" "$remote_home/.local/state/t3code" \
    "$remote_home/.npm-global" "$remote_home/.t3" || return 1
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.cache/chezmoi" || return 1

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
    { die "$dev_root is not a bind mount; bind the host's /home/ubuntu/dev to $dev_root"; return 1; }
  local expected_uid expected_gid actual_uid actual_gid
  expected_uid="$(id -u "$remote_user")" || return 1
  expected_gid="$(id -g "$remote_user")" || return 1
  actual_uid="$(stat -c '%u' "$dev_root")" || return 1
  actual_gid="$(stat -c '%g' "$dev_root")" || return 1
  if [[ "$actual_uid" != "$expected_uid" || "$actual_gid" != "$expected_gid" ]]; then
    die "$dev_root is owned by ${actual_uid}:${actual_gid}; expected ${expected_uid}:${expected_gid}. Fix ownership on the host rather than recursively changing it here."
    return 1
  fi
}

install_ssh_host_keys() {
  install -d -m 0700 /etc/ssh/host-keys
  if [[ ! -s /etc/ssh/host-keys/ssh_host_ed25519_key ]]; then
    ssh-keygen -q -t ed25519 -f /etc/ssh/host-keys/ssh_host_ed25519_key -N "" || return 1
  fi
  chmod 0600 /etc/ssh/host-keys/*_key
  chmod 0644 /etc/ssh/host-keys/*.pub
}

install_authorized_key() {
  # Not fatal: without it SSH is unavailable, but T3 Code pairing still is.
  [[ -n "${DEV_SSH_PUBLIC_KEY:-}" ]] ||
    { die "DEV_SSH_PUBLIC_KEY is unset; SSH access will be unavailable"; return 1; }
  [[ "$DEV_SSH_PUBLIC_KEY" == ssh-* ]] ||
    { die "DEV_SSH_PUBLIC_KEY does not look like an OpenSSH public key"; return 1; }
  install -d -o ubuntu -g ubuntu -m 0700 "$remote_home/.ssh" || return 1
  printf '%s\n' "$DEV_SSH_PUBLIC_KEY" >"$remote_home/.ssh/authorized_keys" || return 1
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
      run_as_ubuntu ssh-keygen -q -t ed25519 -f "$remote_home/.ssh/$key" -N "" -C "t3code-$key" || return 1
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

ensure_npm_agents() {
  # The t3-home volume masks image content under /home/ubuntu, so packages
  # baked into the image are invisible once the volume exists. Reinstall only
  # what is missing; a no-op on a healthy container.
  local missing=() spec bin pkg
  for spec in "t3:t3@latest" \
              "claude:@anthropic-ai/claude-code@latest" \
              "codex:@openai/codex@latest"; do
    bin="${spec%%:*}"; pkg="${spec#*:}"
    [[ -x "$remote_home/.npm-global/bin/$bin" ]] || missing+=("$pkg")
  done
  if ((${#missing[@]})); then
    log "reinstalling npm-provided agents: ${missing[*]}"
    run_as_ubuntu npm install -g "${missing[@]}" || return 1
  fi
}

bootstrap_dotfiles() {
  local repository="${REMOTE_DOTFILES_REPO:-https://github.com/satyvm/dot.git}"
  if [[ ! -d "$chezmoi_source/.git" ]]; then
    if [[ -e "$chezmoi_source" ]]; then
      die "$chezmoi_source exists but is not a Git checkout"
      return 1
    fi
    install -d -o ubuntu -g ubuntu -m 0755 "$(dirname "$chezmoi_source")" || return 1
    log "cloning dotfiles from $repository"
    run_as_ubuntu git clone --depth=1 "$repository" "$chezmoi_source" || return 1
  else
    log "refreshing the dotfiles checkout"
    run_as_ubuntu git -C "$chezmoi_source" pull --ff-only ||
      log "warning: fast-forward pull failed; applying the existing checkout"
  fi

  install -d -o ubuntu -g ubuntu -m 0700 "$(dirname "$chezmoi_config")" || return 1
  log "regenerating the t3 chezmoi profile"
  run_as_ubuntu chezmoi init \
    --source "$chezmoi_source" --config-path "$chezmoi_config" \
    --cache "$remote_home/.cache/chezmoi" --no-tty --force \
    --promptChoice "Machine preset=t3" \
    --promptBool "Customize preset features=false" \
    --promptString "Git user name=${REMOTE_GIT_NAME:-Satyam}" \
    --promptString "Git email address=${REMOTE_GIT_EMAIL:-75127014+satyvm@users.noreply.github.com}" || return 1

  log "applying dotfiles"
  run_as_ubuntu chezmoi apply --force --no-tty --refresh-externals=never \
    --config "$chezmoi_config" --source "$chezmoi_source" \
    --cache "$remote_home/.cache/chezmoi" || return 1
  run_as_ubuntu touch "$bootstrap_marker" || return 1
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
  attempt "prepare runtime directories" prepare_runtime_directories
  attempt "validate the development mount" validate_development_mount
  attempt "install SSH host keys" install_ssh_host_keys
  attempt "install the authorized key" install_authorized_key
  attempt "install the gateway client key" install_gateway_client_key
  attempt "configure forge SSH" setup_forge_ssh
  attempt "reconcile npm-provided agents" ensure_npm_agents
  attempt "bootstrap dotfiles" bootstrap_dotfiles
  attempt "register projects" register_projects
  attempt "validate the sshd configuration" /usr/sbin/sshd -t

  if ((${#failed_steps[@]})); then
    printf '%s\n' "${failed_steps[@]}" >"$failure_log" 2>/dev/null || true
    chown ubuntu:ubuntu "$failure_log" 2>/dev/null || true
    log "===================================================================="
    log "BOOTSTRAP INCOMPLETE — ${#failed_steps[@]} step(s) failed:"
    printf 't3code:   - %s\n' "${failed_steps[@]}"
    log "Services are starting anyway. Connect and repair, then restart."
    log "Recorded in $failure_log"
    log "===================================================================="
  else
    log "bootstrap complete"
  fi

  exec /usr/bin/supervisord -c /etc/supervisor/conf.d/t3code.conf
}

main "$@"
