#!/usr/bin/env bash
set -euo pipefail

AX_BIN="$(cd "$(dirname "$0")/.." && pwd)/executable_ax"
CHEZMOI_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$CHEZMOI_DIR/dot_config/cli-proxy-api/models.env"

FAILED=0

assert_contains() {
  local output="$1"
  local expected="$2"
  local test_name="$3"
  if echo "$output" | grep -Fq "$expected"; then
    echo "  [PASS] $test_name"
  else
    echo "  [FAIL] $test_name"
    echo "    Expected output to contain: '$expected'"
    echo "    Actual output:"
    echo "$output"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== Seam 1: ax CLI Parameter Parsing & Subcommands ==="

# 1.1 ax --help
HELP_OUT="$("$AX_BIN" --help)"
assert_contains "$HELP_OUT" "ax — Unified Agent Executor" "ax --help displays usage header"
assert_contains "$HELP_OUT" "POSITIONAL PARAMETERS:" "ax --help displays positional params"

# 1.2 ax models
MODELS_OUT="$("$AX_BIN" models)"
assert_contains "$MODELS_OUT" "Active Subscription Model Mappings" "ax models displays mapping header"
assert_contains "$MODELS_OUT" "${GPT_OPUS_MODEL:-gpt-5-codex(high)}" "ax models contains default GPT opus model"
assert_contains "$MODELS_OUT" "${GEMINI_OPUS_MODEL:-claude-opus-4-6-thinking}" "ax models contains default Gemini opus model"

# 1.3 ax quota / ax q
QUOTA_OUT="$(DRY_RUN=1 "$AX_BIN" quota)"
assert_contains "$QUOTA_OUT" "CLI Proxy API Quota Dashboard:" "ax quota displays quota header"
assert_contains "$QUOTA_OUT" "Management Secret Key:" "ax quota displays management key"
assert_contains "$QUOTA_OUT" "http://127.0.0.1:8317/management.html#/quota" "ax quota displays target URL"

QUOTA_SHORT_OUT="$(DRY_RUN=1 "$AX_BIN" q)"
assert_contains "$QUOTA_SHORT_OUT" "CLI Proxy API Quota Dashboard:" "ax q displays quota header"

# 1.3 DRY_RUN default invocation (ax)
DRY_DEFAULT="$(DRY_RUN=1 "$AX_BIN")"
assert_contains "$DRY_DEFAULT" "AGENT=claude SUBSESSION=auto SANDBOX=safe" "ax default resolves agent=claude, subsession=auto, sandbox=safe"
assert_contains "$DRY_DEFAULT" "ANTHROPIC_BASE_URL=http://127.0.0.1:8317" "ax default exports base URL"
assert_contains "$DRY_DEFAULT" "EXEC: nono run --profile default-claude --allow-cwd -- claude" "ax default runs nono with default-claude profile"

# 1.4 DRY_RUN Pi agent (ax p)
DRY_PI="$(DRY_RUN=1 "$AX_BIN" p)"
assert_contains "$DRY_PI" "AGENT=pi SUBSESSION=auto SANDBOX=safe" "ax p resolves agent=pi"
assert_contains "$DRY_PI" "EXEC: nono run --profile default-pi --allow-cwd -- pi" "ax p runs nono with default-pi profile"

# 1.5 DRY_RUN GPT subsession (ax c gpt)
DRY_GPT="$(DRY_RUN=1 "$AX_BIN" c gpt)"
assert_contains "$DRY_GPT" "AGENT=claude SUBSESSION=gpt SANDBOX=safe" "ax c gpt resolves subsession=gpt"
assert_contains "$DRY_GPT" "ANTHROPIC_MODEL=${GPT_PRIMARY_MODEL:-gpt-5-codex}" "ax c gpt sets ANTHROPIC_MODEL to primary GPT model"

# 1.6 DRY_RUN Gemini subsession (ax c gemini)
DRY_GEMINI="$(DRY_RUN=1 "$AX_BIN" c gemini)"
assert_contains "$DRY_GEMINI" "AGENT=claude SUBSESSION=gemini SANDBOX=safe" "ax c gemini resolves subsession=gemini"
assert_contains "$DRY_GEMINI" "ANTHROPIC_DEFAULT_SONNET_MODEL=${GEMINI_SONNET_MODEL:-claude-sonnet-4-6}" "ax c gemini sets ANTHROPIC_DEFAULT_SONNET_MODEL to Gemini sonnet model"

# 1.7 DRY_RUN direct mode (ax c auto direct)
DRY_DIRECT="$(DRY_RUN=1 "$AX_BIN" c auto direct)"
assert_contains "$DRY_DIRECT" "AGENT=claude SUBSESSION=auto SANDBOX=direct" "ax c auto direct resolves sandbox=direct"
assert_contains "$DRY_DIRECT" "EXEC: claude" "ax direct executes binary directly without nono"

# 1.8 Extra arguments pass through (ax c auto safe --resume)
DRY_EXTRA="$(DRY_RUN=1 "$AX_BIN" c auto safe --resume)"
assert_contains "$DRY_EXTRA" "EXEC: nono run --profile default-claude --allow-cwd -- claude --resume" "ax extra args pass through to agent"

# 1.9 Local .nono.json detection
TMP_DIR="$(mktemp -d)"
touch "$TMP_DIR/.nono.json"
DRY_LOCAL="$(cd "$TMP_DIR" && DRY_RUN=1 "$AX_BIN")"
assert_contains "$DRY_LOCAL" "EXEC: nono run --profile .nono.json --allow-cwd -- claude" "ax safe mode uses .nono.json when present in CWD"
rm -rf "$TMP_DIR"

echo "=== Seam 2: Nono Profile Validation & Credential Isolation ==="

CLAUDE_PROFILE="$CHEZMOI_DIR/dot_config/nono/profiles/default-claude.json"
PI_PROFILE="$CHEZMOI_DIR/dot_config/nono/profiles/default-pi.json"

VALIDATE_CLAUDE="$(nono profile validate "$CLAUDE_PROFILE")"
assert_contains "$VALIDATE_CLAUDE" "Result: valid" "default-claude.json passes nono profile validate"

VALIDATE_PI="$(nono profile validate "$PI_PROFILE")"
assert_contains "$VALIDATE_PI" "Result: valid" "default-pi.json passes nono profile validate"

# Check credential isolation: cli-proxy-api must NOT be in filesystem.read or filesystem.allow
if grep -q "cli-proxy-api" "$CLAUDE_PROFILE" "$PI_PROFILE"; then
  echo "  [FAIL] default-claude and default-pi must not grant access to cli-proxy-api"
  FAILED=$((FAILED + 1))
else
  echo "  [PASS] default-claude and default-pi exclude cli-proxy-api access"
fi

# Check skill directory access
assert_contains "$(cat "$CLAUDE_PROFILE")" '$HOME/.config/agents/skills/' "default-claude.json grants access to ~/.config/agents/skills/"
assert_contains "$(cat "$PI_PROFILE")" '$HOME/.config/agents/skills/' "default-pi.json grants access to ~/.config/agents/skills/"

echo "=== Seam 3: CLI Proxy API Config & Models Environment ==="

CONFIG_YAML="$CHEZMOI_DIR/dot_config/cli-proxy-api/config.yaml"
assert_contains "$(cat "$CONFIG_YAML")" 'strategy: "fill-first"' "config.yaml uses fill-first routing strategy"
assert_contains "$(cat "$CONFIG_YAML")" 'session-affinity: true' "config.yaml enables session-affinity"
assert_contains "$(cat "$CONFIG_YAML")" 'session-affinity-ttl: "24h"' "config.yaml sets 24h session affinity TTL"

MODELS_ENV="$CHEZMOI_DIR/dot_config/cli-proxy-api/models.env"
MODELS_ENV_CONTENT="$(cat "$MODELS_ENV")"
assert_contains "$MODELS_ENV_CONTENT" "GPT_OPUS_MODEL" "models.env defines GPT_OPUS_MODEL"
assert_contains "$MODELS_ENV_CONTENT" "GEMINI_OPUS_MODEL" "models.env defines GEMINI_OPUS_MODEL"

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL TESTS PASSED SUCCESSFULLY!"
  exit 0
else
  echo "TEST SUITE FAILED WITH $FAILED FAILURE(S)"
  exit 1
fi
