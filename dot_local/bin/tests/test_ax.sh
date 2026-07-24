#!/usr/bin/env bash
set -euo pipefail

# Find directory of the script and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHEZMOI_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
AX_SCRIPT="$CHEZMOI_DIR/dot_local/bin/executable_ax"

# Text colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

FAILURES=0

assert_contains() {
  local output="$1"
  local expected="$2"
  local message="$3"
  
  if echo "$output" | grep -qF "$expected"; then
    echo -e "${GREEN}✓ PASS:${NC} $message"
  else
    echo -e "${RED}✗ FAIL:${NC} $message"
    echo -e "  Expected to find: '$expected'"
    echo -e "  In output:\n$output"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "Running Unit Tests for ax (Unified Agent Executor)"
echo "---------------------------------------------------"

# Test 1: Claude Code defaults (safe mode)
DRY_CLAUDE=$(DRY_RUN=1 "$AX_SCRIPT" c)
assert_contains "$DRY_CLAUDE" "AGENT=claude SANDBOX=safe" "ax c resolves agent=claude sandbox=safe"
assert_contains "$DRY_CLAUDE" "ANTHROPIC_MODEL=gemini-3.6-flash-high" "ax c sets ANTHROPIC_MODEL to gemini-3.6-flash-high"
assert_contains "$DRY_CLAUDE" "EXEC: nono run --profile default-claude --allow-cwd -- claude" "ax c runs nono with default-claude profile"

# Test 2: Claude Code direct mode
DRY_CLAUDE_DIRECT=$(DRY_RUN=1 "$AX_SCRIPT" c direct)
assert_contains "$DRY_CLAUDE_DIRECT" "AGENT=claude SANDBOX=direct" "ax c direct resolves sandbox=direct"
assert_contains "$DRY_CLAUDE_DIRECT" "EXEC: claude" "ax c direct skips nono sandbox wrapper"

# Test 3: OpenCode Agent
DRY_OPENCODE=$(DRY_RUN=1 "$AX_SCRIPT" o)
assert_contains "$DRY_OPENCODE" "AGENT=opencode SANDBOX=safe" "ax o resolves agent=opencode"
assert_contains "$DRY_OPENCODE" "HERDR_AGENT=opencode" "ax o sets HERDR_AGENT to opencode"
assert_contains "$DRY_OPENCODE" "EXEC: nono run --profile default-opencode --allow-cwd -- opencode" "ax o runs nono with default-opencode profile"

# Test 4: OpenCode Nono Profile Validation
echo ""
echo "Running Nono Profile Validation"
echo "---------------------------------------------------"
if command -v nono >/dev/null 2>&1; then
  # Check opencode profile
  OPENCODE_PROFILE="$CHEZMOI_DIR/dot_config/nono/profiles/default-opencode.json"
  VALIDATE_OPENCODE=$(nono profile validate "$OPENCODE_PROFILE" 2>&1 || true)
  assert_contains "$VALIDATE_OPENCODE" "Result: valid" "default-opencode.json passes nono profile validate"
else
  echo -e "⚠️  Skipping nono profile validation (nono CLI not installed)"
fi

echo "---------------------------------------------------"
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}All tests passed successfully!${NC}"
  exit 0
else
  echo -e "${RED}$FAILURES tests failed.${NC}"
  exit 1
fi
