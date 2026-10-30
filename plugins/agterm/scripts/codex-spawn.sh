#!/usr/bin/env bash
# Spawn a fresh agterm session and type a `codex` launch command into it,
# reading the task prompt from a file — the Codex CLI counterpart to
# agterm-spawn.sh. Same file-based prompt hand-off and the same
# session-creation primitive (agterm-session-new.sh); only the launched
# binary and its flags differ.
#
# Shared by codex-handoff.sh (plan-file hand-off) and spawn-session/SKILL.md
# (arbitrary task hand-off, Codex runtime).
#
# Usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [codex-flags]
#   <cwd>            working directory for the new session's shell
#   <session-name>   sidebar label for the new session, which opens as a
#                    companion of the caller's session
#   <prompt-file>    path to a file containing the full task prompt. Left in
#                    place after this script returns — agtermctl is
#                    fire-and-forget, so there is no reliable moment at
#                    which the new session is known to have read it yet.
#   [codex-flags]    extra flags inserted into the `codex` launch command,
#                    e.g. "--sandbox workspace-write --ask-for-approval
#                    never". Caller-controlled, fixed literal — never built
#                    from untrusted input.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

CWD="${1:?usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [codex-flags]}"
SESSION_NAME="${2:?usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [codex-flags]}"
PROMPT_FILE="${3:?usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [codex-flags]}"
CODEX_FLAGS="${4:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "codex-spawn: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "codex-spawn: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SID=$(bash "$SCRIPT_DIR/agterm-session-new.sh" "$CWD" "$SESSION_NAME")

# %q shell-escapes the path if it needs it (spaces, etc). The prompt text
# itself never appears on this command line — it's read by the new
# session's own shell, from the file, at run time.
if [ -n "$CODEX_FLAGS" ]; then
  printf 'codex %s "$(cat %q)"' "$CODEX_FLAGS" "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
else
  printf 'codex "$(cat %q)"' "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
fi
agtermctl session type $'\n' --target "$SID"

echo "$SESSION_NAME"
