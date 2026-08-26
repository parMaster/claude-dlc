#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session, in the caller's
# own workspace. Shared by plan/SKILL.md, review-plan/SKILL.md, and
# implement-in-session/SKILL.md so the agtermctl sequence lives in one place
# instead of three copies.
#
# Usage: agterm-handoff.sh <plan-file>
# Requires: AGTERM_ENABLED=1, AGTERM_WORKSPACE_ID set (both set automatically
# by agterm itself), agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Implement: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: agterm-handoff.sh <plan-file>}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Implement: $SLUG"

SID=$(agtermctl session new --cwd "$PROJECT_ROOT" --workspace "$AGTERM_WORKSPACE_ID" --name "$SESSION_NAME" --json | jq -r '.result.id')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
  echo "agterm-handoff: session new failed to return a session id" >&2
  exit 1
fi

agtermctl session type "claude 'You have a new implementation plan to execute: $PLAN_FILE

Read it fully, then implement every task in order, following its stated
testing approach. Run the project'\''s tests and linter before treating any
task as done.'" --target "$SID"

agtermctl session type $'\n' --target "$SID"

echo "$SESSION_NAME"
