#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ONE="$REPO_ROOT/dot_local/bin/executable_one"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/one-test.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

FAKE_BIN="$FIXTURE_ROOT/bin"
HOME_DIR="$FIXTURE_ROOT/home"
mkdir -p "$FAKE_BIN" "$HOME_DIR"

TEST_COUNT=0
pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  printf 'ok %d - %s\n' "$TEST_COUNT" "$1"
}

fail() {
  TEST_COUNT=$((TEST_COUNT + 1))
  printf 'not ok %d - %s\n' "$TEST_COUNT" "$1"
  if [[ -n "${2:-}" ]]; then
    printf '%s\n' "$2" | sed 's/^/  # /'
  fi
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

run_one() {
  HOME="$HOME_DIR" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    "$ONE" "$@"
}

# Create fake tools for testing
cat >"$FAKE_BIN/mise" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "prune" ]]; then
  echo "mise prune executed"
elif [[ "$1" == "cache" && "$2" == "clean" ]]; then
  echo "mise cache clean executed"
fi
SH

cat >"$FAKE_BIN/uv" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "cache" && "$2" == "clean" ]]; then
  echo "uv cache clean executed"
fi
SH

cat >"$FAKE_BIN/cargo" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "clean-all" ]]; then
  echo "cargo clean-all executed: $*"
fi
SH

cat >"$FAKE_BIN/npkill" <<'SH'
#!/usr/bin/env bash
echo "npkill executed: $*"
SH

chmod +x "$FAKE_BIN/mise" "$FAKE_BIN/uv" "$FAKE_BIN/cargo" "$FAKE_BIN/npkill"

printf 'TAP version 13\n'

# 1. Help & Usage
OUTPUT="$(run_one)"
assert_contains "$OUTPUT" "one — unified developer cleanup CLI" "no args shows help message"
assert_contains "$OUTPUT" "Subcommands:" "help includes subcommands overview"

OUTPUT="$(run_one help)"
assert_contains "$OUTPUT" "one system" "one help shows usage details"

OUTPUT="$(run_one --help)"
assert_contains "$OUTPUT" "one project" "one --help shows usage details"

# 2. List Command
OUTPUT="$(run_one list)"
assert_contains "$OUTPUT" "Available Cleaners:" "one list shows available cleaners"
assert_contains "$OUTPUT" "[DEEP]" "one list highlights deep cleaners"
assert_contains "$OUTPUT" "mise" "one list includes mise cleaner"
assert_contains "$OUTPUT" "node" "one list includes node cleaner"

# 3. Doctor Command
OUTPUT="$(run_one doctor)"
assert_contains "$OUTPUT" "one doctor — System Cleanup Diagnostics" "one doctor header displayed"
assert_contains "$OUTPUT" "mise:" "one doctor checks mise tool status"
assert_contains "$OUTPUT" "npkill:" "one doctor checks npkill tool status"

# 4. System Cleanup Dry Run
OUTPUT="$(run_one system --dry-run)"
assert_contains "$OUTPUT" "Selected Cleaners Preview:" "system dry-run shows preview"
assert_contains "$OUTPUT" "[dry-run] Dry run active" "system dry-run displays dry run message"

# 5. Filtering with --only
OUTPUT="$(run_one system --dry-run --only mise,python)"
assert_contains "$OUTPUT" "mise" "system --only includes specified cleaner mise"
assert_contains "$OUTPUT" "python" "system --only includes specified cleaner python"
if [[ "$OUTPUT" != *"[System] rust"* ]]; then
  pass "system --only excludes unselected cleaners"
else
  fail "system --only excludes unselected cleaners" "$OUTPUT"
fi

# 6. Invalid Cleaner --only
set +e
OUTPUT="$(run_one system --only invalid_cleaner 2>&1)"
STATUS=$?
set -e
assert_status 64 "$STATUS" "invalid --only cleaner fails with usage exit code 64"
assert_contains "$OUTPUT" "unknown system cleaner: invalid_cleaner" "error message names invalid cleaner"

# 7. Missing Tools Handling
NO_DEV_BIN="$FIXTURE_ROOT/no_dev_bin"
mkdir -p "$NO_DEV_BIN"
for tool in bash cat du cut awk grep find; do
  if command -v "$tool" >/dev/null 2>&1; then
    ln -s "$(command -v "$tool")" "$NO_DEV_BIN/$tool"
  fi
done

OUTPUT="$(PATH="$NO_DEV_BIN" "$ONE" system --dry-run)"
assert_contains "$OUTPUT" "Unavailable" "missing tools reported as Unavailable"
assert_contains "$OUTPUT" "Cleaners: 0 available" "reports 0 available cleaners when no tools present"

# 8. Confirmation Prompt Abort
OUTPUT="$(echo "n" | run_one system --only mise)"
assert_contains "$OUTPUT" "Aborted." "user typing 'n' aborts cleanup"

# 9. Confirmation Prompt Accept
OUTPUT="$(echo "y" | run_one system --only mise)"
assert_contains "$OUTPUT" "mise prune executed" "user typing 'y' executes cleanup"

# 10. Project Cleanup Detection (Node & Rust)
PROJ_DIR="$FIXTURE_ROOT/test_project"
mkdir -p "$PROJ_DIR/node_modules" "$PROJ_DIR/target"
touch "$PROJ_DIR/package.json" "$PROJ_DIR/Cargo.toml"

OUTPUT="$(run_one project "$PROJ_DIR" --dry-run)"
assert_contains "$OUTPUT" "[Project] node" "project command detects node project"
assert_contains "$OUTPUT" "[Project] rust" "project command detects rust project"

# 11. Paths with spaces
SPACE_DIR="$FIXTURE_ROOT/dir with spaces/sub project"
mkdir -p "$SPACE_DIR/node_modules"
touch "$SPACE_DIR/package.json"

OUTPUT="$(run_one project "$SPACE_DIR" --dry-run)"
assert_contains "$OUTPUT" "dir with spaces/sub project" "project command handles paths with spaces"

# 12. Non-existent directory
set +e
OUTPUT="$(run_one project "$FIXTURE_ROOT/nonexistent" 2>&1)"
STATUS=$?
set -e
assert_status 64 "$STATUS" "non-existent project path fails with usage status 64"

# 13. Partial Failure Handling & Exit Code
cat >"$FAKE_BIN/failing_mise" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "prune" ]]; then
  echo "failing mise prune error" >&2
  exit 1
fi
SH
chmod +x "$FAKE_BIN/failing_mise"

set +e
OUTPUT="$(PATH="$FAKE_BIN:$PATH" mise="$FAKE_BIN/failing_mise" run_one system --yes --only mise,python 2>&1)"
STATUS=$?
set -e

# Test fake failing cleaner directly by overriding PATH with failing mise
cat >"$FAKE_BIN/mise" <<'SH'
#!/usr/bin/env bash
echo "failing mise error" >&2
exit 1
SH

set +e
OUTPUT="$(run_one system --yes --only mise,python 2>&1)"
STATUS=$?
set -e
assert_status 1 "$STATUS" "partial failure exits with status code 1"
assert_contains "$OUTPUT" "failing mise error" "failing cleaner error output captured"
assert_contains "$OUTPUT" "uv cache clean executed" "independent cleaner continues despite prior failure"
assert_contains "$OUTPUT" "Cleanup finished with failures:" "failure summary printed"

printf 'All tests completed.\n'
