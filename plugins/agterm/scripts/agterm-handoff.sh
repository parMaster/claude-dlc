#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session running `claude`,
# in the caller's own workspace. Called by handoff/SKILL.md. Thin wrapper
# around the generic agterm-spawn.sh: builds the
# canned plan-hand-off prompt into a temp file and hands off in the current
# workspace (no workspace grouping — matches this script's prior behavior).
#
# Usage: agterm-handoff.sh <plan-file> [model] [parent-name]
#   [model]                model alias (e.g. "opus", "sonnet", "haiku") to run
#                          the new session on, passed through as `--model`.
#                          Omit (or pass "") to inherit whatever `claude`
#                          launches with by default.
#   [parent-name]          the calling session's Claude name (from ListAgents).
#                          If given, the prompt ends with a footer telling the
#                          new session to report back there via SendMessage.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Implement: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: agterm-handoff.sh <plan-file> [model]}"
MODEL="${2:-}"
PARENT_NAME="${3:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Implement: $SLUG"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/handoff-prompt.sh"

# Portable mktemp (no -t <prefix>, which is BSD-only and fails GNU coreutils
# on the Linux CI runner). Left in place after this script returns — see
# agterm-spawn.sh's comment on why the prompt file is never cleaned up.
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/agterm-handoff.XXXXXX")
build_handoff_prompt "$PLAN_FILE" "$PARENT_NAME" > "$PROMPT_FILE"

# True when any settings file Claude Code reads sets
# permissions.disableAutoMode to "disable" (how an org turns auto mode off).
# Such a machine starts `--permission-mode auto` in Manual, not accept-edits,
# so it must never be asked for auto. CLAUDE_MANAGED_SETTINGS_DIR overrides
# the system managed-settings directory (for tests).
auto_mode_disabled() {
  local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local system_dir="${CLAUDE_MANAGED_SETTINGS_DIR:-}"
  if [ -z "$system_dir" ]; then
    case "$(uname -s)" in
      Darwin) system_dir="/Library/Application Support/ClaudeCode" ;;
      *) system_dir="/etc/claude-code" ;;
    esac
  fi
  local f
  for f in "$system_dir/managed-settings.json" "$system_dir"/managed-settings.d/*.json \
           "$config_dir/remote-settings.json" "$config_dir/settings.json" \
           "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    if [ "$(jq -r '.permissions.disableAutoMode // .disableAutoMode // empty' "$f" 2>/dev/null)" = "disable" ]; then
      return 0
    fi
  done
  # macOS MDM configuration profile (com.anthropic.claudecode domain).
  local plist="/Library/Managed Preferences/com.anthropic.claudecode.plist"
  if [ -f "$plist" ] && command -v plutil >/dev/null 2>&1 && \
     [ "$(plutil -extract permissions.disableAutoMode raw -o - "$plist" 2>/dev/null)" = "disable" ]; then
    return 0
  fi
  return 1
}

# Implementation hand-offs skip per-edit permission prompts: the whole point
# is to implement the plan. Auto mode where the org allows it, accept-edits
# where it doesn't.
if auto_mode_disabled; then
  CLAUDE_FLAGS="--permission-mode acceptEdits"
else
  CLAUDE_FLAGS="--permission-mode auto"
fi
if [ -n "$MODEL" ]; then
  CLAUDE_FLAGS="$CLAUDE_FLAGS --model $MODEL"
fi

bash "$SCRIPT_DIR/agterm-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE" "" "$CLAUDE_FLAGS"
