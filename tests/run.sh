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

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
run_setup "$GLOBALRULES_SCRIPT" "$GLOBALRULES_ROOT"
assert_eq "turns off commit/PR attribution" '{"commit":"","pr":""}' "$(jq -c '.attribution' "${TEST_HOME}/.claude/settings.json")"
rm -rf "$TEST_HOME"

TEST_HOME="$(mktemp -d)"
mkdir -p "${TEST_HOME}/.claude"
echo '{"attribution": true}' > "${TEST_HOME}/.claude/settings.json"
run_setup "$GLOBALRULES_SCRIPT" "$GLOBALRULES_ROOT"
assert_eq "keeps an existing attribution setting" "true" "$(jq -c '.attribution' "${TEST_HOME}/.claude/settings.json")"
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

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'git commit -m "fix bug

Claude-Session: https://claude.ai/code/session_01ABC"')
assert_contains "blocks git commit with a Claude-Session trailer" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'gh pr create --title x --body "desc

https://claude.ai/code/session_01ABC"')
assert_contains "blocks gh pr create with a bare claude.ai session link" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'gh pr edit 5 --body "desc https://claude.ai/code/session_01ABC"')
assert_contains "blocks gh pr edit with a bare claude.ai session link" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'git commit -m "plain message"')
assert_eq "allows a git commit with no Co-Authored-By line" "" "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'git status')
assert_eq "allows unrelated git commands" "" "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'grep -rn "Co-Authored-By" .')
assert_eq "allows unrelated commands merely mentioning the phrase" "" "$result"

result=$(run_hook "$BLOCK_COAUTHOR_SCRIPT" 'grep -rn "Claude-Session" .')
assert_eq "allows unrelated commands merely mentioning Claude-Session" "" "$result"

# ---------------------------------------------------------------------------
# global-rules/block-inline-edit.sh
# ---------------------------------------------------------------------------

BLOCK_INLINE_EDIT_SCRIPT="${REPO_ROOT}/plugins/global-rules/scripts/block-inline-edit.sh"

echo "global-rules/block-inline-edit.sh"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "python3 - <<'EOF'
p='internal/handler/subsidiaries_test.go'
s=open(p).read()
s=s.replace('a','b')
open(p,'w').write(s)
EOF
go test ./...")
assert_contains "blocks python heredoc that writes a file" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "python3 -c \"import pathlib; pathlib.Path('x.go').write_text('y')\"")
assert_contains "blocks python -c with write_text" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "node -e \"require('fs').writeFileSync('a.js','x')\"")
assert_contains "blocks node -e with writeFileSync" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "sed -i '' 's/foo/bar/' main.go")
assert_contains "blocks sed -i" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "sed -Ei 's/foo/bar/' main.go")
assert_contains "blocks sed with combined -Ei flags" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "gofmt -l . && sed --in-place 's/a/b/' x")
assert_contains "blocks sed --in-place chained after &&" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "perl -pi -e 's/foo/bar/' main.go")
assert_contains "blocks perl -pi on a code file" '"permissionDecision": "deny"' "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "perl -pi -e 's/- \[ \]/- [x]/ if /^### Task 2:/.../^### Task/' docs/plans/2026-09-25-x.md")
assert_eq "allows perl -pi checkbox ticking on a plan" "" "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "python3 -c 'import json,sys; print(json.load(sys.stdin)[\"a\"])' < f.json")
assert_eq "allows python -c that only reads" "" "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "python3 - <<'EOF'
print(open('f.txt').read())
EOF")
assert_eq "allows python heredoc that only reads" "" "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "sed -n '1,20p' main.go")
assert_eq "allows sed without -i" "" "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "perl -ne 'print if /x/' f")
assert_eq "allows perl without -i" "" "$result"

result=$(run_hook "$BLOCK_INLINE_EDIT_SCRIPT" "go test ./... | grep -v '^{'")
assert_eq "allows unrelated commands" "" "$result"

# ---------------------------------------------------------------------------
# global-rules/block-comment-refs.sh
# ---------------------------------------------------------------------------

BLOCK_COMMENT_REFS_SCRIPT="${REPO_ROOT}/plugins/global-rules/scripts/block-comment-refs.sh"
COMMENT_DIR="$(mktemp -d)"

run_edit() {
  jq -n --arg f "$1" --arg o "$2" --arg n "$3" \
    '{tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' | bash "$BLOCK_COMMENT_REFS_SCRIPT"
}

run_write() {
  jq -n --arg f "$1" --arg c "$2" \
    '{tool_name:"Write", tool_input:{file_path:$f, content:$c}}' | bash "$BLOCK_COMMENT_REFS_SCRIPT"
}

run_multi() {
  jq -n --arg f "$1" --arg o "$2" --arg n "$3" \
    '{tool_name:"MultiEdit", tool_input:{file_path:$f, edits:[{old_string:"x", new_string:"y"}, {old_string:$o, new_string:$n}]}}' \
    | bash "$BLOCK_COMMENT_REFS_SCRIPT"
}

echo "global-rules/block-comment-refs.sh"

DENY='"permissionDecision": "deny"'

result=$(run_edit main.go "x := 1" $'x := 1\n// PROJ-12: handle nil')
assert_contains "Edit: blocks a ticket ID in a Go comment" "$DENY" "$result"
assert_contains "deny reason names the matched ticket" 'ticket ID \"PROJ-12\"' "$result"
assert_contains "deny reason says to rewrite the comment" "Rewrite it" "$result"

result=$(run_edit app.py "x = 1" $'x = 1\n# see https://acme.atlassian.net/browse/ABC-9')
assert_contains "Edit: blocks a Jira link in a Python comment" "$DENY" "$result"

result=$(run_edit app.py "x = 1" $'x = 1\n# background: https://acme.atlassian.net/wiki/spaces/ENG/pages/123')
assert_contains "Edit: blocks a Confluence link with no ticket ID in it" 'link \"https://acme.atlassian.net' "$result"

result=$(run_edit run.sh "x=1" $'x=1\n# from https://github.com/o/r/pull/482')
assert_contains "Edit: blocks a GitHub PR link in a shell comment" "$DENY" "$result"

result=$(run_edit main.go "x" $'x\n\t// per docs/plans/2026-09-01-foo.md')
assert_contains "Edit: blocks a pointer to a plan doc" "$DENY" "$result"

result=$(run_edit main.go "x" $'x\n/* Slice B wires this up */')
assert_contains "Edit: blocks a slice marker" "$DENY" "$result"

result=$(run_edit main.go "x" $'x\n// reverted in 3fa9c2e')
assert_contains "Edit: blocks a commit SHA" "$DENY" "$result"

result=$(run_write "$COMMENT_DIR/new.go" $'package x\n\n// PROJ-7 workaround\nfunc F() {}')
assert_contains "Write: blocks a ticket ID in a new file" "$DENY" "$result"

result=$(run_multi main.ts "a" $'a\n// PROJ-3 fix')
assert_contains "MultiEdit: blocks a ticket ID in any of the edits" "$DENY" "$result"

result=$(run_edit main.go "x" $'x\n// UTF-8 input, SHA-256 digest, RFC-7231 dates, ISO-8601 times')
assert_eq "allows standard names shaped like ticket IDs" "" "$result"

result=$(run_edit main.go "x" $'x\nmsg := "PROJ-12 failed" // keep message stable')
assert_eq "allows ticket IDs outside comment lines" "" "$result"

result=$(run_edit main.go "x" $'x\n// retries 1234567 times at most, mask 0xdeadbeef')
assert_eq "allows plain numbers and 0x hex constants" "" "$result"

result=$(run_edit main.go "x" $'x\n// ids look like 550e8400-e29b-41d4-a716-446655440000')
assert_eq "allows UUIDs" "" "$result"

result=$(run_edit block.sh "x" $'x\n# Exception: `perl -i` on a plan under docs/plans/ is allowed')
assert_eq "allows a bare docs/plans/ path that is not a doc pointer" "" "$result"

result=$(run_edit README.md "x" $'x\n# PROJ-12 see docs/plans/2026-09-01-foo.md')
assert_eq "allows anything in Markdown files" "" "$result"

result=$(run_edit main.go $'// PROJ-12 old note\nx := 1' $'// PROJ-12 old note\nx := 2')
assert_eq "Edit: allows a bad comment already in old_string" "" "$result"

printf 'package x\n\n// PROJ-5 legacy\nfunc F() {}\n' > "$COMMENT_DIR/old.go"
result=$(run_write "$COMMENT_DIR/old.go" $'package x\n\n// PROJ-5 legacy\nfunc F() { return }')
assert_eq "Write: allows a bad comment already on disk" "" "$result"

result=$(run_edit main.go "x" $'x\n// retries twice because the upstream drops the first request')
assert_eq "allows a plain why-comment" "" "$result"

result=$(jq -n '{tool_name:"Bash", tool_input:{command:"echo PROJ-1"}}' | bash "$BLOCK_COMMENT_REFS_SCRIPT")
assert_eq "ignores other tools" "" "$result"

# ---------------------------------------------------------------------------
# Shared fake agtermctl for agterm/agterm-spawn.sh and
# agterm/agterm-handoff.sh (agterm-handoff.sh delegates to agterm-spawn.sh
# internally, so both sections exercise the same agtermctl surface).
# ---------------------------------------------------------------------------

AGTERM_FAKE_BIN="$(mktemp -d)"
cat > "${AGTERM_FAKE_BIN}/agtermctl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${AGTERMCTL_LOG}"
if [ "$1" = "session" ] && [ "$2" = "overlay" ] && [ "$3" = "result" ]; then
  # AGTERMCTL_RESULT_JSON unset = the overlay program is still running.
  if [ -n "${AGTERMCTL_RESULT_JSON:-}" ]; then echo "$AGTERMCTL_RESULT_JSON"; exit 0; fi
  echo '{"ok":false,"error":"overlay still running"}'
  exit 1
fi
if [ "$1" = "session" ] && [ "$2" = "overlay" ] && [ "$3" = "open" ] && [ -n "${AGTERMCTL_OPEN_ERROR:-}" ]; then
  echo "error: ${AGTERMCTL_OPEN_ERROR}" >&2
  exit 1
fi
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
# agterm/agterm-session-new.sh
# ---------------------------------------------------------------------------

SESSION_NEW_SCRIPT="${REPO_ROOT}/plugins/agterm/scripts/agterm-session-new.sh"

echo "agterm/agterm-session-new.sh"

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
# agterm/agterm-spawn.sh
# ---------------------------------------------------------------------------

SPAWN_SCRIPT="${REPO_ROOT}/plugins/agterm/scripts/agterm-spawn.sh"

echo "agterm/agterm-spawn.sh"

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
# agterm/codex-spawn.sh
# ---------------------------------------------------------------------------

CODEX_SPAWN_SCRIPT="${REPO_ROOT}/plugins/agterm/scripts/codex-spawn.sh"

echo "agterm/codex-spawn.sh"

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
# agterm/agterm-handoff.sh
# ---------------------------------------------------------------------------

HANDOFF_SCRIPT="${REPO_ROOT}/plugins/agterm/scripts/agterm-handoff.sh"

echo "agterm/agterm-handoff.sh"

TEST_REPO="$(mktemp -d)"
(cd "$TEST_REPO" && git init -q)
PLAN_FILE="${TEST_REPO}/docs/plans/2026-01-01-example.md"
mkdir -p "$(dirname "$PLAN_FILE")"
echo "# Example plan" > "$PLAN_FILE"

HANDOFF_HOME="$(mktemp -d)"
HANDOFF_MANAGED="$(mktemp -d)"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  HOME="$HANDOFF_HOME" CLAUDE_CONFIG_DIR="" CLAUDE_MANAGED_SETTINGS_DIR="$HANDOFF_MANAGED" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$HANDOFF_SCRIPT" "$PLAN_FILE"
)
assert_eq "prints the new session's display name on success" "Implement: example" "$result"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
assert_contains "creates the session before flagging" "session new" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a claude launch command in auto mode reading a prompt file" 'claude --permission-mode auto "$(cat ' "$TYPED_CMD"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
assert_eq "the prompt file the typed command reads actually exists" "yes" "$([ -f "$PROMPT_PATH" ] && echo yes || echo no)"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt file references the plan path" "$PLAN_FILE" "$PROMPT_CONTENT"
assert_contains "prompt file tells the session to read the plan fully" "Read it fully" "$PROMPT_CONTENT"
assert_not_contains "prompt never mentions SendMessage callback" "SendMessage" "$PROMPT_CONTENT"
NO_FOOTER_PROMPT="$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

# A parent name adds a report-back footer after the unchanged hand-off text.
LOG="$(mktemp)"
TYPED="$(mktemp)"
(
  cd "$TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  HOME="$HANDOFF_HOME" CLAUDE_CONFIG_DIR="" CLAUDE_MANAGED_SETTINGS_DIR="$HANDOFF_MANAGED" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$HANDOFF_SCRIPT" "$PLAN_FILE" "" "claude-dlc-8d" >/dev/null
)
TYPED_CMD="$(cat "$TYPED")"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_eq "prompt with a parent name starts with the unchanged hand-off text" \
  "$NO_FOOTER_PROMPT" "$(printf '%s\n' "$PROMPT_CONTENT" | head -n "$(printf '%s\n' "$NO_FOOTER_PROMPT" | wc -l)")"
assert_contains "footer names the parent session" "Spawned from Claude session claude-dlc-8d." "$PROMPT_CONTENT"
assert_contains "footer says how to report back" 'SendMessage (to: "claude-dlc-8d")' "$PROMPT_CONTENT"
assert_contains "footer reports only when asked" "When the task or the user asks you" "$PROMPT_CONTENT"
assert_eq "footer appears once" "1" "$(printf '%s\n' "$PROMPT_CONTENT" | grep -c 'Spawned from Claude session')"
rm -f "$LOG" "$TYPED"

# Each place an org can turn auto mode off falls back to accept-edits.
handoff_typed_with() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  echo '{"permissions":{"disableAutoMode":"disable"}}' > "$file"
  local log typed
  log="$(mktemp)"; typed="$(mktemp)"
  (
    cd "$TEST_REPO" && \
    AGTERMCTL_LOG="$log" AGTERMCTL_TYPED="$typed" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
    HOME="$HANDOFF_HOME" CLAUDE_CONFIG_DIR="" CLAUDE_MANAGED_SETTINGS_DIR="$HANDOFF_MANAGED" \
    PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$HANDOFF_SCRIPT" "$PLAN_FILE" "opus" >/dev/null
  )
  cat "$typed"
  rm -f "$file" "$log" "$typed"
}
for disabled_in in "${HANDOFF_MANAGED}/managed-settings.json" \
                   "${HANDOFF_MANAGED}/managed-settings.d/10-policy.json" \
                   "${HANDOFF_HOME}/.claude/remote-settings.json" \
                   "${HANDOFF_HOME}/.claude/settings.json" \
                   "${TEST_REPO}/.claude/settings.local.json"; do
  assert_contains "falls back to accept-edits when ${disabled_in##*/} disables auto mode" \
    'claude --permission-mode acceptEdits --model opus "$(cat ' "$(handoff_typed_with "$disabled_in")"
done
rm -rf "$HANDOFF_HOME" "$HANDOFF_MANAGED"

result=$(AGTERM_ENABLED="" bash "$HANDOFF_SCRIPT" "$PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"


# ---------------------------------------------------------------------------
# agterm/codex-handoff.sh
# ---------------------------------------------------------------------------

CODEX_HANDOFF_SCRIPT="${REPO_ROOT}/plugins/agterm/scripts/codex-handoff.sh"

echo "agterm/codex-handoff.sh"

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
assert_contains "types a codex launch command with the accept-edits-equivalent flags" 'codex --sandbox danger-full-access --ask-for-approval on-request "$(cat ' "$TYPED_CMD"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
assert_eq "the prompt file the typed command reads actually exists" "yes" "$([ -f "$PROMPT_PATH" ] && echo yes || echo no)"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt file references the plan path" "$CODEX_PLAN_FILE" "$PROMPT_CONTENT"
assert_contains "prompt file tells the session to read the plan fully" "Read it fully" "$PROMPT_CONTENT"
assert_not_contains "codex prompt has no report-back footer" "SendMessage" "$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$CODEX_TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE" "gpt-5.1-codex"
)
assert_contains "appends --model when a model is given" 'codex --sandbox danger-full-access --ask-for-approval on-request --model gpt-5.1-codex "$(cat ' "$(cat "$TYPED")"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"

rm -rf "$CODEX_TEST_REPO"

# ---------------------------------------------------------------------------
# agterm/overlay.sh
# ---------------------------------------------------------------------------

OVERLAY_SCRIPT="${REPO_ROOT}/plugins/agterm/scripts/overlay.sh"

echo "agterm/overlay.sh"

OVERLAY_REPO="$(mktemp -d)"
OVERLAY_REPO="$(cd "$OVERLAY_REPO" && pwd -P)"
mkdir -p "$OVERLAY_REPO/docs/plans/completed" "$OVERLAY_REPO/sub" "$OVERLAY_REPO/it's dir"
echo "# done" > "$OVERLAY_REPO/docs/plans/completed/old.md"
echo "<p>hi</p>" > "$OVERLAY_REPO/sub/page.html"
echo "# q" > "$OVERLAY_REPO/it's dir/a b.md"

# run_overlay <cwd> <args...>; AGTERMCTL_RESULT_JSON and OVERLAY_SID (session id, default sess-1) pass through from the caller.
run_overlay() {
  local dir="$1"; shift
  (cd "$dir" && AGTERMCTL_LOG="$LOG" AGTERM_SESSION_ID="${OVERLAY_SID-sess-1}" \
    PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$OVERLAY_SCRIPT" "$@" 2>&1; echo "exit:$?")
}

LOG="$(mktemp)"
result=$(run_overlay "$OVERLAY_REPO" md)
assert_contains "md with no arg falls back to docs/plans/completed/" "opened $OVERLAY_REPO/docs/plans/completed/old.md" "$result"
assert_contains "md opens glow -p through a login shell" "overlay open zsh -lc 'glow -p \"\$1\"' glow $OVERLAY_REPO/docs/plans/completed/old.md" "$(cat "$LOG")"
assert_contains "md targets the caller's session" " --target sess-1" "$(head -1 "$LOG")"
assert_contains "md sets --cwd to the file's directory" " --cwd $OVERLAY_REPO/docs/plans/completed" "$(head -1 "$LOG")"
: > "$LOG"

echo "# old" > "$OVERLAY_REPO/docs/plans/older.md"
touch -t 202001010000 "$OVERLAY_REPO/docs/plans/older.md"
echo "# new" > "$OVERLAY_REPO/docs/plans/newer.md"
result=$(run_overlay "$OVERLAY_REPO" md)
assert_contains "md with no arg picks the newest active plan by mtime" "opened $OVERLAY_REPO/docs/plans/newer.md" "$result"
: > "$LOG"

result=$(run_overlay "$OVERLAY_REPO/sub" md "../it's dir/a b.md")
assert_contains "md resolves a relative path with a quote and a space" "opened $OVERLAY_REPO/it's dir/a b.md" "$result"
assert_contains "md escapes the path for the shell" "glow it\\'s\\ dir/a\\ b.md" "$(sed "s|$OVERLAY_REPO/||" "$LOG")"
: > "$LOG"

result=$(AGTERMCTL_RESULT_JSON='{"result":{"exitCode":127},"ok":true}' run_overlay "$OVERLAY_REPO" md docs/plans/newer.md)
assert_contains "reports glow exiting right after opening" "glow exited with status 127" "$result"
assert_contains "glow failure exits 1" "exit:1" "$result"
: > "$LOG"

result=$(run_overlay "$OVERLAY_REPO/sub" html page.html)
assert_contains "html opens the absolute file" "overlay open --html $OVERLAY_REPO/sub/page.html --cwd $OVERLAY_REPO/sub --navigation" "$(cat "$LOG")"
assert_contains "html targets the caller's session" " --target sess-1" "$(cat "$LOG")"
: > "$LOG"

result=$(run_overlay "$OVERLAY_REPO/sub" html page.html --js)
assert_contains "html passes --js" "overlay open --html $OVERLAY_REPO/sub/page.html --cwd $OVERLAY_REPO/sub --navigation --js --size-percent 90 --target sess-1" "$(cat "$LOG")"
: > "$LOG"

result=$(run_overlay "$OVERLAY_REPO/sub" html page.html)
assert_not_contains "html without the flag keeps JavaScript off" "navigation --js" "$(cat "$LOG")"
: > "$LOG"

result=$(run_overlay "$OVERLAY_REPO" url http://localhost:5173/ --js)
assert_contains "url passes the url and --js" "overlay open --url http://localhost:5173/ --js --size-percent 90 --target sess-1" "$(cat "$LOG")"
: > "$LOG"

result=$(AGTERMCTL_OPEN_ERROR="overlay already open" run_overlay "$OVERLAY_REPO" url https://example.com/)
assert_contains "an overlay already open asks the user to close it" "close it (q or Cmd-W) and try again" "$result"
assert_contains "an overlay already open exits 1" "exit:1" "$result"
assert_not_contains "an overlay already open never closes it" "overlay close" "$(cat "$LOG")"
: > "$LOG"

result=$(AGTERMCTL_OPEN_ERROR="no such session: sess-1" run_overlay "$OVERLAY_REPO" url https://example.com/)
assert_contains "other agtermctl errors pass through" "agtermctl: error: no such session: sess-1" "$result"
: > "$LOG"

result=$(run_overlay "$OVERLAY_REPO" url localhost:5173)
assert_contains "url rejects a non-http(s)/file url" "not an http(s):// or file:// URL" "$result"
assert_eq "rejected url never calls agtermctl" "" "$(cat "$LOG")"

result=$(run_overlay "$OVERLAY_REPO" md missing.md)
assert_contains "missing file fails" "no such file: missing.md" "$result"
assert_eq "missing file never calls agtermctl" "" "$(cat "$LOG")"

result=$(OVERLAY_SID="" run_overlay "$OVERLAY_REPO" md)
assert_contains "refuses outside agterm" "not inside an agterm session" "$result"
assert_contains "outside agterm exits 1" "exit:1" "$result"
assert_eq "outside agterm never calls agtermctl" "" "$(cat "$LOG")"

rm -rf "$OVERLAY_REPO/docs/plans"/*.md "$OVERLAY_REPO/docs/plans/completed"/*.md
result=$(run_overlay "$OVERLAY_REPO" md)
assert_contains "no plans at all fails" "no plans found" "$result"

result=$(run_overlay "$OVERLAY_REPO" run htop)
assert_contains "unknown kind (run) is refused" "usage: overlay.sh" "$result"
assert_eq "unknown kind never calls agtermctl" "" "$(cat "$LOG")"

rm -rf "$OVERLAY_REPO" "$LOG"

# ---------------------------------------------------------------------------
# agterm/approve-overlay.sh
# ---------------------------------------------------------------------------

APPROVE_OVERLAY_SCRIPT="${REPO_ROOT}/plugins/agterm/scripts/approve-overlay.sh"
AGTERM_PLUGIN_ROOT="${FAKE_PLUGIN_ROOT_BASE}/parmaster-claude-dlc/agterm/1.0.0"

echo "agterm/approve-overlay.sh"

approve() { CLAUDE_PLUGIN_ROOT="$AGTERM_PLUGIN_ROOT" run_hook "$APPROVE_OVERLAY_SCRIPT" "$1"; }

for cmd in \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md \"docs/plans/x.md\"" \
  "bash $AGTERM_PLUGIN_ROOT/scripts/overlay.sh html page.html" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" html \"/tmp/backlog-dashboard-repo-123/index.html\" --js" \
  'bash "${CLAUDE_PLUGIN_ROOT}/scripts/overlay.sh" url "http://localhost:5173/" --js' \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md \"\""; do
  assert_contains "allows: $cmd" '"permissionDecision": "allow"' "$(approve "$cmd")"
done

for cmd in \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md; rm -rf ~" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md a.md && curl x" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md a.md || true" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md a.md | sh" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md \"\$(whoami).md\"" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md \`whoami\`" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md a.md > /tmp/x" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md \$HOME/a.md" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" md a.md
rm -rf ~" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" run htop" \
  "bash \"$AGTERM_PLUGIN_ROOT/scripts/overlay.sh\" mdx a.md" \
  "bash /tmp/evil/scripts/overlay.sh md a.md" \
  "agtermctl session overlay open htop --target x" \
  "ls -la"; do
  assert_eq "no decision: $cmd" "" "$(approve "$cmd")"
done

assert_eq "no decision without CLAUDE_PLUGIN_ROOT" "" \
  "$(CLAUDE_PLUGIN_ROOT="" run_hook "$APPROVE_OVERLAY_SCRIPT" "bash /scripts/overlay.sh md")"

rm -rf "$AGTERM_FAKE_BIN" "$TEST_REPO"

# ---------------------------------------------------------------------------
# planning/backlog-dashboard.sh
# ---------------------------------------------------------------------------

DASHBOARD_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/backlog-dashboard.sh"

echo "planning/backlog-dashboard.sh"

DASH_REPO="$(mktemp -d)"
DASH_REPO="$(cd "$DASH_REPO" && pwd -P)"
DASH_TMP="$(mktemp -d)"
dash_git() { git -C "$DASH_REPO" -c user.name=t -c user.email=t@example.com "$@"; }
# run_dashboard <cwd>
run_dashboard() { (cd "$1" && TMPDIR="$DASH_TMP" bash "$DASHBOARD_SCRIPT" 2>&1; echo "exit:$?"); }
# dash_item <file> <slug> <jq filter on the item>
dash_item() { sed -n '/id="backlog-data"/{n;p;}' "$1" | jq -c --arg s "$2" ".items[] | select(.slug == \$s) | $3"; }
dash_head() { sed -n '/id="backlog-data"/{n;p;}' "$1" | jq -c "$2"; }

dash_git init -q -b main
mkdir -p "$DASH_REPO/src/pkg/deep" "$DASH_REPO/docs"
printf 'one\ntwo\nthree\n' > "$DASH_REPO/src/pkg/deep/code.go"
echo "top" > "$DASH_REPO/Makefile"

result=$(run_dashboard "$DASH_REPO")
assert_contains "no docs/backlog/ is reported" "no docs/backlog/ in" "$result"
assert_contains "no docs/backlog/ exits 1" "exit:1" "$result"
assert_eq "no docs/backlog/ does not create it" "1" "$([ -d "$DASH_REPO/docs/backlog" ] && echo 0 || echo 1)"

mkdir -p "$DASH_REPO/docs/backlog"
cat > "$DASH_REPO/docs/backlog/good-where.md" <<'EOF'
---
worth: yes
where: src/pkg/deep/code.go:2
added: 2026-01-05
ticket: PROJ-7
---
# a good anchor

Body with </script><b>bold</b> & an ampersand.
EOF
cat > "$DASH_REPO/docs/backlog/gone-path.md" <<'EOF'
---
worth: later
where: src/removed.go:10
added: 2026-02-01
---
# path is gone
EOF
cat > "$DASH_REPO/docs/backlog/past-end.md" <<'EOF'
---
worth: no
where: src/pkg/deep/code.go:99
added: 2026-03-01
---
# line past the end
EOF
cat > "$DASH_REPO/docs/backlog/top-level.md" <<'EOF'
---
worth: yes
where: Makefile
added: 2026-03-02
---
# anchored to a top-level file
EOF
cat > "$DASH_REPO/docs/backlog/no-where.md" <<'EOF'
---
worth: yes
added: 2026-04-01
---
# not anchored
EOF
dash_git add -A
dash_git commit -q -m init
cat > "$DASH_REPO/docs/backlog/brand-new.md" <<'EOF'
---
worth: later
added: 2026-05-01
---
# never committed
EOF
echo "edited" >> "$DASH_REPO/docs/backlog/no-where.md"

result=$(run_dashboard "$DASH_REPO/src")
DASH_OUT=$(echo "$result" | head -1)
assert_contains "exits 0 with items" "exit:0" "$result"
assert_eq "prints the path of an existing file" "0" "$([ -f "$DASH_OUT" ] && echo 0 || echo 1)"
assert_contains "writes under the temp dir" "$DASH_TMP/backlog-dashboard-" "$DASH_OUT"
assert_not_contains "adds no file to the repo" "html" "$(dash_git status --porcelain)"
assert_eq "page keeps one data and one code script tag" "2" "$(grep -c '</script>' "$DASH_OUT")"

assert_eq "item carries its frontmatter and title" \
  '["a good anchor","yes","src/pkg/deep/code.go:2","PROJ-7","2026-01-05"]' \
  "$(dash_item "$DASH_OUT" good-where '[.title, .worth, .where, .ticket, .added]')"
assert_eq "body with markup round-trips" 'Body with </script><b>bold</b> & an ampersand.' \
  "$(sed -n '/id="backlog-data"/{n;p;}' "$DASH_OUT" | jq -r '.items[] | select(.slug == "good-where") | .body' | grep Body)"
assert_eq "good where: area is two segments, found, committed" '["src/pkg",false,false]' \
  "$(dash_item "$DASH_OUT" good-where '[.area, .whereMissing, .uncommitted]')"
assert_eq "committed item has a touched date" "true" "$(dash_item "$DASH_OUT" good-where '.touched | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")')"
assert_eq "missing path is flagged" "true" "$(dash_item "$DASH_OUT" gone-path '.whereMissing')"
assert_eq "line past the end is flagged" "true" "$(dash_item "$DASH_OUT" past-end '.whereMissing')"
assert_eq "top-level where: area is the file" '["Makefile",false]' "$(dash_item "$DASH_OUT" top-level '[.area, .whereMissing]')"
assert_eq "no where: unanchored, modified counts as uncommitted" '["unanchored",false,true]' \
  "$(dash_item "$DASH_OUT" no-where '[.area, .whereMissing, .uncommitted]')"
assert_eq "untracked item: uncommitted with no touched date" '[true,""]' "$(dash_item "$DASH_OUT" brand-new '[.uncommitted, .touched]')"
assert_eq "header: repo, count, branch, no warning without origin/HEAD" \
  "[\"$(basename "$DASH_REPO")\",6,\"main\",false]" "$(dash_head "$DASH_OUT" '[.repo, .count, .branch, .offDefault]')"
assert_eq "header: short commit" "$(dash_git rev-parse --short HEAD)" "$(dash_head "$DASH_OUT" '.commit' | tr -d '"')"

dash_git update-ref refs/remotes/origin/main HEAD
dash_git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
run_dashboard "$DASH_REPO" > /dev/null
assert_eq "on the default branch: no warning" '["main",false]' "$(dash_head "$DASH_OUT" '[.defaultBranch, .offDefault]')"
dash_git checkout -q -b feature
run_dashboard "$DASH_REPO" > /dev/null
assert_eq "off the default branch: warning on" '["feature","main",true]' "$(dash_head "$DASH_OUT" '[.branch, .defaultBranch, .offDefault]')"

DASH_PLAIN="$(mktemp -d)"
result=$(run_dashboard "$DASH_PLAIN")
assert_contains "outside a Git repo is reported" "not inside a Git repository" "$result"
assert_contains "outside a Git repo exits 1" "exit:1" "$result"

rm -rf "$DASH_REPO" "$DASH_TMP" "$DASH_PLAIN"

# ---------------------------------------------------------------------------

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
