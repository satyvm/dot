#!/usr/bin/env bash
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="$stack_dir/hermes_docker_compose.yaml"
rendered="$(mktemp "${TMPDIR:-/tmp}/hermes-compose.XXXXXX")"
trap 'rm -f "$rendered"' EXIT

export DEV_SSH_PUBLIC_KEY="ssh-ed25519 AAAATEST hermes-dev"
export CLIPROXY_CLIENT_KEY="test-client-key"
export CLIPROXY_MANAGEMENT_KEY="test-management-key"
export HERMES_WEBUI_PASSWORD="test-webui-password"
export SERVER_DEV_PATH="/home/ubuntu/dev"

bash -n "$stack_dir/entrypoint.sh"
shellcheck "$stack_dir/entrypoint.sh"
docker compose -f "$compose_file" config >"$rendered"

grep -q 'host_ip: 127.0.0.1' "$rendered"
grep -q 'target: 22' "$rendered"
grep -q 'published: "2222"' "$rendered"
grep -q 'source: /home/ubuntu/dev' "$rendered"
grep -q 'target: /home/ubuntu/dev' "$rendered"
grep -q 'target: /home/ubuntu/.hermes' "$rendered"
grep -q 'http://cliproxyapi:8317/v1' "$rendered"
grep -q 'python /apptoo/server.py' "$stack_dir/supervisord.conf"
grep -q 'PasswordAuthentication no' "$stack_dir/Dockerfile"

if rg -n 'npm start|NOPASSWD|chown -R .*dev|0\\.0\\.0\\.0:.*:22' \
  "$stack_dir/Dockerfile" "$stack_dir/entrypoint.sh" \
  "$stack_dir/supervisord.conf" "$compose_file"; then
  echo "unsafe or obsolete stack pattern found" >&2
  exit 1
fi

printf 'coolify stack validation passed\n'
