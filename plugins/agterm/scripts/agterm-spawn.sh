#!/usr/bin/env bash
# Spawn a fresh agterm session and type a `claude` launch command into it,
# reading the task prompt from a file. This avoids passing arbitrary prompt
# text through the terminal-typing mechanism at all — only the file path is
# typed (as a short, known-safe command line); the new session's own shell
# does the `$(cat ...)` expansion when it runs the command.
#
# Shared by agterm-handoff.sh (plan-file hand-off) and spawn-session/SKILL.md
# (arbitrary task hand-off). Session creation itself (workspace resolution,
# `agtermctl session new`, flagging) is agent-agnostic and lives in
# agterm-session-new.sh, reused by codex-spawn.sh for the Codex runtime.
#
# Usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name] [claude-flags]
#   <cwd>            working directory for the new session's shell
#   <session-name>   sidebar label for the new session
#   <prompt-file>    path to a file containing the full task prompt. Left in
#                    place after this script returns — agtermctl is
#                    fire-and-forget, so there is no reliable moment at
#                    which the new session is known to have read it yet.
#   [workspace-name] if given, group the session under this named workspace
#                    (created if it doesn't exist yet). If omitted, the
#                    session opens in the caller's own current workspace,
#                    or the active session's workspace if that isn't set
#                    (e.g. when called from agterm's quick terminal). Pass ""
#                    to skip grouping while still supplying claude-flags.
#   [claude-flags]   extra flags inserted into the `claude` launch command,
#                    e.g. "--permission-mode acceptEdits". Caller-controlled,
#                    fixed literal — never built from untrusted input.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

CWD="${1:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
SESSION_NAME="${2:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
PROMPT_FILE="${3:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
WORKSPACE_NAME="${4:-}"
CLAUDE_FLAGS="${5:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-spawn: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "agterm-spawn: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SID=$(bash "$SCRIPT_DIR/agterm-session-new.sh" "$CWD" "$SESSION_NAME" "$WORKSPACE_NAME")

# %q shell-escapes the path if it needs it (spaces, etc). The prompt text
# itself never appears on this command line — it's read by the new
# session's own shell, from the file, at run time.
if [ -n "$CLAUDE_FLAGS" ]; then
  printf 'claude %s "$(cat %q)"' "$CLAUDE_FLAGS" "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
else
  printf 'claude "$(cat %q)"' "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
fi
agtermctl session type $'\n' --target "$SID"

echo "$SESSION_NAME"
