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
# global-rules/block-root-find.sh
# ---------------------------------------------------------------------------

BLOCK_ROOT_FIND_SCRIPT="${REPO_ROOT}/plugins/global-rules/scripts/block-root-find.sh"

run_hook() {
  local script="$1" command="$2"
  printf '%s' "$command" | jq -Rs '{tool_input:{command: .}}' | bash "$script"
}

echo "global-rules/block-root-find.sh"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'gem_path=$(find / -type d -path "*bibook-rails-base-models*" -not -path "*/node_modules/*" 2>/dev/null | head -5); echo "$gem_path"')
assert_contains "blocks root find embedded in \$(...) assignment" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'find /')
assert_contains "blocks bare find / with no trailing args" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'find -H / -type f')
assert_contains "blocks find / with flags before the path" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'echo hi && find / -name foo.txt')
assert_contains "blocks find / chained after &&" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'echo `find / -name foo.txt`')
assert_contains "blocks find / inside backtick substitution" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'find /Users/gusto/go/src/claude-dlc -name "*.go"')
assert_eq "allows find rooted at a real absolute project path" "" "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'find . -name "*.go"')
assert_eq "allows relative find" "" "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'myfind / -name foo')
assert_eq "allows commands where find is a substring of a longer word" "" "$result"

result=$(run_hook "$BLOCK_ROOT_FIND_SCRIPT" 'grep -rn "find /" .')
assert_eq "allows unrelated commands merely mentioning find /" "" "$result"

# ---------------------------------------------------------------------------
# global-rules/block-coauthor.sh
# ---------------------------------------------------------------------------

BLOCK_COAUTHOR_SCRIPT="${REPO_ROOT}/plugins/global-rules/scripts/block-coauthor.sh"

echo "global-rules/block-coauthor.sh"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'git commit -m "fix bug

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"')
assert_contains "blocks git commit with a Co-Authored-By line" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'git commit --amend -m "msg Co-Authored-By: x"')
assert_contains "blocks git commit --amend with a Co-Authored-By line" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'gh pr create --title x --body "desc Co-Authored-By: Claude"')
assert_contains "blocks gh pr create with a Co-Authored-By line" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'gh pr edit 5 --body "desc Co-Authored-By: Claude"')
assert_contains "blocks gh pr edit with a Co-Authored-By line" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'echo hi && git commit -m "hi Co-Authored-By: x"')
assert_contains "blocks a Co-Authored-By commit chained after &&" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'git commit -m "plain message"')
assert_eq "allows a git commit with no Co-Authored-By line" "" "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'git status')
assert_eq "allows unrelated git commands" "" "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'grep -rn "Co-Authored-By" .')
assert_eq "allows unrelated commands merely mentioning the phrase" "" "$result"

# ---------------------------------------------------------------------------
# Shared fake agtermctl for planning/agterm-spawn.sh and
# planning/agterm-handoff.sh (agterm-handoff.sh delegates to agterm-spawn.sh
# internally, so both sections exercise the same agtermctl surface).
# ---------------------------------------------------------------------------

AGTERM_FAKE_BIN="$(mktemp -d)"
cat > "${AGTERM_FAKE_BIN}/agtermctl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${AGTERMCTL_LOG}"
if [ "$1" = "session" ] && [ "$2" = "new" ]; then
  if [ -n "${AGTERMCTL_SESSION_NEW_JSON:-}" ]; then
    echo "$AGTERMCTL_SESSION_NEW_JSON"
  else
    echo '{"result":{"id":"fake-session-id"}}'
  fi
fi
for a in "$@"; do
  if [ "$a" = "--stdin" ]; then
    # Always drain stdin so `printf | agtermctl session type --stdin ...`
    # never dies of SIGPIPE, whether or not the caller wants the content
    # captured (AGTERMCTL_TYPED unset).
    if [ -n "${AGTERMCTL_TYPED:-}" ]; then
      cat >> "${AGTERMCTL_TYPED}"
      printf '\n' >> "${AGTERMCTL_TYPED}"
    else
      cat >/dev/null
    fi
  fi
done
EOF
chmod +x "${AGTERM_FAKE_BIN}/agtermctl"

# ---------------------------------------------------------------------------
# planning/agterm-session-new.sh
# ---------------------------------------------------------------------------

SESSION_NEW_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/agterm-session-new.sh"

echo "planning/agterm-session-new.sh"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SESSION_NEW_SCRIPT" "/tmp/some/dir" "My Session"
)
assert_eq "prints the session id on success" "fake-session-id" "$result"
assert_contains "creates the session in the current workspace when no workspace-name given" " --workspace ws-1" "$(cat "$LOG")"
assert_not_contains "does not pass --workspace-name when not grouping" " --workspace-name" "$(cat "$LOG")"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
rm -f "$LOG"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SESSION_NEW_SCRIPT" "/tmp/some/dir" "My Session" "my-workspace"
)
assert_contains "groups under a named workspace when given" " --workspace-name my-workspace --create-workspace" "$(cat "$LOG")"
rm -f "$LOG"

result=$(AGTERM_ENABLED="" bash "$SESSION_NEW_SCRIPT" "/tmp" "name" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset (exit code)" "exit:1" "$result"
assert_contains "refuses to run when AGTERM_ENABLED is unset (message)" "not available" "$result"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" AGTERMCTL_SESSION_NEW_JSON='{"result":{}}' \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SESSION_NEW_SCRIPT" "/tmp/some/dir" "My Session" 2>&1; echo "exit:$?"
)
assert_contains "refuses to run when session new returns no id (exit code)" "exit:1" "$result"
assert_contains "refuses to run when session new returns no id (message)" "session new failed to return a session id" "$result"
rm -f "$LOG"

# ---------------------------------------------------------------------------
# planning/agterm-spawn.sh
# ---------------------------------------------------------------------------

SPAWN_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/agterm-spawn.sh"

echo "planning/agterm-spawn.sh"

SPAWN_PROMPT_FILE="$(mktemp)"
echo "do the thing" > "$SPAWN_PROMPT_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$SPAWN_PROMPT_FILE"
)
assert_eq "prints the session name on success" "My Session" "$result"
assert_contains "creates the session in the current workspace when no workspace-name given" " --workspace ws-1" "$(cat "$LOG")"
assert_not_contains "does not pass --workspace-name when not grouping" " --workspace-name" "$(cat "$LOG")"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a claude launch command reading the prompt file" "claude \"\$(cat ${SPAWN_PROMPT_FILE}" "$TYPED_CMD"
assert_not_contains "does not type the prompt text itself" "do the thing" "$TYPED_CMD"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$SPAWN_PROMPT_FILE" "my-workspace"
)
assert_contains "groups under a named workspace when given" " --workspace-name my-workspace --create-workspace" "$(cat "$LOG")"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$SPAWN_PROMPT_FILE" "" "--permission-mode acceptEdits"
)
assert_contains "inserts claude-flags into the launch command when given" 'claude --permission-mode acceptEdits "$(cat ' "$(cat "$TYPED")"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$SPAWN_SCRIPT" "/tmp" "name" "$SPAWN_PROMPT_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset (exit code)" "exit:1" "$result"
assert_contains "refuses to run when AGTERM_ENABLED is unset (message)" "not available" "$result"

result=$(AGTERM_ENABLED="1" PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp" "name" "/nonexistent/prompt-file" 2>&1; echo "exit:$?")
assert_contains "refuses to run when the prompt file doesn't exist (exit code)" "exit:1" "$result"
assert_contains "refuses to run when the prompt file doesn't exist (message)" "prompt file not found" "$result"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" AGTERMCTL_SESSION_NEW_JSON='{"result":{}}' \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$SPAWN_PROMPT_FILE" 2>&1; echo "exit:$?"
)
assert_contains "refuses to run when session new returns no id (exit code)" "exit:1" "$result"
assert_contains "refuses to run when session new returns no id (message)" "session new failed to return a session id" "$result"
rm -f "$LOG"

rm -f "$SPAWN_PROMPT_FILE"

# ---------------------------------------------------------------------------
# planning/codex-spawn.sh
# ---------------------------------------------------------------------------

CODEX_SPAWN_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/codex-spawn.sh"

echo "planning/codex-spawn.sh"

CODEX_SPAWN_PROMPT_FILE="$(mktemp)"
echo "do the thing" > "$CODEX_SPAWN_PROMPT_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$CODEX_SPAWN_PROMPT_FILE"
)
assert_eq "prints the session name on success" "My Session" "$result"
assert_contains "creates the session in the current workspace when no workspace-name given" " --workspace ws-1" "$(cat "$LOG")"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a codex launch command reading the prompt file" "codex \"\$(cat ${CODEX_SPAWN_PROMPT_FILE}" "$TYPED_CMD"
assert_not_contains "does not type the prompt text itself" "do the thing" "$TYPED_CMD"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$CODEX_SPAWN_PROMPT_FILE" "my-workspace"
)
assert_contains "groups under a named workspace when given" " --workspace-name my-workspace --create-workspace" "$(cat "$LOG")"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$CODEX_SPAWN_PROMPT_FILE" "" "--sandbox workspace-write --ask-for-approval never"
)
assert_contains "inserts codex-flags into the launch command when given" 'codex --sandbox workspace-write --ask-for-approval never "$(cat ' "$(cat "$TYPED")"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$CODEX_SPAWN_SCRIPT" "/tmp" "name" "$CODEX_SPAWN_PROMPT_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset (exit code)" "exit:1" "$result"
assert_contains "refuses to run when AGTERM_ENABLED is unset (message)" "not available" "$result"

result=$(AGTERM_ENABLED="1" PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp" "name" "/nonexistent/prompt-file" 2>&1; echo "exit:$?")
assert_contains "refuses to run when the prompt file doesn't exist (exit code)" "exit:1" "$result"
assert_contains "refuses to run when the prompt file doesn't exist (message)" "prompt file not found" "$result"

rm -f "$CODEX_SPAWN_PROMPT_FILE"

# ---------------------------------------------------------------------------
# planning/agterm-handoff.sh
# ---------------------------------------------------------------------------

HANDOFF_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/agterm-handoff.sh"

echo "planning/agterm-handoff.sh"

TEST_REPO="$(mktemp -d)"
(cd "$TEST_REPO" && git init -q)
PLAN_FILE="${TEST_REPO}/docs/plans/2026-01-01-example.md"
mkdir -p "$(dirname "$PLAN_FILE")"
echo "# Example plan" > "$PLAN_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$HANDOFF_SCRIPT" "$PLAN_FILE"
)
assert_eq "prints the new session's display name on success" "Implement: example" "$result"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
assert_contains "creates the session before flagging" "session new" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a claude launch command reading a prompt file" 'claude --permission-mode acceptEdits "$(cat ' "$TYPED_CMD"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
assert_eq "the prompt file the typed command reads actually exists" "yes" "$([ -f "$PROMPT_PATH" ] && echo yes || echo no)"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt file references the plan path" "$PLAN_FILE" "$PROMPT_CONTENT"
assert_contains "prompt file tells the session to read the plan fully" "Read it fully" "$PROMPT_CONTENT"
assert_not_contains "prompt never mentions SendMessage callback" "SendMessage" "$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$HANDOFF_SCRIPT" "$PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"


# ---------------------------------------------------------------------------
# planning/codex-handoff.sh
# ---------------------------------------------------------------------------

CODEX_HANDOFF_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/codex-handoff.sh"

echo "planning/codex-handoff.sh"

CODEX_TEST_REPO="$(mktemp -d)"
(cd "$CODEX_TEST_REPO" && git init -q)
CODEX_PLAN_FILE="${CODEX_TEST_REPO}/docs/plans/2026-01-01-example.md"
mkdir -p "$(dirname "$CODEX_PLAN_FILE")"
echo "# Example plan" > "$CODEX_PLAN_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$CODEX_TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE"
)
assert_eq "prints the new session's display name on success" "Implement: example" "$result"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
assert_contains "creates the session before flagging" "session new" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a codex launch command with the accept-edits-equivalent flags" 'codex --sandbox workspace-write --ask-for-approval never "$(cat ' "$TYPED_CMD"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
assert_eq "the prompt file the typed command reads actually exists" "yes" "$([ -f "$PROMPT_PATH" ] && echo yes || echo no)"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt file references the plan path" "$CODEX_PLAN_FILE" "$PROMPT_CONTENT"
assert_contains "prompt file tells the session to read the plan fully" "Read it fully" "$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$CODEX_TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE" "gpt-5.1-codex"
)
assert_contains "appends --model when a model is given" 'codex --sandbox workspace-write --ask-for-approval never --model gpt-5.1-codex "$(cat ' "$(cat "$TYPED")"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"

rm -rf "$CODEX_TEST_REPO"

# ---------------------------------------------------------------------------
# planning/codex-review-handoff.sh
# ---------------------------------------------------------------------------

CODEX_REVIEW_HANDOFF_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/codex-review-handoff.sh"

echo "planning/codex-review-handoff.sh"

CODEX_REVIEW_TEST_REPO="$(mktemp -d)"
(cd "$CODEX_REVIEW_TEST_REPO" && git init -q)
CODEX_REVIEW_PLAN_FILE="${CODEX_REVIEW_TEST_REPO}/docs/plans/2026-01-01-example.md"
mkdir -p "$(dirname "$CODEX_REVIEW_PLAN_FILE")"
echo "# Example plan" > "$CODEX_REVIEW_PLAN_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$CODEX_REVIEW_TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_REVIEW_HANDOFF_SCRIPT" "$CODEX_REVIEW_PLAN_FILE"
)
assert_eq "prints the new session's display name on success" "Review: example" "$result"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
assert_contains "creates the session before flagging" "session new" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a codex launch command with workspace-write flags" 'codex --sandbox workspace-write --ask-for-approval never "$(cat ' "$TYPED_CMD"
assert_not_contains "never passes a --model flag" " --model" "$TYPED_CMD"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
assert_eq "the prompt file the typed command reads actually exists" "yes" "$([ -f "$PROMPT_PATH" ] && echo yes || echo no)"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt file references the plan path" "$CODEX_REVIEW_PLAN_FILE" "$PROMPT_CONTENT"
assert_contains "prompt file tells the session to review it thoroughly" "Review it thoroughly" "$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$CODEX_REVIEW_HANDOFF_SCRIPT" "$CODEX_REVIEW_PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"

rm -rf "$CODEX_REVIEW_TEST_REPO"

rm -rf "$AGTERM_FAKE_BIN" "$TEST_REPO"

# ---------------------------------------------------------------------------

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
