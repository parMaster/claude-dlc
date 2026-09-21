#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks attribution lines — "Co-Authored-By" or a
# claude.ai session link ("Claude-Session:" trailer on commits, bare URL on
# PR descriptions) — in a `git commit`/`git commit --amend` or
# `gh pr create`/`gh pr edit` invocation.
#
# This repo's CLAUDE.md says never to include a Co-Authored-By line, and the
# user doesn't want session links either, but Claude Code's own attribution
# system-reminder tells the model to add them to every commit and PR — the
# two conflict, and the reminder says the user's own instructions win, but
# that depends on the model noticing the conflict every single time. This
# hook is the systematic backstop.

COMMAND=$(jq -r '.tool_input.command // empty')

if [[ -n "$COMMAND" ]] \
  && echo "$COMMAND" | grep -Eq '(^|[[:space:];&|(`])git[[:space:]]+commit([[:space:]]|$)|(^|[[:space:];&|(`])gh[[:space:]]+pr[[:space:]]+(create|edit)([[:space:]]|$)' \
  && echo "$COMMAND" | grep -Eqi 'co-authored-by|claude-session:|claude\.ai/code/session_'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Commit messages and PR descriptions must not carry attribution lines: no Co-Authored-By, no Claude-Session trailer, no claude.ai session link. Remove it and retry."
    }
  }'
fi

exit 0
