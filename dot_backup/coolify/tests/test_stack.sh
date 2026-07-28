#!/usr/bin/env bash
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="$stack_dir/hermes_docker_compose.yaml"
pycache_dir="$(mktemp -d "${TMPDIR:-/tmp}/hermes-pycache.XXXXXX")"
rendered=""

cleanup() {
  rm -rf "$pycache_dir"
  if [[ -n "$rendered" ]]; then
    rm -f "$rendered"
  fi
}
trap cleanup EXIT

export DEV_SSH_PUBLIC_KEY="ssh-ed25519 AAAATEST hermes-dev"
export CLIPROXY_CLIENT_KEY="test-client-key"
export CLIPROXY_MANAGEMENT_KEY="test-management-key"
export HERMES_WEBUI_PASSWORD="test-webui-password"
export DEV_SSH_PORT="22223"
export PYTHONPYCACHEPREFIX="$pycache_dir"

bash -n "$stack_dir/entrypoint.sh"
python3 -m py_compile "$stack_dir/tea_sidecar.py"
python3 -m py_compile "$stack_dir/gitea_ai_cli.py"
shellcheck "$stack_dir/entrypoint.sh"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  rendered="$(mktemp "${TMPDIR:-/tmp}/hermes-compose.XXXXXX")"
  docker compose -f "$compose_file" config >"$rendered"

  if grep -q 'cliproxy-init' "$rendered"; then
    echo "one-shot cliproxy-init must not be present" >&2
    exit 1
  fi
  grep -q 'host_ip: 127.0.0.1' "$rendered"
  grep -q 'target: 22' "$rendered"
  grep -q 'published: "22223"' "$rendered"
  grep -q 'source: /home/ubuntu/dev' "$rendered"
  grep -q 'target: /home/ubuntu/dev' "$rendered"
  grep -q 'target: /home/ubuntu/.hermes' "$rendered"
  grep -q 'http://cliproxyapi:8317/v1' "$rendered"
  grep -q 'tea-sidecar' "$rendered"
  grep -q '/run/tea/tea.sock' "$rendered"
else
  grep -q '22223' "$compose_file"
  grep -q 'tea-sidecar' "$compose_file"
  grep -q '/run/tea/tea.sock' "$compose_file"
fi

grep -q 'python /apptoo/server.py' "$stack_dir/supervisord.conf"
grep -q 'PasswordAuthentication no' "$stack_dir/Dockerfile"
grep -q 'context: ./dot_backup/coolify' "$compose_file"
grep -q './dot_backup/coolify/tea_sidecar.py:/app/tea_sidecar.py:ro' "$compose_file"
grep -q 'exec ./CLIProxyAPI -config /config/config.yaml' "$compose_file"
grep -q '/dev/tcp/127.0.0.1/8317' "$compose_file"
grep -q '/home/linuxbrew/.linuxbrew/bin/herdr' "$stack_dir/Dockerfile"
grep -q '/home/linuxbrew/.linuxbrew/bin/nono' "$stack_dir/Dockerfile"
grep -q '/home/linuxbrew/.linuxbrew/bin/crush' "$stack_dir/Dockerfile"
grep -q 'install -d -o ubuntu -g ubuntu' "$stack_dir/Dockerfile"
grep -q '/home/linuxbrew/.linuxbrew' "$stack_dir/Dockerfile"

if rg -n 'npm start|NOPASSWD|chown -R .*dev|0\.0\.0\.0:.*:22' \
  "$stack_dir/Dockerfile" "$stack_dir/entrypoint.sh" \
  "$stack_dir/supervisord.conf" "$compose_file"; then
  echo "unsafe or obsolete stack pattern found" >&2
  exit 1
fi

printf 'coolify stack validation passed\n'
