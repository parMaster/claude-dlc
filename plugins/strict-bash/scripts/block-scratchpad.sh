#!/usr/bin/env bash
# PreToolUse hook (Bash): denies a command that names the session scratchpad,
# like /private/tmp/claude-501/-Users-me-repo/<session-id>/scratchpad/e2e.out.
# That path is wider than the screen, and the user reads every Bash call.
# session-start.sh tells Claude to use tmp/ in the repo instead; this hook
# only catches a drift back. It runs in every mode, because the problem is
# readability, not permission prompts.

COMMAND=$(jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# macOS shows both /tmp/claude-<uid> and /private/tmp/claude-<uid>.
if echo "$COMMAND" | grep -Eq '/tmp/claude-[0-9]+/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Do not use the scratchpad path in Bash commands: it is wider than the user'"'"'s screen. Write temp files to tmp/<name> at the repo root instead, like `make test > tmp/test.out 2>&1`. Git ignores tmp/. Create it first with `mkdir -p tmp` if it is missing."
    }
  }'
fi

exit 0
