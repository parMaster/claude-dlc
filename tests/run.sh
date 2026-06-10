#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Simulated CLAUDE_PLUGIN_ROOT — matches the path structure the scripts expect:
# .../plugins/cache/<marketplace>/<plugin>/<version>
FAKE_PLUGIN_ROOT_BASE="/tmp/claude-dlc-test/plugins/cache"
STATUSLINE_ROOT="${FAKE_PLUGIN_ROOT_BASE}/parmaster-claude-dlc/statusline/1.0.3"
GLOBALRULES_ROOT="${FAKE_PLUGIN_ROOT_BASE}/parmaster-claude-dlc/global-rules/1.0.1"

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then pass "$desc"; else fail "$desc (expected: '$expected', got: '$actual')"; fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then pass "$desc"; else fail "$desc (expected to contain: '$needle')"; fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then fail "$desc (expected NOT to contain: '$needle')"; else pass "$desc"; fi
}

run_setup() {
  local script="$1" plugin_root="$2"
  HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$plugin_root" bash "$script"
}

# ---------------------------------------------------------------------------
# statusline/setup.sh
# ---------------------------------------------------------------------------

STATUSLINE_SCRIPT="${REPO_ROOT}/plugins/statusline/scripts/setup.sh"
STABLE_STATUSLINE="${FAKE_PLUGIN_ROOT_BASE%/cache}/marketplaces/parmaster-claude-dlc/plugins/statusline/scripts/statusline.sh"

echo "statusline/setup.sh"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
echo '{}' > "${TEST_HOME}/.claude/settings.json"
run_setup "$STATUSLINE_SCRIPT" "$STATUSLINE_ROOT"
result=$(jq -r '.statusLine.command // ""' "${TEST_HOME}/.claude/settings.json")
assert_contains "writes statusLine when settings.json exists" "statusline.sh" "$result"
rm -rf "$TEST_HOME"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
EXPECTED_CMD="bash ${STABLE_STATUSLINE}"
jq --arg cmd "$EXPECTED_CMD" '.statusLine = {"type":"command","command":$cmd}' <<< '{}' > "${TEST_HOME}/.claude/settings.json"
run_setup "$STATUSLINE_SCRIPT" "$STATUSLINE_ROOT"
result=$(jq -r '.statusLine.command' "${TEST_HOME}/.claude/settings.json")
assert_eq "skips if statusLine already correct (idempotent)" "$EXPECTED_CMD" "$result"
rm -rf "$TEST_HOME"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
echo '{"statusLine":{"type":"command","command":"bash /usr/local/bin/my-statusline.sh"}}' > "${TEST_HOME}/.claude/settings.json"
run_setup "$STATUSLINE_SCRIPT" "$STATUSLINE_ROOT"
result=$(jq -r '.statusLine.command' "${TEST_HOME}/.claude/settings.json")
assert_eq "skips if user has non-plugin statusLine" "bash /usr/local/bin/my-statusline.sh" "$result"
rm -rf "$TEST_HOME"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
run_setup "$STATUSLINE_SCRIPT" "$STATUSLINE_ROOT"
assert_not_contains "skips if settings.json missing" "statusLine" "$(ls "${TEST_HOME}/.claude/")"
rm -rf "$TEST_HOME"

# ---------------------------------------------------------------------------
# global-rules/setup.sh
# ---------------------------------------------------------------------------

GLOBALRULES_SCRIPT="${REPO_ROOT}/plugins/global-rules/scripts/setup.sh"
STABLE_RULES="${FAKE_PLUGIN_ROOT_BASE%/cache}/marketplaces/parmaster-claude-dlc/plugins/global-rules/CLAUDE.md"
IMPORT_LINE="@${STABLE_RULES}"

echo "global-rules/setup.sh"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
echo "# existing content" > "${TEST_HOME}/.claude/CLAUDE.md"
run_setup "$GLOBALRULES_SCRIPT" "$GLOBALRULES_ROOT"
result=$(cat "${TEST_HOME}/.claude/CLAUDE.md")
assert_contains "appends @import line" "$IMPORT_LINE" "$result"
assert_contains "preserves existing content" "# existing content" "$result"
rm -rf "$TEST_HOME"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
run_setup "$GLOBALRULES_SCRIPT" "$GLOBALRULES_ROOT"
assert_eq "creates CLAUDE.md if missing" "0" "$([ -f "${TEST_HOME}/.claude/CLAUDE.md" ] && echo 0 || echo 1)"
assert_contains "writes @import into freshly created CLAUDE.md" "$IMPORT_LINE" "$(cat "${TEST_HOME}/.claude/CLAUDE.md")"
rm -rf "$TEST_HOME"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
echo "$IMPORT_LINE" > "${TEST_HOME}/.claude/CLAUDE.md"
run_setup "$GLOBALRULES_SCRIPT" "$GLOBALRULES_ROOT"
count=$(grep -cF "$IMPORT_LINE" "${TEST_HOME}/.claude/CLAUDE.md")
assert_eq "skips if @import already present (idempotent)" "1" "$count"
rm -rf "$TEST_HOME"

# ---------------------------------------------------------------------------

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
