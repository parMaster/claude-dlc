#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session, in the caller's
# own workspace. Shared by plan/SKILL.md, review-plan/SKILL.md, and
# handoff/SKILL.md so the agtermctl sequence lives in one place instead of
# three copies. Thin wrapper around the generic agterm-spawn.sh: builds the
# canned plan-hand-off prompt into a temp file and hands off in the current
# workspace (no workspace grouping — matches this script's prior behavior).
#
# Usage: agterm-handoff.sh <plan-file>
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
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

# Portable mktemp (no -t <prefix>, which is BSD-only and fails GNU coreutils
# on the Linux CI runner). Left in place after this script returns — see
# agterm-spawn.sh's comment on why the prompt file is never cleaned up.
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/agterm-handoff.XXXXXX")
cat > "$PROMPT_FILE" <<EOF
You have a new implementation plan to execute: $PLAN_FILE

Read it fully, then implement every task in order, following its stated
testing approach. Run the project's tests and linter before treating any
task as done.
EOF

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$SCRIPT_DIR/agterm-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE"
