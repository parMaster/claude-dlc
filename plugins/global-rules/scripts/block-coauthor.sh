#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks a "Co-Authored-By" tag line in a `git
# commit`/`git commit --amend` or `gh pr create`/`gh pr edit` invocation.
#
# This repo's CLAUDE.md says never to include one, but Claude Code's own
# attribution system-reminder tells the model to add a Co-Authored-By line
# to every commit and PR — the two conflict, and the reminder says the
# user's own instructions win, but that depends on the model noticing the
# conflict every single time. This hook is the systematic backstop.

COMMAND=$(jq -r '.tool_input.command // empty')

if [[ -n "$COMMAND" ]] \
  && echo "$COMMAND" | grep -Eq '(^|[[:space:];&|(`])git[[:space:]]+commit([[:space:]]|$)|(^|[[:space:];&|(`])gh[[:space:]]+pr[[:space:]]+(create|edit)([[:space:]]|$)' \
  && echo "$COMMAND" | grep -Eqi 'co-authored-by'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "This repo CLAUDE.md rule disallows a Co-Authored-By line in commit messages or PR descriptions. Remove it and retry."
    }
  }'
fi

exit 0
