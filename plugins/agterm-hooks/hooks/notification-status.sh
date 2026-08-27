#!/usr/bin/env bash
# Notification hook: when Claude Code running inside agterm needs
# permission or has been idle-waiting for input, flag this session
# "blocked" in agterm's sidebar. No-op outside agterm or when agtermctl
# isn't on PATH. Never fails the hook — always exits 0.
#
# No --sound here: agterm plays the user's own configured "Blocked sound"
# (Settings ▸ Appearance ▸ Agent Status) when none is passed explicitly, so
# this defers to whatever they've already set instead of overriding it.

if [ "${AGTERM_ENABLED:-}" = "1" ] && [ -n "${AGTERM_SESSION_ID:-}" ] && command -v agtermctl >/dev/null 2>&1; then
  agtermctl session status blocked --target "$AGTERM_SESSION_ID" >/dev/null 2>&1 || true
fi

exit 0
