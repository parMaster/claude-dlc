#!/usr/bin/env bash
# PreToolUse hook (Bash, EnterWorktree): denies the two ways Claude can reach a
# worktree that the WorktreeCreate hook never sees: the EnterWorktree tool and
# a plain `git worktree add`.
#
# Runs in every permission mode: work that lands outside the open checkout is
# hidden from the user whether or not Bash prompts.

INPUT=$(cat)

deny() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Worktrees are turned off on this machine. Work in the current checkout."
    }
  }'
  exit 0
}

[ "$(jq -r '.tool_name // empty' <<< "$INPUT")" = "EnterWorktree" ] && deny

COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")
[ -n "$COMMAND" ] || exit 0

# Quoted text is data: a commit message or a grep pattern may mention the
# command. Joining lines first lets a multi-line quoted string drop as one.
BARE=$(printf '%s' "$COMMAND" | tr '\n' ' ' | sed -E 's/"[^"]*"//g' | sed -E "s/'[^']*'//g")

# `git`, then any global options (`-C <dir>`, `-c k=v`, `--no-pager`), then
# `worktree add`. list, remove and prune stay allowed for cleanup.
PATTERN='(^|[[:space:];&|(`/])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+worktree[[:space:]]+add([[:space:]]|$)'

if printf '%s' "$BARE" | grep -Eq "$PATTERN"; then
  deny
fi

exit 0
