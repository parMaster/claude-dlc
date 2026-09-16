#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session running `codex`,
# in the caller's own workspace — the Codex CLI counterpart to
# agterm-handoff.sh. Shares the same canned plan-hand-off prompt (built by
# handoff-prompt.sh) so the wording can't drift between the two runtimes;
# only the launched binary and its flags differ.
#
# Usage: codex-handoff.sh <plan-file> [model]
#   [model]                exact Codex model name (e.g. "gpt-5.1-codex") to
#                          run the new session on, passed through as
#                          `--model`. Omit (or pass "") to use whatever model
#                          Codex is configured to use by default.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Implement: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: codex-handoff.sh <plan-file> [model]}"
MODEL="${2:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "codex-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Implement: $SLUG"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/handoff-prompt.sh"

PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-handoff.XXXXXX")
build_handoff_prompt "$PLAN_FILE" > "$PROMPT_FILE"

CODEX_FLAGS="--sandbox danger-full-access --ask-for-approval on-request"
if [ -n "$MODEL" ]; then
  CODEX_FLAGS="$CODEX_FLAGS --model $MODEL"
fi

# workspace-write blocked gofmt/golangci-lint/docker from writing to their
# temp/cache dirs outside the repo, so implementation hand-offs use
# danger-full-access instead. on-request (rather than never) still lets
# Codex pause and ask when it judges an action risky.
bash "$SCRIPT_DIR/codex-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE" "" "$CODEX_FLAGS"
