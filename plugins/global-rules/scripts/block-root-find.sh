#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks `find` rooted at `/` — a full-filesystem scan.
#
# permissions.deny only splits a command on shell operators (&& ; | etc.) and
# can't see inside $(...) command substitution or a variable assignment, so a
# plain deny rule like "Bash(find /*)" misses commands like
# `path=$(find / -type d ...)`. This hook regex-matches the raw command
# string wherever the pattern occurs, closing that gap.

COMMAND=$(jq -r '.tool_input.command // empty')

PATTERN='(^|[[:space:];&|(`])find[[:space:]]+(-[A-Za-z]+[[:space:]]+)*/([[:space:]]|$)'

if [[ -n "$COMMAND" ]] && echo "$COMMAND" | grep -Eq "$PATTERN"; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Full-filesystem find (`find /...`) is blocked. Scope the search to a specific directory instead of the root filesystem."
    }
  }'
fi

exit 0
