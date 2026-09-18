#!/usr/bin/env bash
set -euo pipefail
unset HERDR_SOCKET_PATH

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
mkdir -p "$FAKE_BIN" "$CONFIG_HOME/agents" "$CONFIG_HOME/ax" "$CONFIG_HOME/cli-proxy-api" "$CONFIG_HOME/crush" "$CONFIG_HOME/nono/profiles" "$STATE_HOME" "$HOME_DIR/.local/bin" "$HOME_DIR/dev"
mkdir -p "$CONFIG_HOME/agents/context"
for layer in base environment ax-context; do
  printf '%s\n' "# Test context layer: $layer" >"$CONFIG_HOME/agents/context/$layer.md"
done

cat >"$CONFIG_HOME/ax/models.json" <<'JSON'
{
  "version": 1,
  "proxy": {"url": "http://127.0.0.1:8317", "mode": "local", "channel": "antigravity"},
  "roles": {
    "frontier": {"alias": "frontier", "target": "upstream-frontier", "provider": "codex", "displayName": "Frontier", "contextWindow": 200000, "maxTokens": 32768, "reasoning": false, "reasoningSuffix": "", "input": ["text", "image"]},
    "balanced": {"alias": "balanced", "target": "upstream-balanced", "provider": "codex", "displayName": "Balanced", "contextWindow": 1000000, "maxTokens": 65536, "reasoning": false, "reasoningSuffix": "", "input": ["text", "image"]},
    "fast": {"alias": "fast", "target": "upstream-fast", "provider": "antigravity", "displayName": "Fast", "contextWindow": 1000000, "maxTokens": 65536, "reasoning": false, "reasoningSuffix": "", "input": ["text", "image"]},
    "light": {"alias": "light", "target": "upstream-light", "provider": "codex", "displayName": "Light", "contextWindow": 1000000, "maxTokens": 32768, "reasoning": false, "reasoningSuffix": "", "input": ["text"]}
  },
  "catalog": {
    "gpt-5.6-luna": {"alias": "gpt-5.6-luna", "target": "upstream-luna", "provider": "codex", "displayName": "GPT Luna", "contextWindow": 200000, "maxTokens": 32768, "reasoning": false, "reasoningSuffix": "", "input": ["text", "image"]}
  },
  "agents": {
    "claude": {"defaultRole": "balanced", "profile": "default-claude"},
    "codex": {"defaultRole": "balanced", "profile": "default-codex"},
    "omp": {"defaultRole": "balanced", "profile": "default-omp"},
    "opencode": {"defaultRole": "balanced", "profile": "default-opencode"}
  },
  "classes": {
    "claude": {"large": "frontier", "normal": "balanced", "fast": "fast", "small": "light"}
  },
  "alternatives": {
    "balanced": [{"provider": "codex", "target": "candidate-not-active"}]
  },
  "minimumVersions": {
    "nono": "0.1.0", "herdr": "0.1.0", "cliproxyapi": "1.0.0",
    "claude": "0.1.0", "codex": "0.1.0", "omp": "0.1.0", "opencode": "0.1.0"
  }
}
JSON
cat >"$CONFIG_HOME/ax/omp-models.yml" <<'YAML'
providers:
  cliproxy:
    baseUrl: http://127.0.0.1:8317/v1
    api: openai-responses
    apiKey: OPENAI_API_KEY
    authHeader: true
    discovery:
      type: proxy
YAML
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
printf '{}\n' >"$CONFIG_HOME/cli-proxy-api/codex-test.json"

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"/v1/models"* ]]; then
  if [[ -n "${AX_TEST_CURL_COUNT_FILE:-}" ]]; then
    count=0
    [[ -r "$AX_TEST_CURL_COUNT_FILE" ]] && read -r count <"$AX_TEST_CURL_COUNT_FILE"
    count=$((count + 1))
    printf '%s\n' "$count" >"$AX_TEST_CURL_COUNT_FILE"
    if [[ "${AX_TEST_MALFORMED_SYNC:-}" == "1" && "$count" -ge 4 ]]; then
      printf '%s\n' '{"data":'
      exit 0
    fi
  fi
  if [[ "${AX_TEST_EMPTY_MODELS:-}" == "1" ]]; then
    printf '%s\n' '{"data":[]}'
  elif [[ "${AX_TEST_UNMANAGED_MODELS:-}" == "1" ]]; then
    printf '%s\n' '{"data":[{"id":"unmanaged-only","owned_by":"unknown"}]}'
  elif [[ "${AX_TEST_HIDE_MODEL:-}" == "balanced" ]]; then
    printf '%s\n' '{"data":[{"id":"frontier","owned_by":"antigravity"},{"id":"fast","owned_by":"antigravity"},{"id":"light","owned_by":"antigravity"}]}'
  elif [[ "${AX_TEST_UPSTREAM_ONLY:-}" == "1" ]]; then
    printf '%s\n' '{"data":[{"id":"upstream-frontier","owned_by":"openai"},{"id":"upstream-balanced","owned_by":"openai"},{"id":"upstream-fast","owned_by":"antigravity"},{"id":"upstream-light","owned_by":"openai"}]}'
  else
    printf '%s\n' '{"data":[{"id":"frontier","owned_by":"antigravity"},{"id":"balanced","owned_by":"antigravity"},{"id":"fast","owned_by":"antigravity"},{"id":"light","owned_by":"antigravity"},{"id":"gpt-5.6-sol","owned_by":"openai"},{"id":"gpt-5.6-luna","owned_by":"openai"},{"id":"gemini-3.6-flash-high","owned_by":"antigravity"},{"id":"experimental/model","owned_by":"antigravity"},{"id":"future-model(preview)","owned_by":"openai"},{"id":"unrelated-anthropic-model","owned_by":"anthropic"}]}'
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
if [[ "${1:-}" == "prune" ]]; then
  echo "nono prune $*"
  exit
fi
if [[ "${1:-}" == "rollback" ]]; then
  echo "nono rollback $*"
  exit
fi
if [[ -n "${OPENCODE_CONFIG_CONTENT:-}" ]]; then
  printf ' opencode_live_model=%s' "$(/usr/bin/jq -r '.provider.cliproxy.models | has("experimental/model")' <<<"$OPENCODE_CONFIG_CONTENT")"
  printf ' opencode_parenthetical_model=%s' "$(/usr/bin/jq -r '.provider.cliproxy.models | has("future-model(preview)")' <<<"$OPENCODE_CONFIG_CONTENT")"
fi
printf 'nono cwd=<%s>' "$PWD"
for arg in "$@"; do printf ' <%s>' "$arg"; done
printf '\n'
# Behave like the real sandbox: run whatever follows the argument separator so
# the wrapped agent's environment stays observable now that --direct is gone.
saw_separator=false
command=()
for arg in "$@"; do
  if [[ "$saw_separator" == true ]]; then
    command+=("$arg")
  elif [[ "$arg" == "--" ]]; then
    saw_separator=true
  fi
done
if ((${#command[@]} > 0)); then
  exec "${command[@]}"
fi
SH

for agent in claude codex omp opencode crush; do
  cat >"$FAKE_BIN/$agent" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "agent version 99.0.0"
  exit
fi
printf 'agent=%s\n' "$(basename "$0")"
printf 'model=%s\n' "${AX_MODEL_ROLE:-}:${AX_MODEL_ID:-}"
printf 'pi_agent_dir=%s\n' "${PI_CODING_AGENT_DIR:-}"
printf 'session_context=%s\n' "${AX_SESSION_CONTEXT:-}"
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
  printf 'crush_discovery=%s\n' "$(/usr/bin/jq -r '.providers.cliproxy.discover_models' "$CRUSH_GLOBAL_CONFIG")"
fi
if [[ "$(basename "$0")" == "opencode" && -n "${OPENCODE_CONFIG_CONTENT:-}" ]]; then
  printf 'opencode_live_model=%s\n' "$(/usr/bin/jq -r '.provider.cliproxy.models | has("experimental/model")' <<<"$OPENCODE_CONFIG_CONTENT")"
  printf 'opencode_parenthetical_model=%s\n' "$(/usr/bin/jq -r '.provider.cliproxy.models | has("future-model(preview)")' <<<"$OPENCODE_CONFIG_CONTENT")"
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
  printf '%s\n' "omp: current (v99)"
  printf '%s\n' "opencode: current (v99)"
fi
SH

cat >"$FAKE_BIN/cliproxyapi" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-antigravity-login" ]]; then
  echo "interactive-login=antigravity"
elif [[ "${1:-}" == "-codex-login" ]]; then
  echo "interactive-login=codex"
  printf '{}\n' >"$XDG_CONFIG_HOME/cli-proxy-api/codex-test.json"
else
  echo "CLIProxyAPI Version: 99.0.0"
fi
SH

cat >"$FAKE_BIN/htpasswd" <<'SH'
#!/usr/bin/env bash
printf 'ax:$2a$10$test-management-key-hash\n'
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
chmod +x "$FAKE_BIN/herdr" "$FAKE_BIN/cliproxyapi" "$FAKE_BIN/htpasswd" "$FAKE_BIN/chezmoi" "$FAKE_BIN/brew"
for profile in default-claude default-codex default-omp default-opencode; do
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

assert_not_contains() {
  local output="$1" unexpected="$2" label="$3"
  if [[ "$output" != *"$unexpected"* ]]; then
    pass "$label"
  else
    fail "$label" "unexpected: $unexpected
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
    NONO_CAP_FILE="" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$AX" "$@"
}

printf 'TAP version 13\n'

if rg -F 'path=("$HOME/.local/bin" ${path:#$HOME/.local/bin})' \
  "$REPO_ROOT/dot_dotfiles/dot_extra.tmpl" >/dev/null; then
  pass "shell startup keeps ~/.local/bin ahead of Mise"
else
  fail "shell startup keeps ~/.local/bin ahead of Mise" "missing final PATH precedence repair"
fi

OUTPUT="$(cd "$HOME_DIR" && AX_PLATFORM=Linux run_ax claude --resume 'session id' --flag='two words')"
assert_contains "$OUTPUT" "/home/dev> <run> <--profile> <default-claude> <--allow-cwd> <--> <$FAKE_BIN/claude>" "Linux home launches use the safe development workspace"
assert_contains "$OUTPUT" "<--settings> <{\"availableModels\":[\"frontier\",\"balanced\",\"fast\",\"light\"]}>" "Claude receives the canonical four-role allowlist"
assert_contains "$OUTPUT" "<--append-system-prompt-file> <$CONFIG_HOME/agents/context/ax-context.md>" "Claude receives the ax session context as a system-prompt file"
assert_contains "$OUTPUT" "<--resume> <session id> <--flag=two words>" "safe launch preserves Claude arguments"

OUTPUT="$(run_ax claude)"
assert_contains "$OUTPUT" "anthropic_auth_token=set" "Claude receives the gateway credential as a bearer token"
assert_contains "$OUTPUT" "anthropic_api_key=unset" "Claude avoids interactive API-key approval state"
assert_contains "$OUTPUT" "session_context=$CONFIG_HOME/agents/context/ax-context.md" "the ax session context path is exported to the agent"

OUTPUT="$(HERDR_SOCKET_PATH="$FIXTURE_ROOT/herdr named.sock" run_ax opencode --session 'herdr session')"
assert_contains "$OUTPUT" "<--allow-unix-socket> <$FIXTURE_ROOT/herdr named.sock>" "Herdr's resolved named-session socket is granted dynamically"
assert_contains "$OUTPUT" "<--session> <herdr session>" "Herdr restore arguments remain unchanged"

OUTPUT="$(TEA_SOCKET_PATH="$FIXTURE_ROOT/tea.sock" run_ax opencode)"
assert_contains "$OUTPUT" "<--allow-unix-socket> <$FIXTURE_ROOT/tea.sock>" "Tea socket is granted dynamically when configured"

OUTPUT="$(run_ax omp --session 'path with spaces')"
assert_contains "$OUTPUT" "agent=omp" "ax resolves the real OMP binary from PATH"
assert_contains "$OUTPUT" "pi_agent_dir=$HOME_DIR/.cache/ax/omp-agent" "gateway launches isolate OMP's provider configuration"
assert_contains "$OUTPUT" "<--model> <cliproxy/balanced>" "OMP receives its canonical gateway model"
assert_contains "$OUTPUT" "<--append-system-prompt> <$CONFIG_HOME/agents/context/ax-context.md>" "OMP receives the ax context file"
assert_contains "$OUTPUT" "<--session> <path with spaces>" "OMP arguments pass through unchanged"
if [[ -f "$HOME_DIR/.cache/ax/omp-agent/models.yml" ]]; then
  pass "OMP gateway config exists before the sandbox starts"
else
  fail "OMP gateway config exists before the sandbox starts" "missing isolated models.yml"
fi

OUTPUT="$(run_ax --sandbox codex --resume sandbox-only)"
assert_contains "$OUTPUT" "nono cwd=" "--sandbox enables Nono"
assert_not_contains "$OUTPUT" "model_providers.cliproxy" "--sandbox leaves Codex on native authentication"

OUTPUT="$(run_ax -g codex --resume gateway-only)"
assert_not_contains "$OUTPUT" "nono cwd=" "--gateway does not enable Nono"
assert_contains "$OUTPUT" "model_providers.cliproxy.wire_api=responses" "--gateway injects CLIProxyAPI"

OUTPUT="$(run_ax -sg codex --resume both)"
assert_contains "$OUTPUT" "nono cwd=" "-sg enables Nono"
assert_contains "$OUTPUT" "model_providers.cliproxy.wire_api=responses" "-sg enables CLIProxyAPI"

set +e
OUTPUT="$(run_ax claude direct 2>&1)"
STATUS=$?
set -e
assert_status 0 "$STATUS" "a positional word named direct is forwarded as an argument"
assert_contains "$OUTPUT" "<direct>" "there is no flag-based sandbox bypass to trip over"

OUTPUT="$(AX_MODEL=frontier run_ax opencode)"
assert_contains "$OUTPUT" "<run> <--profile> <default-opencode>" "OpenCode selects its agent-specific profile"
assert_contains "$OUTPUT" "<--model> <cliproxy/frontier>" "OpenCode selects the clean canonical role"
assert_contains "$OUTPUT" "opencode_live_model=true" "OpenCode receives live proxy models through an ephemeral config merge"

OUTPUT="$(run_ax codex)"
assert_contains "$OUTPUT" "<model_providers.cliproxy.wire_api=responses>" "Codex uses the supported Responses API through ax"
assert_contains "$OUTPUT" "<model_providers.cliproxy.base_url=\"http://127.0.0.1:8317/v1\">" "Codex receives its gateway provider only for the ax session"

OUTPUT="$(AX_TEST_UPSTREAM_ONLY=1 run_ax codex)"
assert_contains "$OUTPUT" "<--model> <balanced>" "a canonical role remains usable when the gateway advertises only its upstream target"

OUTPUT="$(AX_MODEL=gpt-5.6-sol run_ax opencode)"
assert_contains "$OUTPUT" "<--model> <cliproxy/gpt-5.6-sol>" "OpenCode accepts a live Codex model by its real name"

OUTPUT="$(AX_MODEL='future-model(preview)' run_ax opencode)"
assert_contains "$OUTPUT" "<--model> <cliproxy/future-model(preview)>" "OpenCode preserves parenthetical live IDs"
assert_contains "$OUTPUT" "opencode_parenthetical_model=true" "OpenCode synchronizes the parenthetical live ID"

OUTPUT="$(AX_MODEL=gemini-3.6-flash-high run_ax omp)"
assert_contains "$OUTPUT" "<--model> <cliproxy/gemini-3.6-flash-high>" "OMP accepts a live Antigravity model by its real name"

OUTPUT="$(AX_MODEL=fast run_ax claude)"
assert_contains "$OUTPUT" "arg[0]=<--model>" "Claude accepts the canonical fast role override"
assert_contains "$OUTPUT" "arg[1]=<fast>" "Claude passes the fast role to Claude Code"

set +e
OUTPUT="$(AX_MODEL=gpt-5.6-luna run_ax claude 2>&1)"
STATUS=$?
set -e
assert_status 64 "$STATUS" "Claude rejects catalog models outside its canonical allowlist"
assert_contains "$OUTPUT" "Claude model must be one of" "Claude's restricted-model error names the allowlist"

set +e
OUTPUT="$(AX_MODEL='raw:experimental/model' run_ax claude 2>&1)"
STATUS=$?
set -e
assert_status 64 "$STATUS" "Claude rejects the raw-model escape hatch"

OUTPUT="$(AX_MODEL='raw:experimental/model' run_ax omp --resume 'native id')"
assert_contains "$OUTPUT" "<--model> <cliproxy/experimental/model>" "OMP receives an explicit raw-model override"
assert_contains "$OUTPUT" "<--resume> <native id>" "raw-model selection preserves OMP resume arguments"

set +e
OUTPUT="$(AX_MODEL='gpt-5.6-sol(garbage)' run_ax omp 2>&1)"
STATUS=$?
set -e
assert_status 64 "$STATUS" "malformed reasoning suffixes are not accepted through a matching base model"

set +e
OUTPUT="$(AX_MODEL=missing run_ax omp 2>&1)"
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
assert_contains "$OUTPUT" "gpt-5.6-luna" "models live includes original non-role model IDs"

OUTPUT="$(run_ax models sync)"
assert_contains "$OUTPUT" "models: valid" "models sync validates before rendering"
assert_contains "$OUTPUT" "chezmoi-apply=$CONFIG_HOME/ax/models.json" "models sync applies the managed client configurations"

set +e
OUTPUT="$(AX_TEST_EMPTY_MODELS=1 run_ax models live 2>&1)"
STATUS=$?
set -e
assert_status 69 "$STATUS" "models live fails when no provider models are available"
assert_contains "$OUTPUT" "no models are advertised" "empty live catalog points to provider authentication"

set +e
OUTPUT="$(AX_TEST_UNMANAGED_MODELS=1 run_ax models live 2>&1)"
STATUS=$?
set -e
assert_status 69 "$STATUS" "models live fails when proxy aliases drift from the managed catalog"
assert_contains "$OUTPUT" "none match the managed catalog" "unmanaged live catalog points to alias synchronization"

OUTPUT="$(run_ax doctor)"
assert_contains "$OUTPUT" "gateway: ready" "doctor reports gateway readiness"
assert_contains "$OUTPUT" "models: valid" "doctor validates the registry"
assert_contains "$OUTPUT" "agent context layers: ready" "doctor validates the essential universal context"

mkdir -p "$HOME_DIR/.omp/agent/sessions/old_session" "$HOME_DIR/.cache/crush/old_cache"
OUTPUT="$(run_ax clear --dry-run)"
assert_contains "$OUTPUT" "nono prune --dry-run" "ax clear --dry-run previews nono prune"
assert_contains "$OUTPUT" "Would purge session contents in:" "ax clear --dry-run previews clearing session targets"

OUTPUT="$(run_ax clear)"
assert_contains "$OUTPUT" "Purged session contents in:" "ax clear purges AI agent sessions"
if [[ ! -d "$HOME_DIR/.omp/agent/sessions/old_session" && -d "$HOME_DIR/.omp/agent/sessions" ]]; then
  pass "ax clear cleans session contents while keeping directory structures"
else
  fail "ax clear cleans session contents while keeping directory structures" "session directory was not cleaned properly"
fi

mv "$CONFIG_HOME/agents/context/ax-context.md" "$FIXTURE_ROOT/ax-context.md"
set +e
OUTPUT="$(run_ax claude 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "launch fails closed when the ax session context is unavailable"
assert_contains "$OUTPUT" "ax session context is missing or unreadable" "missing session context error is actionable"
mv "$FIXTURE_ROOT/ax-context.md" "$CONFIG_HOME/agents/context/ax-context.md"

OUTPUT="$(AX_PLATFORM=Darwin run_ax auth setup)"
assert_contains "$OUTPUT" "interactive-login=antigravity" "auth setup runs the active provider's interactive login"
assert_contains "$OUTPUT" "brew-service=restart:cliproxyapi" "auth setup restarts CLIProxyAPI after login"
if [[ -s "$CONFIG_HOME/cli-proxy-api/client-key" && -s "$CONFIG_HOME/cli-proxy-api/management-key" && -s "$CONFIG_HOME/cli-proxy-api/management-key.bcrypt" ]]; then
  pass "auth setup initializes client, management, and bcrypt-hash keys"
else
  fail "auth setup initializes client, management, and bcrypt-hash keys" "one or more key files are missing"
fi

OUTPUT="$(AX_PLATFORM=Darwin run_ax auth setup codex)"
assert_contains "$OUTPUT" "interactive-login=codex" "auth setup uses Codex OAuth for ChatGPT authentication"
if [[ -s "$CONFIG_HOME/cli-proxy-api/codex-test.json" ]]; then
  pass "Codex OAuth writes a provider credential"
else
  fail "Codex OAuth writes a provider credential" "missing Codex credential fixture"
fi

OUTPUT="$(AX_PLATFORM=Linux run_ax auth setup codex)"
assert_contains "$OUTPUT" "interactive-login=codex" "Linux workstation auth uses its configured local gateway"
assert_contains "$OUTPUT" "brew-service=restart:cliproxyapi" "Linux workstation restarts its local gateway"

REMOTE_REGISTRY="$FIXTURE_ROOT/remote-models.json"
jq '.proxy.url = "http://cliproxyapi:8317" | .proxy.mode = "sidecar"' "$CONFIG_HOME/ax/models.json" >"$REMOTE_REGISTRY"
OUTPUT="$(AX_REGISTRY_PATH="$REMOTE_REGISTRY" AX_PLATFORM=Linux run_ax auth setup codex)"
assert_contains "$OUTPUT" "docker exec -it" "remote auth setup prints the Docker-host login command"
assert_contains "$OUTPUT" "-codex-login" "remote auth setup names the requested provider login flag"

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

mv "$CONFIG_HOME/cli-proxy-api/antigravity-test.json" "$FIXTURE_ROOT/antigravity-remote-test.json"
OUTPUT="$(AX_REGISTRY_PATH="$REMOTE_REGISTRY" AX_PLATFORM=Linux run_ax doctor)"
assert_contains "$OUTPUT" "managed by the cliproxyapi sidecar" "sidecar doctor does not require locally owned provider files"
assert_not_contains "$OUTPUT" "cliproxyapi: missing" "sidecar doctor does not demand a local cliproxyapi binary"
mv "$FIXTURE_ROOT/antigravity-remote-test.json" "$CONFIG_HOME/cli-proxy-api/antigravity-test.json"

for agent in claude codex omp opencode crush; do
  shim="$SHIM_DIR/executable_$agent"
  if [[ -e "$shim" ]]; then
    fail "no managed shim shadows $agent" "shim still present: $shim"
  else
    pass "no managed shim shadows $agent"
  fi
done

INVALID_REGISTRY="$FIXTURE_ROOT/invalid-models.json"
jq '.roles.frontier.target = .roles.balanced.target' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
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

jq '.roles.light.reasoningSuffix = "ultra"' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects unsupported reasoning suffixes"

jq '.catalog["gpt-5.6-luna"].provider = "unknown-provider"' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects unknown catalog providers"

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

jq '.catalog["gpt-5.6-luna"].provider = .roles.frontier.provider | .catalog["gpt-5.6-luna"].target = .roles.frontier.target' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects duplicate targets across roles and catalog"

jq '
  .catalog["upstream-frontier"] =
    (.catalog["gpt-5.6-luna"] | .alias = "upstream-frontier") |
  del(.catalog["gpt-5.6-luna"])
' "$CONFIG_HOME/ax/models.json" >"$INVALID_REGISTRY"
set +e
OUTPUT="$(AX_REGISTRY_PATH="$INVALID_REGISTRY" run_ax models validate 2>&1)"
STATUS=$?
set -e
assert_status 78 "$STATUS" "registry validation rejects alias-to-target ID collisions"

MIXED_REGISTRY="$FIXTURE_ROOT/mixed-provider-models.json"
jq '
  .roles.frontier.provider = "codex" |
  .roles.fast.provider = "codex" |
  .roles.light.provider = "codex"
' "$CONFIG_HOME/ax/models.json" >"$MIXED_REGISTRY"
OUTPUT="$(AX_REGISTRY_PATH="$MIXED_REGISTRY" run_ax models validate)"
assert_contains "$OUTPUT" "models: valid" "registry validation permits simultaneous provider roles"

RENDER_ROOT="$FIXTURE_ROOT/rendered"
mkdir -p "$RENDER_ROOT"
if command -v chezmoi >/dev/null 2>&1; then
  MAC_CONFIG="$FIXTURE_ROOT/mac_config.json"
  echo '{"data":{"setupCli":true,"setupAi":true,"aiMode":"local"}}' > "$MAC_CONFIG"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/ax/models.json.tmpl" >"$RENDER_ROOT/models.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_codex/config.toml.tmpl" >"$RENDER_ROOT/codex.toml"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/opencode/opencode.jsonc.tmpl" >"$RENDER_ROOT/opencode.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_omp/agent/APPEND_SYSTEM.md.tmpl" >"$RENDER_ROOT/omp-append-system.md"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/ax/omp-models.yml.tmpl" >"$RENDER_ROOT/omp-models.yml"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/crush/crush.json.tmpl" >"$RENDER_ROOT/crush.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/ai-tools/claude-mcp.json.tmpl" >"$RENDER_ROOT/claude-mcp.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_zed/settings.json.tmpl" >"$RENDER_ROOT/zed.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/cli-proxy-api/private_config.yaml.tmpl" >"$RENDER_ROOT/proxy.yaml"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/run_onchange_after_setup-ai-agent-platform.sh.tmpl" >"$RENDER_ROOT/setup-ai-agent-platform.sh"
  HOME="$HOME_DIR" chezmoi execute-template --config "$MAC_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/run_after_sync-nono-packs.sh.tmpl" >"$RENDER_ROOT/sync-nono-packs.sh"
  SKILL_SCRIPT_ROOT="$RENDER_ROOT/skill-creator/scripts"
  mkdir -p "$SKILL_SCRIPT_ROOT"
  for script_name in generate_report improve_description quick_validate run_eval run_loop utils; do
    if [[ -f "$HOME/.config/agents/skills/skill-creator/scripts/$script_name.py" ]]; then
      cp "$HOME/.config/agents/skills/skill-creator/scripts/$script_name.py" "$SKILL_SCRIPT_ROOT/$script_name.py"
    else
      touch "$SKILL_SCRIPT_ROOT/$script_name.py"
    fi
  done
  if jq -e . "$RENDER_ROOT"/*.json >/dev/null; then
    pass "all rendered client JSON documents parse"
  else
    fail "all rendered client JSON documents parse" "one or more rendered files are invalid"
  fi
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    yaml_check=(python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))')
  elif command -v ruby >/dev/null 2>&1; then
    yaml_check=(ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV[0]), aliases: false)')
  else
    yaml_check=()
  fi
  if ((${#yaml_check[@]} == 0)); then
    printf '# skip - no YAML reader available to parse the CLIProxyAPI render\n'
  elif "${yaml_check[@]}" "$RENDER_ROOT/proxy.yaml"; then
    pass "rendered CLIProxyAPI YAML parses"
  else
    fail "rendered CLIProxyAPI YAML parses" "invalid YAML"
  fi
  assert_contains "$(cat "$RENDER_ROOT/proxy.yaml")" 'host: "127.0.0.1"' "CLIProxyAPI binds only to IPv4 loopback"
  assert_contains "$(cat "$RENDER_ROOT/proxy.yaml")" 'codex:' "CLIProxyAPI renders Codex aliases alongside Antigravity aliases"
  assert_contains "$(cat "$RENDER_ROOT/proxy.yaml")" 'fork: true' "CLIProxyAPI preserves real upstream model names alongside canonical aliases"
  # Prefer a Python YAML reader; fall back to Ruby. Neither is managed by this
  # repository, so the check is skipped rather than failed when both are absent.
  PROXY_JSON=""
  if python3 -c 'import yaml' >/dev/null 2>&1; then
    PROXY_JSON="$(python3 -c 'import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$RENDER_ROOT/proxy.yaml")"
  elif command -v ruby >/dev/null 2>&1; then
    PROXY_JSON="$(ruby -ryaml -rjson -e 'print JSON.generate(YAML.safe_load(File.read(ARGV[0]), aliases: false))' "$RENDER_ROOT/proxy.yaml")"
  fi
  if [[ -z "$PROXY_JSON" ]]; then
    printf '# skip - no YAML reader available for the CLIProxyAPI render check\n'
  elif jq -e '
    [."oauth-model-alias"[] | .[]] as $aliases |
    ($aliases | length == 4) and
    ([$aliases[].alias] | sort == ["balanced", "fast", "frontier", "light"]) and
    all($aliases[]; .fork == true and ."force-mapping" == true) and
    ([$aliases[] | select(.name == .alias)] | length == 0)
  ' <<<"$PROXY_JSON" >/dev/null; then
    pass "CLIProxyAPI renders four non-conflicting forked role aliases"
  else
    fail "CLIProxyAPI renders four non-conflicting forked role aliases" "$PROXY_JSON"
  fi
  assert_not_contains "$(cat "$RENDER_ROOT/codex.toml")" 'model_providers.cliproxy' "direct Codex config does not define the ax-only gateway"
  assert_not_contains "$(cat "$RENDER_ROOT/opencode.json")" 'cliproxy' "direct OpenCode config does not select or define the ax-only gateway"
  assert_contains "$(cat "$RENDER_ROOT/opencode.json")" '/.config/agents/context/base.md"' "OpenCode loads the base context as an instruction file"
  assert_contains "$(cat "$RENDER_ROOT/opencode.json")" '"extensions": [".go"]' "OpenCode maps Go files to gopls"
  assert_contains "$(cat "$RENDER_ROOT/opencode.json")" '"extensions": [".ts",".tsx",".js",".jsx",".mjs",".cjs",".mts",".cts"]' "OpenCode maps JavaScript and TypeScript files to vtsls"
  assert_contains "$(cat "$RENDER_ROOT/omp-append-system.md")" 'Developer Environment — Base Context' "direct OMP receives the shared system context"
  assert_contains "$(cat "$RENDER_ROOT/omp-models.yml")" 'api: openai-responses' "ax gives OMP a Responses-compatible gateway provider"
  assert_not_contains "$(cat "$RENDER_ROOT/crush.json")" 'cliproxy' "direct Crush config does not select or define the ax-only gateway"
  assert_contains "$(cat "$RENDER_ROOT/crush.json")" '/.config/agents/context/base.md"' "Crush loads the base context through context_paths"
  assert_contains "$(cat "$RENDER_ROOT/claude-mcp.json")" '"@upstash/context7-mcp@2.1.1"' "local Claude MCP uses the supported Context7 server"
  assert_contains "$(cat "$RENDER_ROOT/zed.json")" '"host": "t3-dev"' "Zed renders the remote development SSH alias"
  if bash -n "$RENDER_ROOT/setup-ai-agent-platform.sh"; then
    pass "rendered AI platform setup script parses"
  else
    fail "rendered AI platform setup script parses" "invalid shell syntax"
  fi
  assert_contains "$(cat "$RENDER_ROOT/setup-ai-agent-platform.sh")" 'for agent in claude omp opencode' "Herdr installs integrations for the supported direct agents"
  if bash -n "$RENDER_ROOT/sync-nono-packs.sh"; then
    pass "rendered Nono pack synchronization script parses"
  else
    fail "rendered Nono pack synchronization script parses" "invalid shell syntax"
  fi
  NONO_PACK_SCRIPT="$(cat "$RENDER_ROOT/sync-nono-packs.sh")"
  assert_contains "$NONO_PACK_SCRIPT" "nolabs-ai/claude" "Nono sync installs the Claude pack from the nolabs-ai namespace"
  assert_contains "$NONO_PACK_SCRIPT" "nolabs-ai/omp" "Nono sync installs the OMP pack from the nolabs-ai namespace"
  assert_contains "$NONO_PACK_SCRIPT" "nolabs-ai/codex" "Nono sync installs the Codex pack from the nolabs-ai namespace"
  assert_contains "$NONO_PACK_SCRIPT" "nolabs-ai/opencode" "Nono sync installs the OpenCode pack from the nolabs-ai namespace"
  assert_contains "$NONO_PACK_SCRIPT" "retired_packs=(" "Nono sync declares a retired-pack list"
  assert_contains "$NONO_PACK_SCRIPT" "nono remove \"\$pack\"" "Nono sync prunes retired packs"
  if grep -A5 'retired_packs=(' <<<"$NONO_PACK_SCRIPT" | grep -qF 'always-further/claude'; then
    pass "Nono sync retires the migrated Claude pack"
  else
    fail "Nono sync retires the migrated Claude pack" "$NONO_PACK_SCRIPT"
  fi
  if [[ "$NONO_PACK_SCRIPT" != *"always-further/codex"* ]]; then
    pass "Nono sync leaves Codex unmanaged"
  else
    fail "Nono sync leaves Codex unmanaged" "$NONO_PACK_SCRIPT"
  fi
  assert_contains "$(chezmoi target-path --config "$MAC_CONFIG" --source "$REPO_ROOT" "$REPO_ROOT/dot_config/agents/skills/skill-creator/scripts/literal_run_eval.py")" "/run_eval.py" "chezmoi preserves the run_eval.py payload basename"
  assert_contains "$(chezmoi target-path --config "$MAC_CONFIG" --source "$REPO_ROOT" "$REPO_ROOT/dot_config/agents/skills/skill-creator/scripts/literal_run_loop.py")" "/run_loop.py" "chezmoi preserves the run_loop.py payload basename"
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

  REMOTE_CONFIG="$FIXTURE_ROOT/remote_config.json"
  echo '{"data":{"setupCli":true,"setupAi":true,"aiMode":"remote"}}' > "$REMOTE_CONFIG"
  HOME="$HOME_DIR" chezmoi execute-template --config "$REMOTE_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/ax/models.json.tmpl" >"$RENDER_ROOT/models-remote.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$REMOTE_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/opencode/opencode.jsonc.tmpl" >"$RENDER_ROOT/opencode-remote.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$REMOTE_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/ai-tools/claude-mcp.json.tmpl" >"$RENDER_ROOT/claude-mcp-remote.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$REMOTE_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/zed/settings.json.tmpl" >"$RENDER_ROOT/zed-remote.json"
  HOME="$HOME_DIR" chezmoi execute-template --config "$REMOTE_CONFIG" --source "$REPO_ROOT" <"$REPO_ROOT/dot_config/cli-proxy-api/private_config.yaml.tmpl" >"$RENDER_ROOT/proxy-remote.yaml"
  assert_contains "$(cat "$RENDER_ROOT/models-remote.json")" '"url": "http://cliproxyapi:8317"' "legacy remote aiMode still renders the sidecar gateway URL"
  assert_not_contains "$(cat "$RENDER_ROOT/opencode-remote.json")" 'cliproxy' "legacy remote config keeps the gateway scoped to ax"
  assert_contains "$(cat "$RENDER_ROOT/claude-mcp-remote.json")" '"@upstash/context7-mcp@2.1.1"' "remote Claude MCP uses the supported Context7 server"
  assert_contains "$(cat "$RENDER_ROOT/zed-remote.json")" '"@upstash/context7-mcp@2.1.1"' "remote Zed MCP uses the supported Context7 server"
  assert_contains "$(cat "$RENDER_ROOT/proxy-remote.yaml")" 'host: "127.0.0.1"' "local proxy configuration remains loopback-only"
else
  fail "chezmoi render tests" "chezmoi is not installed"
fi

if command -v nono >/dev/null 2>&1; then
  omp_pack_installed=false
  if nono list --installed 2>/dev/null | grep -qF $'nolabs-ai/omp\t'; then
    omp_pack_installed=true
  fi
  for profile_path in "$REPO_ROOT"/dot_config/nono/profiles/*.json; do
    if [[ "$(basename "$profile_path")" == "default-omp.json" && "$omp_pack_installed" == false ]]; then
      printf '# skip - nolabs-ai/omp is installed by chezmoi apply before effective validation\n'
      continue
    fi
    if nono profile validate "$profile_path" >/dev/null 2>&1; then
      pass "$(basename "$profile_path") passes nono profile validate"
    else
      fail "$(basename "$profile_path") passes nono profile validate" "invalid Nono profile"
    fi
  done
  if jq -e '
    .extends == "nolabs-ai/claude" and
    .security.capability_elevation == false and
    ([.groups.include[] | if type == "object" then .name else . end] |
      contains(["mise_manager", "bun_runtime", "go_runtime", "go_runtime_macos"])) and
    (.filesystem.allow | length == 3) and
    (.filesystem.read == ["$HOME/.config/agents/skills", "$HOME/.go", "$HOME/.local/state/fnm_multishells", "$HOME/.npm-global/bin"]) and
    (.filesystem.read_file | index("$HOME/.config/agents/context/ax-context.md")) != null and
    (.filesystem.suppress_save_prompt? == null)
  ' "$REPO_ROOT/dot_config/nono/profiles/default-claude.json" >/dev/null; then
    pass "Claude is a thin ax overlay on the official pack"
  else
    fail "Claude is a thin ax overlay on the official pack" "$(cat "$REPO_ROOT/dot_config/nono/profiles/default-claude.json")"
  fi

  # In the container the agents are npm-installed, so the binary nono execs
  # lives in ~/.npm-global/bin. nono grants the binary itself but not its
  # directory, and without read access there the sandbox dies with exit 127
  # before the agent ever starts. macOS misses this: Homebrew's prefix is
  # already covered by the official packs.
  npm_bin_missing=""
  for profile_path in "$REPO_ROOT"/dot_config/nono/profiles/default-{agent,claude,codex,opencode,omp}.json; do
    jq -e '[.filesystem.read[] | if type == "object" then .path else . end] |
      index("$HOME/.npm-global/bin")' "$profile_path" >/dev/null ||
      npm_bin_missing="$npm_bin_missing $(basename "$profile_path")"
  done
  if [[ -z "$npm_bin_missing" ]]; then
    pass "npm-installed agents can read their own bin directory in the sandbox"
  else
    fail "npm-installed agents can read their own bin directory in the sandbox" \
      "missing \$HOME/.npm-global/bin:$npm_bin_missing"
  fi
  if jq -e '
    .extends == "nolabs-ai/codex" and
    .security.capability_elevation == false and
    (.filesystem.read_file | index("$HOME/.config/agents/context/ax-context.md")) != null
  ' "$REPO_ROOT/dot_config/nono/profiles/default-codex.json" >/dev/null; then
    pass "Codex is a thin ax overlay on the nolabs-ai pack"
  else
    fail "Codex is a thin ax overlay on the nolabs-ai pack" "$(cat "$REPO_ROOT/dot_config/nono/profiles/default-codex.json")"
  fi
  if jq -e '
    .extends == "nolabs-ai/omp" and .security.capability_elevation == false
  ' "$REPO_ROOT/dot_config/nono/profiles/default-omp.json" >/dev/null &&
    jq -e '
      .extends == "nolabs-ai/opencode" and .security.capability_elevation == false
    ' "$REPO_ROOT/dot_config/nono/profiles/default-opencode.json" >/dev/null; then
    pass "OMP and OpenCode inherit their official packs without interactive elevation"
  else
    fail "OMP and OpenCode inherit their official packs without interactive elevation" "official pack inheritance is missing"
  fi
  for profile in default-claude default-codex default-crush default-opencode default-omp; do
    profile_path="$REPO_ROOT/dot_config/nono/profiles/$profile.json"
    if jq -e '
      .security.signal_mode == "isolated" and
      .security.capability_elevation == false and
      ((.platform_overrides.linux.security.capability_elevation? // false) == false)
    ' "$profile_path" >/dev/null; then
      pass "$profile disables interactive capability elevation on every platform"
    else
      fail "$profile disables interactive capability elevation on every platform" "$(cat "$profile_path")"
    fi
  done
  if jq -e '
    any(.filesystem.allow[]; type == "object" and .path == "$HOME/.local/share/crush" and .when == "macos") and
    any(.filesystem.allow[]; type == "object" and .path == "$HOME/.local/share/crush/sessions" and .when == "linux") and
    any(.filesystem.read[]; type == "object" and .path == "$HOME/.config/crush" and .when == "macos")
  ' "$REPO_ROOT/dot_config/nono/profiles/default-crush.json" >/dev/null; then
    pass "Crush splits state grants by platform"
  else
    fail "Crush splits state grants by platform" "$(cat "$REPO_ROOT/dot_config/nono/profiles/default-crush.json")"
  fi
  if jq -e '
    .extends == "default" and
    ([.groups.include[] | if type == "object" then .name else . end] |
      contains(["node_runtime", "rust_runtime", "python_runtime", "mise_manager",
        "bun_runtime", "go_runtime", "go_runtime_macos", "user_caches_macos",
        "user_caches_linux", "linux_sysfs_read", "nix_runtime", "git_config"])) and
    (all(.filesystem.read[]; if type == "object" then .path != "/proc" else . != "/proc" end))
  ' "$REPO_ROOT/dot_config/nono/profiles/default-agent.json" >/dev/null; then
    pass "unpacked agents use Nono-maintained cross-platform runtime groups"
  else
    fail "unpacked agents use Nono-maintained cross-platform runtime groups" "$(cat "$REPO_ROOT/dot_config/nono/profiles/default-agent.json")"
  fi
  if jq -e '
    any(.filesystem.suppress_save_prompt[]; type == "object" and .path == "/proc" and .when == "linux")
  ' "$REPO_ROOT/dot_config/nono/profiles/default-crush.json" >/dev/null; then
    pass "the unpacked Crush client suppresses unsafe procfs grant suggestions"
  else
    fail "the unpacked Crush client suppresses unsafe procfs grant suggestions" "missing suppress_save_prompt entry"
  fi
  if REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import json
import os
from pathlib import PurePosixPath

root = os.environ["REPO_ROOT"]
profile_names = ["default-agent", "default-claude", "default-crush", "default-opencode", "default-omp"]
profiles = {}
for name in profile_names:
    path = os.path.join(root, "dot_config", "nono", "profiles", f"{name}.json")
    with open(path) as stream:
        profiles[name] = json.load(stream)

def linux_paths(entries):
    paths = []
    for entry in entries or []:
        if isinstance(entry, str):
            paths.append(entry)
        elif isinstance(entry, dict) and entry.get("when") == "linux":
            paths.append(entry["path"])
    return paths

def merged(name):
    profile = profiles[name]
    filesystem = {key: [] for key in ("allow", "read", "write", "allow_file", "read_file", "write_file", "deny")}
    parent = profile.get("extends")
    if parent in profiles:
        filesystem = merged(parent)
    own = profile.get("filesystem", {})
    for key in filesystem:
        filesystem[key] = filesystem[key] + linux_paths(own.get(key, []))
    return filesystem

for name in profile_names[1:]:
    filesystem = merged(name)
    parents = filesystem["allow"] + filesystem["read"] + filesystem["write"]
    for denied in filesystem["deny"]:
        denied_path = PurePosixPath(denied)
        for parent in parents:
            parent_path = PurePosixPath(parent)
            if denied_path != parent_path and parent_path in denied_path.parents:
                raise SystemExit(f"{name}: deny {denied} overlaps Linux grant {parent}")
PY
  then
    pass "Linux profiles contain no Landlock deny-overlap"
  else
    fail "Linux profiles contain no Landlock deny-overlap" "platform-specific profile conflict"
  fi
  EFFECTIVE_PROFILE="$(nono profile show "$REPO_ROOT/dot_config/nono/profiles/default-opencode.json" --json)"
  assert_contains "$EFFECTIVE_PROFILE" '"block": false' "effective policy permits general developer networking"
  assert_contains "$EFFECTIVE_PROFILE" "\"\$HOME/.config/agents/context/ax-context.md\"" "effective policy grants read-only session context access"
  assert_contains "$EFFECTIVE_PROFILE" "\"\$HOME/.npm/_cacache\"" "effective policy permits npm package cache writes"
  assert_contains "$EFFECTIVE_PROFILE" '8317' "effective policy permits the local CLIProxy port"
  if [[ "$omp_pack_installed" == true ]]; then
    OMP_EFFECTIVE="$(nono profile show "$REPO_ROOT/dot_config/nono/profiles/default-omp.json" --json)"
    if jq -e '
      (.filesystem.allow | index("$HOME/.omp")) != null and
      .security.capability_elevation == false
    ' <<<"$OMP_EFFECTIVE" >/dev/null; then
      pass "OMP inherits complete client state access from the official pack"
    else
      fail "OMP inherits complete client state access from the official pack" "$OMP_EFFECTIVE"
    fi
  else
    printf '# skip - effective OMP policy requires the nolabs-ai/omp pack\n'
  fi
  CLAUDE_EFFECTIVE="$(nono profile show "$REPO_ROOT/dot_config/nono/profiles/default-claude.json" --json)"
  if jq -e '
    (.filesystem.allow | index("$HOME/.claude")) != null and
    (.filesystem.allow_file | index("$HOME/.claude.json")) != null and
    (.filesystem.allow_file | index("$HOME/.claude.json.lock")) != null and
    .security.capability_elevation == false
  ' <<<"$CLAUDE_EFFECTIVE" >/dev/null; then
    pass "Claude inherits complete client state access from the official pack"
  else
    fail "Claude inherits complete client state access from the official pack" "$CLAUDE_EFFECTIVE"
  fi
else
  fail "Nono profile tests" "nono is not installed"
fi

printf '1..%d\n' "$((PASS + FAIL))"
if ((FAIL > 0)); then
  printf '# %d test(s) failed\n' "$FAIL"
  exit 1
fi
