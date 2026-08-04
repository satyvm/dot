#!/usr/bin/env bash
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$stack_dir/.." && pwd)"
compose_file="$stack_dir/hermes_docker_compose.yaml"
pycache_dir="$(mktemp -d "${TMPDIR:-/tmp}/hermes-pycache.XXXXXX")"
host_chezmoi_cache="$pycache_dir/chezmoi-cache"
rendered=""
rendered_json=""
remote_config=""
remote_destination=""
rendered_setup=""
hermes_test_home=""
hermes_test_bin=""

cleanup() {
  rm -rf "$pycache_dir"
  if [[ -n "$rendered" ]]; then
    rm -f "$rendered"
  fi
  if [[ -n "$rendered_json" ]]; then
    rm -f "$rendered_json"
  fi
  if [[ -n "$remote_config" ]]; then
    rm -f "$remote_config"
  fi
  if [[ -n "$remote_destination" ]]; then
    rm -rf "$remote_destination"
  fi
  if [[ -n "$rendered_setup" ]]; then
    rm -f "$rendered_setup"
  fi
  if [[ -n "$hermes_test_home" ]]; then
    rm -rf "$hermes_test_home"
  fi
  if [[ -n "$hermes_test_bin" ]]; then
    rm -rf "$hermes_test_bin"
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

if command -v chezmoi >/dev/null 2>&1; then
  remote_config="$(mktemp "${TMPDIR:-/tmp}/hermes-remote-config.XXXXXX")"
  remote_destination="$(mktemp -d "${TMPDIR:-/tmp}/hermes-remote-home.XXXXXX")"
  printf '%s\n' \
    '{"data":{"machine":{"schemaVersion":1,"preset":"container","os":"linux","arch":"amd64","distro":"debian","homebrewPrefix":"/home/linuxbrew/.linuxbrew","devRoot":"/home/ubuntu/dev","customize":false,"overrides":{}},"name":"Satyam","email":"test@example.com"}}' \
    >"$remote_config"
  remote_managed="$(
    HOME="$remote_destination" chezmoi managed \
      --config "$remote_config" \
      --config-format json \
      --source "$repo_root" \
      --destination "$remote_destination" \
      --cache "$host_chezmoi_cache" \
      --refresh-externals=never
  )"
  if grep -Eq '^(backup|hermes)(/|$)' <<<"$remote_managed"; then
    echo "remote profile must not manage repository-only backup or Hermes files" >&2
    exit 1
  fi
  if grep -qx 'install-homebrew-packages.sh' <<<"$remote_managed"; then
    echo "remote profile must not run the host Homebrew package installer" >&2
    exit 1
  fi
  if grep -qx 'install-developer-tools.sh' <<<"$remote_managed"; then
    echo "remote profile must use image-baked developer tools" >&2
    exit 1
  fi
  if grep -qx 'setup-shell.sh' <<<"$remote_managed"; then
    echo "remote profile must use image-baked login shell, not host setup-shell.sh" >&2
    exit 1
  fi
  grep -qx 'setup-ai-agent-platform.sh' <<<"$remote_managed"

  rendered_setup="$(mktemp "${TMPDIR:-/tmp}/hermes-setup-script.XXXXXX")"
  HOME="$remote_destination" chezmoi execute-template \
    --config "$remote_config" \
    --config-format json \
    --source "$repo_root" \
    <"$repo_root/run_onchange_after_setup-ai-agent-platform.sh.tmpl" \
    >"$rendered_setup"
  bash -n "$rendered_setup"

  hermes_test_home="$(mktemp -d "${TMPDIR:-/tmp}/hermes-test-home.XXXXXX")"
  hermes_test_bin="$(mktemp -d "${TMPDIR:-/tmp}/hermes-test-bin.XXXXXX")"
  mkdir -p "$hermes_test_home/.config/ai-tools"
  printf '%s\n' '{"mcpServers":{"filesystem":{"command":"mcp-server","args":["/workspace"]}}}' \
    >"$hermes_test_home/.config/ai-tools/claude-mcp.json"
  for command_name in hermes herdr claude pi opencode; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$hermes_test_bin/$command_name"
    chmod 0755 "$hermes_test_bin/$command_name"
  done
  hermes_python=""
  for candidate in python3 python; do
    candidate_path="$(command -v "$candidate" 2>/dev/null || true)"
    if [[ -n "$candidate_path" ]] && "$candidate_path" -c 'import yaml' >/dev/null 2>&1; then
      hermes_python="$candidate_path"
      break
    fi
  done
  if [[ -n "$hermes_python" ]]; then
    HOME="$hermes_test_home" \
      PATH="$hermes_test_bin:$PATH" \
      HERMES_WEBUI_PYTHON="$hermes_python" \
      OPENAI_API_KEY="$CLIPROXY_CLIENT_KEY" \
      bash "$rendered_setup"
    HERMES_TEST_CONFIG="$hermes_test_home/.hermes/config.yaml" "$hermes_python" - <<'PY'
import os
from pathlib import Path

import yaml

config = yaml.safe_load(Path(os.environ["HERMES_TEST_CONFIG"]).read_text())
assert config["model"] == {
    "default": "balanced",
    "provider": "custom:cliproxyapi",
    "base_url": "http://cliproxyapi:8317/v1",
    "api_mode": "chat_completions",
}
assert "provider" not in config
provider = config["custom_providers"][0]
assert provider["name"] == "CLIProxyAPI"
assert provider["base_url"] == "http://cliproxyapi:8317/v1"
assert provider["key_env"] == "OPENAI_API_KEY"
assert provider["api_mode"] == "chat_completions"
assert provider["discover_models"] is True
assert "frontier" in provider["models"]
assert "gpt-5.6-luna" in provider["models"]
assert "gpt-image-2" not in provider["models"]
assert config["fallback_providers"] == [
    {
        "provider": "custom",
        "model": "gemini-3-flash-agent",
        "base_url": "http://cliproxyapi:8317/v1",
        "key_env": "OPENAI_API_KEY",
    },
    {
        "provider": "custom",
        "model": "gpt-5.6-luna",
        "base_url": "http://cliproxyapi:8317/v1",
        "key_env": "OPENAI_API_KEY",
    },
]
for alias, entry in config["model_aliases"].items():
    assert isinstance(entry, dict), alias
    assert entry["provider"] == "custom:cliproxyapi", alias
    assert entry["base_url"] == "http://cliproxyapi:8317/v1", alias
    assert entry["model"] != alias, alias
assert config["model_aliases"]["frontier"]["model"] == "frontier(xhigh)"
assert config["model_aliases"]["balanced"]["model"] == "balanced(xhigh)"
assert config["model_aliases"]["gpt-5.6-luna"]["model"] == "gpt-5.6-luna(xhigh)"
assert config["model_aliases"]["gpt-5.6-sol"]["model"] == "gpt-5.6-sol(xhigh)"
assert config["mcp_servers"]["filesystem"]["command"] == "mcp-server"
PY
  else
    grep -q 'provider_id = "custom:cliproxyapi"' "$rendered_setup"
    grep -q 'custom_providers = config.get("custom_providers", \[\])' "$rendered_setup"
    grep -q '"key_env": "OPENAI_API_KEY"' "$rendered_setup"
    grep -q '"discover_models": True' "$rendered_setup"
    grep -q 'canonical_aliases\["gpt-5.6-sol"\] = "gpt-5.6-sol(xhigh)"' "$rendered_setup"
  fi
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  rendered="$(mktemp "${TMPDIR:-/tmp}/hermes-compose.XXXXXX")"
  rendered_json="$(mktemp "${TMPDIR:-/tmp}/hermes-compose.XXXXXX.json")"
  docker compose --project-directory "$repo_root" -f "$compose_file" config >"$rendered"
  docker compose --project-directory "$repo_root" -f "$compose_file" config --format json >"$rendered_json"

  if grep -q 'cliproxy-init' "$rendered"; then
    echo "one-shot cliproxy-init must not be present" >&2
    exit 1
  fi
  grep -q 'host_ip: 127.0.0.1' "$rendered"
  grep -q 'target: 22' "$rendered"
  grep -q 'published: "22223"' "$rendered"
  grep -q 'source: /home/ubuntu/dev' "$rendered"
  grep -q 'target: /home/ubuntu/dev' "$rendered"
  bind_count="$(grep -c 'type: bind' "$rendered")"
  if [[ "$bind_count" -ne 1 ]]; then
    echo "only /home/ubuntu/dev may be a host bind; found $bind_count binds" >&2
    exit 1
  fi
  grep -q 'source: remote-home' "$rendered"
  grep -q 'target: /home/ubuntu' "$rendered"
  grep -q 'source: hermes-state' "$rendered"
  grep -q 'target: /home/ubuntu/.hermes' "$rendered"
  grep -q 'source: ssh-host-keys' "$rendered"
  grep -q 'target: /etc/ssh/host-keys' "$rendered"
  grep -q 'source: cliproxy-auth' "$rendered"
  grep -q 'target: /root/.cli-proxy-api' "$rendered"
  grep -q 'source: cliproxy-config' "$rendered"
  grep -q 'target: /config' "$rendered"
  grep -q 'source: platform-secrets' "$rendered"
  jq -e '
    .services.cliproxyapi.command[2] as $command |
    all(
      [
        ["frontier", "gpt-5.6-sol"],
        ["balanced", "gpt-5.6-terra"],
        ["fast", "gemini-3.6-flash-high"],
        ["light", "gpt-5.4-mini"]
      ][];
      . as [$alias, $name] |
      ($command | contains("alias: \"" + $alias + "\"")) and
      ($command | contains("name: \"" + $name + "\""))
    ) and
    ([.services.cliproxyapi.command[2] | scan("fork: true")] | length == 4)
  ' "$rendered_json" >/dev/null

  grep -q 'source: tea-socket' "$rendered"
  grep -q 'http://cliproxyapi:8317/v1' "$rendered"
  grep -q 'tea-sidecar' "$rendered"
  grep -q 'dockerfile: Dockerfile.tea' "$rendered"
  grep -q '/run/tea/tea.sock' "$rendered"
  if grep -q 'tea_sidecar.py' "$rendered"; then
    echo "tea sidecar script must be baked into its image, not mounted at runtime" >&2
    exit 1
  fi
else
  grep -q '22223' "$compose_file"
  grep -q 'tea-sidecar' "$compose_file"
  grep -q '/run/tea/tea.sock' "$compose_file"
fi

grep -q 'python /apptoo/server.py' "$stack_dir/supervisord.conf"
grep -q 'HERMES_WEBUI_AGENT_DIR="/opt/hermes-agent"' "$stack_dir/supervisord.conf"
grep -q 'HERMES_WEBUI_AGENT_DIR: /opt/hermes-agent' "$compose_file"
grep -q 'HERMES_WEBUI_PYTHON: /opt/hermes-venv/bin/python' "$compose_file"
# shellcheck disable=SC2016 # Verify the Dockerfile's literal shell expression.
grep -q 'ln -s "${agent_site}" /opt/hermes-agent' "$stack_dir/Dockerfile"
grep -q 'test -f /opt/hermes-agent/run_agent.py' "$stack_dir/Dockerfile"
grep -q "from run_agent import AIAgent" "$stack_dir/Dockerfile"
grep -q '^FROM node:22\.19\.0-bookworm-slim AS node-runtime$' "$stack_dir/Dockerfile"
grep -q '/home/ubuntu/.config/opencode/agents' "$stack_dir/Dockerfile"
grep -q '/home/ubuntu/.local/share/opencode/log' "$stack_dir/Dockerfile"
grep -q '/home/ubuntu/.local/state/opencode' "$stack_dir/Dockerfile"
grep -q 'PasswordAuthentication no' "$stack_dir/Dockerfile"
if ! grep -q 'PermitEmptyPasswords no' "$stack_dir/Dockerfile"; then
  echo "key-only SSH must explicitly reject empty-password login" >&2
  exit 1
fi
if ! grep -q 'passwd --delete ubuntu' "$stack_dir/Dockerfile"; then
  echo "key-only SSH account must be unlocked after useradd" >&2
  exit 1
fi
grep -q "passwd --status ubuntu.*grep -q '\\^ubuntu NP '" \
  "$stack_dir/Dockerfile"
grep -q 'context: ./hermes' "$compose_file"
grep -q 'dockerfile: Dockerfile.tea' "$compose_file"
grep -q 'COPY tea_sidecar.py /usr/local/bin/tea-sidecar' \
  "$stack_dir/Dockerfile.tea"
if grep -q 'tea_sidecar.py' "$compose_file"; then
  echo "tea sidecar script must not use a runtime file mount" >&2
  exit 1
fi
grep -q 'exec ./CLIProxyAPI -config /config/config.yaml' "$compose_file"
grep -q '/dev/tcp/127.0.0.1/8317' "$compose_file"
grep -q 'chezmoi.json' "$stack_dir/entrypoint.sh"
grep -q 'legacy hand-written chezmoi config' "$stack_dir/entrypoint.sh"
grep -q 'chezmoi init' "$stack_dir/entrypoint.sh"
grep -q 'Machine preset=container' "$stack_dir/entrypoint.sh"
grep -q 'Customize preset features=false' "$stack_dir/entrypoint.sh"
grep -q 'bootstrap marker is incomplete' "$stack_dir/entrypoint.sh"
if grep -A5 'bootstrap_dotfiles()' "$stack_dir/entrypoint.sh" | grep -q 'return'; then
  echo "initialized remote dotfiles must refresh and apply on container restart" >&2
  exit 1
fi
grep -q 'git -C.*pull --ff-only' "$stack_dir/entrypoint.sh"
apply_block="$(grep -A8 'run_as_ubuntu chezmoi apply' "$stack_dir/entrypoint.sh")"
for required_flag in --force --no-tty '--refresh-externals=never'; do
  if ! grep -q -- "$required_flag" <<<"$apply_block"; then
    echo "remote chezmoi apply must include $required_flag for unattended conflict recovery" >&2
    exit 1
  fi
done
if grep -A2 'if \[\[ ! -s "\$chezmoi_config" \]\]' \
    "$stack_dir/entrypoint.sh" | grep -q 'initialize_chezmoi_config'; then
  echo "remote chezmoi config must be regenerated after every source refresh" >&2
  exit 1
fi
grep -q '^  initialize_chezmoi_config$' "$stack_dir/entrypoint.sh"
grep -q 'find.*remote_home' "$stack_dir/entrypoint.sh"
grep -q 'dev_root.*-prune' "$stack_dir/entrypoint.sh"
if grep -q 'SERVER_DEV_PATH' "$stack_dir/entrypoint.sh"; then
  echo "the development mount must remain fixed at /home/ubuntu/dev" >&2
  exit 1
fi
if grep -q 'write_chezmoi_config' "$stack_dir/entrypoint.sh"; then
  echo "remote bootstrap must use chezmoi init, not a hand-written config" >&2
  exit 1
fi
grep -q '/home/linuxbrew/.linuxbrew/bin/herdr' "$stack_dir/Dockerfile"
grep -q '/home/linuxbrew/.linuxbrew/bin/nono' "$stack_dir/Dockerfile"
grep -q '/home/linuxbrew/.linuxbrew/bin/crush' "$stack_dir/Dockerfile"
grep -q 'brew trust --formula charmbracelet/tap/crush' "$stack_dir/Dockerfile"
grep -q 'install -d -o ubuntu -g ubuntu' "$stack_dir/Dockerfile"
grep -q '/home/linuxbrew/.linuxbrew' "$stack_dir/Dockerfile"

if rg -n 'npm start|chown -R .*dev|0\.0\.0\.0:.*:22' \
  "$stack_dir/Dockerfile" "$stack_dir/entrypoint.sh" \
  "$stack_dir/supervisord.conf" "$compose_file"; then
  echo "unsafe or obsolete stack pattern found" >&2
  exit 1
fi

printf 'coolify stack validation passed\n'
