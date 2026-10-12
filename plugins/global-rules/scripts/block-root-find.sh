#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks `find` rooted at `/` or at a home dir
# (`~`, `$HOME`, `/Users/<name>`, `/home/<name>`) — both scan far too much.
#
# permissions.deny only splits a command on shell operators (&& ; | etc.) and
# can't see inside $(...) command substitution or a variable assignment, so a
# plain deny rule like "Bash(find /*)" misses commands like
# `path=$(find / -type d ...)`. This hook regex-matches the raw command
# string wherever the pattern occurs, closing that gap.

COMMAND=$(jq -r '.tool_input.command // empty')

ROOTS='(/|/(Users|home)/?|/(Users|home)/[^/[:space:]"'"'"']+/?|/root/?|~/?|\$HOME/?|\$\{HOME\}/?)'
PATTERN='(^|[[:space:];&|(`])find[[:space:]]+(-[A-Za-z]+[[:space:]]+)*["'"'"']?'"$ROOTS"'["'"'"']?([[:space:];&|)`]|$)'

if [[ -n "$COMMAND" ]] && echo "$COMMAND" | grep -Eq "$PATTERN"; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "A find rooted at `/` or at a home dir is blocked. Scope the search to a specific project or subdirectory instead."
    }
  }'
fi

exit 0
