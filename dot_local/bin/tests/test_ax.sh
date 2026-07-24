#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AX="$REPO_ROOT/dot_local/bin/executable_ax"
SHIM_DIR="$REPO_ROOT/dot_local/bin"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ax-test.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

FAKE_BIN="$FIXTURE_ROOT/bin"
CONFIG_HOME="$FIXTURE_ROOT/config"
STATE_HOME="$FIXTURE_ROOT/state"
HOME_DIR="$FIXTURE_ROOT/home"
mkdir -p "$FAKE_BIN" "$CONFIG_HOME/agents" "$CONFIG_HOME/ax" "$CONFIG_HOME/cli-proxy-api" "$CONFIG_HOME/crush" "$CONFIG_HOME/nono/profiles" "$STATE_HOME" "$HOME_DIR/.local/bin"
printf '%s\n' '# Universal test context' >"$CONFIG_HOME/agents/universal_context.md"

cat >"$CONFIG_HOME/ax/models.json" <<'JSON'
{
  "version": 1,
  "proxy": {"url": "http://127.0.0.1:8317", "channel": "antigravity"},
  "roles": {
    "frontier": {"alias": "frontier", "target": "upstream-frontier", "provider": "antigravity", "displayName": "Frontier", "contextWindow": 200000, "maxTokens": 32768, "reasoning": true, "input": ["text", "image"]},
    "balanced": {"alias": "balanced", "target": "upstream-balanced", "provider": "antigravity", "displayName": "Balanced", "contextWindow": 1000000, "maxTokens": 65536, "reasoning": true, "input": ["text", "image"]},
    "fast": {"alias": "fast", "target": "upstream-fast", "provider": "antigravity", "displayName": "Fast", "contextWindow": 1000000, "maxTokens": 65536, "reasoning": true, "input": ["text", "image"]},
    "light": {"alias": "light", "target": "upstream-light", "provider": "antigravity", "displayName": "Light", "contextWindow": 1000000, "maxTokens": 32768, "reasoning": false, "input": ["text"]}
  },
  "agents": {
    "claude": {"defaultRole": "balanced", "profile": "default-claude"},
    "pi": {"defaultRole": "balanced", "profile": "default-pi"},
    "opencode": {"defaultRole": "balanced", "profile": "default-opencode"},
    "crush": {"defaultRole": "balanced", "profile": "default-crush"}
  },
  "classes": {
    "claude": {"large": "frontier", "normal": "balanced", "fast": "fast", "small": "light"},
    "crush": {"large": "balanced", "small": "light"}
  },
  "alternatives": {
    "balanced": [{"provider": "codex", "target": "candidate-not-active"}]
  },
  "minimumVersions": {
    "nono": "0.1.0", "herdr": "0.1.0", "cliproxyapi": "1.0.0",
    "claude": "0.1.0", "pi": "0.1.0", "opencode": "0.1.0", "crush": "0.1.0"
  }
}
JSON
cat >"$CONFIG_HOME/crush/crush.json" <<'JSON'
{
  "providers": {
    "cliproxy": {
      "models": [
        {"id": "balanced", "name": "Balanced", "context_window": 1000000}
      ]
    }
  },
  "models": {
    "large": {"model": "balanced", "provider": "cliproxy"},
    "small": {"model": "light", "provider": "cliproxy"}
  }
}
JSON
printf '%s\n' 'test-client-key' >"$CONFIG_HOME/cli-proxy-api/client-key"
printf '{}\n' >"$CONFIG_HOME/cli-proxy-api/antigravity-test.json"

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"/v1/models"* ]]; then
  if [[ "${AX_TEST_HIDE_MODEL:-}" == "balanced" ]]; then
    printf '%s\n' '{"data":[{"id":"frontier","owned_by":"antigravity"},{"id":"fast","owned_by":"antigravity"},{"id":"light","owned_by":"antigravity"}]}'
  else
    printf '%s\n' '{"data":[{"id":"frontier","owned_by":"antigravity"},{"id":"balanced","owned_by":"antigravity"},{"id":"fast","owned_by":"antigravity"},{"id":"light","owned_by":"antigravity"},{"id":"experimental/model","owned_by":"antigravity"}]}'
  fi
  exit 0
fi
exit 22
SH

cat >"$FAKE_BIN/nono" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "nono 99.0.0"
  exit
fi
printf 'nono'
for arg in "$@"; do printf ' <%s>' "$arg"; done
printf '\n'
SH

for agent in claude pi opencode crush; do
  cat >"$FAKE_BIN/$agent" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "agent version 99.0.0"
  exit
fi
printf 'agent=%s\n' "$(basename "$0")"
printf 'model=%s\n' "${AX_MODEL_ROLE:-}:${AX_MODEL_ID:-}"
printf 'pi_agent_dir=%s\n' "${PI_CODING_AGENT_DIR:-}"
printf 'universal_context=%s\n' "${AX_UNIVERSAL_CONTEXT:-}"
if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  printf 'anthropic_auth_token=set\n'
else
  printf 'anthropic_auth_token=unset\n'
fi
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  printf 'anthropic_api_key=set\n'
else
  printf 'anthropic_api_key=unset\n'
fi
printf 'crush_config=%s\n' "${CRUSH_GLOBAL_CONFIG:-}"
if [[ -n "${CRUSH_GLOBAL_CONFIG:-}" ]]; then
  printf 'crush_model=%s\n' "$(/usr/bin/jq -r '.models.large.model' "$CRUSH_GLOBAL_CONFIG")"
fi
index=0
for arg in "$@"; do
  printf 'arg[%d]=<%s>\n' "$index" "$arg"
  index=$((index + 1))
done
SH
  chmod +x "$FAKE_BIN/$agent"
  printf '#!/usr/bin/env bash\nexec ax %s "$@"\n' "$agent" >"$HOME_DIR/.local/bin/$agent"
  chmod +x "$HOME_DIR/.local/bin/$agent"
done
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/nono"

cat >"$FAKE_BIN/herdr" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "herdr 99.0.0"
elif [[ "${1:-}" == "integration" && "${2:-}" == "status" ]]; then
  printf '%s\n' "claude: current (v99)"
  if [[ "${PI_CODING_AGENT_DIR:-}" == "$HOME/.pi/agent" ]]; then
    printf '%s\n' "pi: current (v99)"
  else
    printf '%s\n' "pi: not installed"
  fi
  printf '%s\n' "opencode: current (v99)"
fi
SH

cat >"$FAKE_BIN/cliproxyapi" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-antigravity-login" ]]; then
  echo "interactive-login=antigravity"
else
  echo "CLIProxyAPI Version: 99.0.0"
fi
SH

cat >"$FAKE_BIN/chezmoi" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "apply" ]]; then
  echo "chezmoi-apply=$2"
fi
SH

cat >"$FAKE_BIN/brew" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "services" ]]; then
  echo "brew-service=$2:$3"
fi
SH
chmod +x "$FAKE_BIN/herdr" "$FAKE_BIN/cliproxyapi" "$FAKE_BIN/chezmoi" "$FAKE_BIN/brew"
for profile in default-claude default-pi default-opencode default-crush; do
  printf '{}\n' >"$CONFIG_HOME/nono/profiles/$profile.json"
done

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'not ok %d - %s\n%s\n' "$((PASS + FAIL))" "$1" "$2"
}

assert_contains() {
  local output="$1" expected="$2" label="$3"
  if [[ "$output" == *"$expected"* ]]; then
    pass "$label"
  else
    fail "$label" "expected: $expected
actual: $output"
  fi
}

assert_status() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$label"
  else
    fail "$label" "expected status $expected, got $actual"
  fi
}

run_ax() {
  HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$CONFIG_HOME" \
    XDG_STATE_HOME="$STATE_HOME" \
    HERDR_SOCKET_PATH="${HERDR_SOCKET_PATH:-}" \
    AX_REAL_PATH="$FAKE_BIN:/usr/bin:/bin" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$AX" "$@"
}

printf 'TAP version 13\n'

OUTPUT="$(run_ax claude --resume 'session id' --flag='two words')"
assert_contains "$OUTPUT" "nono <run> <--profile> <default-claude> <--allow-cwd> <--> <$FAKE_BIN/claude>" "safe launch selects the Claude profile"
assert_contains "$OUTPUT" "<--settings> <{\"availableModels\":[\"frontier\",\"balanced\",\"fast\",\"light\"]}>" "Claude receives the canonical role allowlist"
assert_contains "$OUTPUT" "<--append-system-prompt-file> <$CONFIG_HOME/agents/universal_context.md>" "Claude receives universal context as a system-prompt file"
assert_contains "$OUTPUT" "<--resume> <session id> <--flag=two words>" "safe launch preserves Claude arguments"

OUTPUT="$(run_ax claude --direct)"
assert_contains "$OUTPUT" "anthropic_auth_token=set" "Claude receives the gateway credential as a bearer token"
assert_contains "$OUTPUT" "anthropic_api_key=unset" "Claude avoids interactive API-key approval state"
assert_contains "$OUTPUT" "universal_context=$CONFIG_HOME/agents/universal_context.md" "direct launches expose the readable universal context path"

OUTPUT="$(HERDR_SOCKET_PATH="$FIXTURE_ROOT/herdr named.sock" run_ax opencode --session 'herdr session')"
assert_contains "$OUTPUT" "<--allow-unix-socket> <$FIXTURE_ROOT/herdr named.sock>" "Herdr's resolved named-session socket is granted dynamically"
assert_contains "$OUTPUT" "<--session> <herdr session>" "Herdr restore arguments remain unchanged"

OUTPUT="$(run_ax pi --direct --session 'path with spaces')"
assert_contains "$OUTPUT" "agent=pi" "direct launch resolves the real Pi binary without shim recursion"
assert_contains "$OUTPUT" "pi_agent_dir=$HOME_DIR/.pi/agent" "Pi uses its documented global agent directory"
assert_contains "$OUTPUT" "arg[0]=<--append-system-prompt>" "Pi receives universal context through its system-prompt flag"
assert_contains "$OUTPUT" "arg[1]=<$CONFIG_HOME/agents/universal_context.md>" "Pi receives the universal context file path"
if [[ -d "$HOME_DIR/.pi/agent/sessions" ]]; then
  pass "Pi session root exists before the sandbox starts"
else
  fail "Pi session root exists before the sandbox starts" "missing: $HOME_DIR/.pi/agent/sessions"
fi
assert_contains "$OUTPUT" "arg[2]=<--session>" "direct launch preserves the session flag"
assert_contains "$OUTPUT" "arg[3]=<path with spaces>" "direct launch preserves a spaced session identifier"

set +e
OUTPUT="$(run_ax claude direct 2>&1)"
STATUS=$?
set -e
assert_status 0 "$STATUS" "legacy positional direct is forwarded instead of bypassing Nono"
assert_contains "$OUTPUT" "<direct>" "sandbox bypass requires the explicit --direct flag"

OUTPUT="$(AX_MODEL=frontier run_ax opencode)"
assert_contains "$OUTPUT" "nono <run> <--profile> <default-opencode>" "OpenCode selects its agent-specific profile"
assert_contains "$OUTPUT" "<--model> <cliproxy/frontier>" "OpenCode receives an explicit canonical role override"

OUTPUT="$(AX_MODEL='raw:experimental/model' run_ax pi --resume 'native id')"
assert_contains "$OUTPUT" "<--model> <cliproxy/experimental/model>" "Pi receives an explicit raw-model override"
assert_contains "$OUTPUT" "<--resume> <native id>" "raw-model selection preserves Pi resume arguments"

OUTPUT="$(AX_MODEL='raw:experimental/model' run_ax crush --direct --continue)"
assert_contains "$OUTPUT" "crush_model=experimental/model" "Crush receives an explicit raw-model override"
assert_contains "$OUTPUT" "arg[0]=<--continue>" "raw-model selection preserves Crush continue arguments"

set +e
OUTPUT="$(AX_MODEL=missing run_ax crush 2>&1)"
STATUS=$?
set -e
assert_status 64 "$STATUS" "an unavailable canonical role fails without fallback"
assert_contains "$OUTPUT" "unknown model role: missing" "unavailable role error is actionable"

set +e
OUTPUT="$(AX_TEST_HIDE_MODEL=balanced run_ax claude 2>&1)"
STATUS=$?
set -e
assert_status 69 "$STATUS" "launch fails before the agent when its role is absent from the live proxy catalog"
assert_contains "$OUTPUT" "model 'balanced' is not advertised" "missing live role error names the unavailable alias"

OUTPUT="$(run_ax models show)"
assert_contains "$OUTPUT" "balanced" "models show lists the canonical roles"
assert_contains "$OUTPUT" "upstream-balanced" "models show lists each active target"
if [[ "$OUTPUT" != *"candidate-not-active"* ]]; then
  pass "models show does not activate recorded alternatives"
else
  fail "models show does not activate recorded alternatives" "$OUTPUT"
fi

OUTPUT="$(run_ax models live)"
assert_contains "$OUTPUT" "frontier" "models live reads the proxy catalog"

OUTPUT="$(run_ax doctor)"
assert_contains "$OUTPUT" "proxy: ready" "doctor reports proxy readiness"
assert_contains "$OUTPUT" "models: valid" "doctor validates the registry"
assert_contains "$OUTPUT" "universal context: ready" "doctor validates the essential universal context"

mv "$CONFIG_HOME/agents/universal_context.md" "$FIXTURE_ROOT/universal_context.md"
set +e
OUTPUT="$(run_ax claude --direct 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "launch fails closed when universal context is unavailable"
assert_contains "$OUTPUT" "essential universal context is missing or unreadable" "missing universal context error is actionable"
mv "$FIXTURE_ROOT/universal_context.md" "$CONFIG_HOME/agents/universal_context.md"

OUTPUT="$(AX_PLATFORM=Darwin run_ax auth setup)"
assert_contains "$OUTPUT" "interactive-login=antigravity" "auth setup runs the active provider's interactive login"
assert_contains "$OUTPUT" "brew-service=restart:cliproxyapi" "auth setup restarts CLIProxyAPI after login"
if [[ -s "$CONFIG_HOME/cli-proxy-api/client-key" && -s "$CONFIG_HOME/cli-proxy-api/management-key" ]]; then
  pass "auth setup initializes both per-device keys"
else
  fail "auth setup initializes both per-device keys" "one or more key files are missing"
fi

mv "$CONFIG_HOME/cli-proxy-api/antigravity-test.json" "$FIXTURE_ROOT/antigravity-test.json"
printf '{}\n' >"$CONFIG_HOME/cli-proxy-api/codex-stale.json"
set +e
OUTPUT="$(run_ax doctor 2>&1)"
STATUS=$?
set -e
assert_status 1 "$STATUS" "doctor fails when provider authentication is missing"
assert_contains "$OUTPUT" "provider authentication (antigravity): missing" "doctor reports missing active-channel authentication without exposing secrets"
rm "$CONFIG_HOME/cli-proxy-api/codex-stale.json"
mv "$FIXTURE_ROOT/antigravity-test.json" "$CONFIG_HOME/cli-proxy-api/antigravity-test.json"

for agent in claude pi opencode crush; do
  shim="$SHIM_DIR/executable_$agent"
  if [[ -x "$shim" ]] && grep -qF "ax $agent" "$shim"; then
    pass "$agent shim delegates to ax"
  else
    fail "$agent shim delegates to ax" "missing or invalid shim: $shim"
  fi
done

INVALID_REGISTRY="$FIXTURE_ROOT/invalid-models.json"
jq '.roles.fast.target = .roles.balanced.target' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects conflicting active targets"

jq 'del(.roles.light)' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation requires all four canonical roles"

jq '.roles.light.contextWindow = 0' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects incomplete capability metadata"

jq '.alternatives.balanced[0].provider = "unknown-provider"' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects unknown alternative providers"

jq '.roles.fast.alias = "balanced"' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects duplicate aliases"

RENDER_ROOT="$FIXTURE_ROOT/rendered"
mkdir -p "$RENDER_ROOT"
if command -v chezmoi >/dev/null 2>&1; then
  chezmoi execute-template <"$REPO_ROOT/dot_config/ax/models.json.tmpl" >"$RENDER_ROOT/models.json"
  chezmoi execute-template <"$REPO_ROOT/dot_config/opencode/opencode.jsonc.tmpl" >"$RENDER_ROOT/opencode.json"
  chezmoi execute-template <"$REPO_ROOT/dot_pi/agent/settings.json.tmpl" >"$RENDER_ROOT/pi-settings.json"
  chezmoi execute-template <"$REPO_ROOT/dot_pi/agent/models.json.tmpl" >"$RENDER_ROOT/pi-models.json"
  chezmoi execute-template <"$REPO_ROOT/dot_config/crush/crush.json.tmpl" >"$RENDER_ROOT/crush.json"
  chezmoi execute-template <"$REPO_ROOT/dot_config/cli-proxy-api/private_config.yaml.tmpl" >"$RENDER_ROOT/proxy.yaml"
  chezmoi execute-template <"$REPO_ROOT/run_onchange_after_setup-ai-agent-platform.sh.tmpl" >"$RENDER_ROOT/setup-ai-agent-platform.sh"
  SKILL_SCRIPT_ROOT="$RENDER_ROOT/skill-creator/scripts"
  mkdir -p "$SKILL_SCRIPT_ROOT"
  for script_name in generate_report improve_description quick_validate run_eval run_loop utils; do
    chezmoi cat "$HOME/.config/agents/skills/skill-creator/scripts/$script_name.py" >"$SKILL_SCRIPT_ROOT/$script_name.py"
  done
  if jq -e . "$RENDER_ROOT"/*.json >/dev/null; then
    pass "all rendered client JSON documents parse"
  else
    fail "all rendered client JSON documents parse" "one or more rendered files are invalid"
  fi
  if ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), aliases: false)' "$RENDER_ROOT/proxy.yaml"; then
    pass "rendered CLIProxyAPI YAML parses"
  else
    fail "rendered CLIProxyAPI YAML parses" "invalid YAML"
  fi
  assert_contains "$(cat "$RENDER_ROOT/proxy.yaml")" 'host: "127.0.0.1"' "CLIProxyAPI binds only to IPv4 loopback"
  assert_contains "$(cat "$RENDER_ROOT/opencode.json")" '"model": "cliproxy/balanced"' "OpenCode receives the canonical balanced default"
  assert_contains "$(cat "$RENDER_ROOT/opencode.json")" '"small_model": "cliproxy/light"' "OpenCode keeps background tasks on the canonical light model"
  assert_contains "$(cat "$RENDER_ROOT/opencode.json")" '"npm": "@ai-sdk/openai-compatible"' "OpenCode uses the proxy's Chat Completions protocol"
  assert_contains "$(cat "$RENDER_ROOT/opencode.json")" '/.config/agents/universal_context.md"' "OpenCode loads the universal context as an instruction file"
  assert_contains "$(cat "$RENDER_ROOT/pi-settings.json")" '"defaultModel": "balanced"' "Pi receives the canonical balanced default"
  assert_contains "$(cat "$RENDER_ROOT/crush.json")" '"model": "balanced"' "Crush receives the canonical balanced default"
  assert_contains "$(cat "$RENDER_ROOT/crush.json")" '/.config/agents/universal_context.md"' "Crush loads the universal context through context_paths"
  if bash -n "$RENDER_ROOT/setup-ai-agent-platform.sh"; then
    pass "rendered AI platform setup script parses"
  else
    fail "rendered AI platform setup script parses" "invalid shell syntax"
  fi
  assert_contains "$(cat "$RENDER_ROOT/setup-ai-agent-platform.sh")" "PI_CODING_AGENT_DIR=\"\$HOME/.pi/agent\" herdr integration install \"\$agent\"" "Herdr installs Pi integration in Pi's documented agent directory"
  assert_contains "$(chezmoi target-path "$REPO_ROOT/dot_config/agents/skills/skill-creator/scripts/literal_run_eval.py")" "/run_eval.py" "chezmoi preserves the run_eval.py payload basename"
  assert_contains "$(chezmoi target-path "$REPO_ROOT/dot_config/agents/skills/skill-creator/scripts/literal_run_loop.py")" "/run_loop.py" "chezmoi preserves the run_loop.py payload basename"
  if (cd "$FIXTURE_ROOT" && PYTHONDONTWRITEBYTECODE=1 python3 "$SKILL_SCRIPT_ROOT/run_eval.py" --help >/dev/null); then
    pass "rendered run_eval.py resolves its sibling scripts package"
  else
    fail "rendered run_eval.py resolves its sibling scripts package" "run_eval.py --help failed"
  fi
  if (cd "$FIXTURE_ROOT" && PYTHONDONTWRITEBYTECODE=1 python3 "$SKILL_SCRIPT_ROOT/run_loop.py" --help >/dev/null); then
    pass "rendered run_loop.py resolves its sibling scripts package"
  else
    fail "rendered run_loop.py resolves its sibling scripts package" "run_loop.py --help failed"
  fi
else
  fail "chezmoi render tests" "chezmoi is not installed"
fi

if command -v nono >/dev/null 2>&1; then
  for profile_path in "$REPO_ROOT"/dot_config/nono/profiles/*.json; do
    if nono profile validate "$profile_path" >/dev/null 2>&1; then
      pass "$(basename "$profile_path") passes nono profile validate"
    else
      fail "$(basename "$profile_path") passes nono profile validate" "invalid Nono profile"
    fi
  done
  EFFECTIVE_PROFILE="$(nono profile show "$REPO_ROOT/dot_config/nono/profiles/default-opencode.json" --json)"
  assert_contains "$EFFECTIVE_PROFILE" '"network_profile": "developer"' "effective policy permits general developer networking"
  assert_contains "$EFFECTIVE_PROFILE" "\"\$HOME/.ssh\"" "effective policy denies SSH material"
  assert_contains "$EFFECTIVE_PROFILE" "\"\$HOME/Library/Keychains\"" "effective policy denies macOS Keychain data"
  assert_contains "$EFFECTIVE_PROFILE" "\"\$HOME/.cargo/credentials.toml\"" "effective policy denies Cargo registry credentials"
  assert_contains "$EFFECTIVE_PROFILE" "\"\$HOME/.config/agents/universal_context.md\"" "effective policy grants read-only universal context access"
  if [[ "$EFFECTIVE_PROFILE" != *"\"\$HOME/.local/share\""* ]]; then
    pass "effective policy avoids a broad ~/.local/share grant"
  else
    fail "effective policy avoids a broad ~/.local/share grant" "$EFFECTIVE_PROFILE"
  fi
  PI_EFFECTIVE="$(nono profile show "$REPO_ROOT/dot_config/nono/profiles/default-pi.json" --json)"
  if jq -e '
    (.filesystem.read | index("$HOME/.pi/agent")) != null and
    (.filesystem.allow | index("$HOME/.pi/agent")) == null
  ' <<<"$PI_EFFECTIVE" >/dev/null; then
    pass "Pi generated config and integration directory are read-only"
  else
    fail "Pi generated config and integration directory are read-only" "$PI_EFFECTIVE"
  fi
  CLAUDE_EFFECTIVE="$(nono profile show "$REPO_ROOT/dot_config/nono/profiles/default-claude.json" --json)"
  if jq -e '
    (.filesystem.read | index("$HOME/.claude")) != null and
    (.filesystem.allow | index("$HOME/.claude")) == null and
    (.filesystem.allow_file | index("$HOME/.claude.json")) != null and
    (.filesystem.allow_file | index("$HOME/.claude.json.lock")) != null
  ' <<<"$CLAUDE_EFFECTIVE" >/dev/null; then
    pass "Claude settings and Herdr hooks are read-only"
  else
    fail "Claude settings and Herdr hooks are read-only" "$CLAUDE_EFFECTIVE"
  fi
else
  fail "Nono profile tests" "nono is not installed"
fi

printf '1..%d\n' "$((PASS + FAIL))"
if ((FAIL > 0)); then
  printf '# %d test(s) failed\n' "$FAIL"
  exit 1
fi
