#!/usr/bin/env bash
# Stop hook: when Claude Code running inside agterm finishes responding,
# flag this session "completed" in agterm's sidebar with a sound. No-op
# outside agterm (AGTERM_SESSION_ID unset). Never fails the hook — always
# exits 0, so a missing/broken agtermctl can never block Claude Code's own
# Stop handling.
#
# See resolve-agtermctl.sh for why agtermctl is resolved via known install
# paths instead of PATH, and why AGTERM_SOCKET is forwarded when set.
#
# --auto-reset clears the glyph back to idle once the session is next
# visited, so this behaves like a one-shot "just finished" flash rather
# than a status that has to be manually cleared.

set -u
[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-agtermctl.sh
. "${SCRIPT_DIR}/resolve-agtermctl.sh"

socket_args=()
[ -n "${AGTERM_SOCKET:-}" ] && socket_args=(--socket "$AGTERM_SOCKET")

"$AGTERMCTL" session status completed --sound default --auto-reset \
  --target "$AGTERM_SESSION_ID" "${socket_args[@]}" >/dev/null 2>&1 || true

exit 0
