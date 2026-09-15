#!/usr/bin/env bash
# Hand off a plan REVIEW (not implementation) to a fresh agterm session
# running `codex`. Companion to codex-handoff.sh, which hands off plan
# implementation instead — this one is invoked from review-plan/SKILL.md's
# Step 0.3 runtime choice, not from `handoff`. No model parameter: the
# reviewing session always uses whatever model Codex is configured to use
# by default, since there's no way to surface Claude-style model tiers to a
# Codex-run review anyway.
#
# Usage: codex-review-handoff.sh <plan-file>
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Review: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: codex-review-handoff.sh <plan-file>}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "codex-review-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Review: $SLUG"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/handoff-prompt.sh"

PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-review-handoff.XXXXXX")
build_review_prompt "$PLAN_FILE" > "$PROMPT_FILE"

# Workspace-write is needed even though the plan-review subagent itself is
# read-only: the fix-and-re-review loop that runs between rounds edits the
# plan file directly.
CODEX_FLAGS="--sandbox workspace-write --ask-for-approval never"

bash "$SCRIPT_DIR/codex-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE" "" "$CODEX_FLAGS"
