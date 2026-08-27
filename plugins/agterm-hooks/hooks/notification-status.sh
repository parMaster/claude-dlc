#!/usr/bin/env bash
# Notification hook: when Claude Code running inside agterm needs
# permission or has been idle-waiting for input, flag this session
# "blocked" in agterm's sidebar. No-op outside agterm (AGTERM_SESSION_ID
# unset). Never fails the hook — always exits 0.
#
# See resolve-agtermctl.sh for why agtermctl is resolved via known install
# paths instead of PATH, and why AGTERM_SOCKET is forwarded when set.
#
# No --sound here: agterm plays the user's own configured "Blocked sound"
# (Settings ▸ Appearance ▸ Agent Status) when none is passed explicitly, so
# this defers to whatever they've already set instead of overriding it.

set -u
[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve-agtermctl.sh
. "${SCRIPT_DIR}/resolve-agtermctl.sh"

socket_args=()
[ -n "${AGTERM_SOCKET:-}" ] && socket_args=(--socket "$AGTERM_SOCKET")

"$AGTERMCTL" session status blocked --target "$AGTERM_SESSION_ID" \
  "${socket_args[@]}" >/dev/null 2>&1 || true

exit 0
