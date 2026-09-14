#!/usr/bin/env bash
# Generic primitive: create a fresh agterm session (optionally grouped under
# a named workspace) and flag it. Agent-agnostic — this is the part of a
# hand-off that's identical no matter which CLI process ends up typed into
# the session. Shared by agterm-spawn.sh (claude) and codex-spawn.sh (codex).
#
# Usage: agterm-session-new.sh <cwd> <session-name> [workspace-name]
#   <cwd>            working directory for the new session's shell
#   <session-name>   sidebar label for the new session
#   [workspace-name] if given, group the session under this named workspace
#                    (created if it doesn't exist yet). If omitted, the
#                    session opens in the caller's own current workspace, or
#                    the active session's workspace if that isn't set (e.g.
#                    when called from agterm's quick terminal).
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's id to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

CWD="${1:?usage: agterm-session-new.sh <cwd> <session-name> [workspace-name]}"
SESSION_NAME="${2:?usage: agterm-session-new.sh <cwd> <session-name> [workspace-name]}"
WORKSPACE_NAME="${3:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-session-new: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

if [ -n "$WORKSPACE_NAME" ]; then
  SID=$(agtermctl session new --cwd "$CWD" --workspace-name "$WORKSPACE_NAME" --create-workspace --name "$SESSION_NAME" --json | jq -r '.result.id')
else
  SID=$(agtermctl session new --cwd "$CWD" --workspace "${AGTERM_WORKSPACE_ID:-active}" --name "$SESSION_NAME" --json | jq -r '.result.id')
fi

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
  echo "agterm-session-new: session new failed to return a session id" >&2
  exit 1
fi

# Flag the hand-off so it shows up in agterm's flagged sidebar / flagged
# dashboard alongside any other in-flight sessions. Best-effort: a flag
# failure must not abort a hand-off that otherwise succeeded.
agtermctl session flag on --target "$SID" >/dev/null 2>&1 || true

echo "$SID"
