#!/usr/bin/env bash
# Stop hook: when Claude Code running inside agterm finishes responding,
# flag this session "completed" in agterm's sidebar with a sound. No-op
# outside agterm (AGTERM_ENABLED unset) or when agtermctl isn't on PATH.
# Never fails the hook — always exits 0, so a missing/broken agtermctl can
# never block Claude Code's own Stop handling.
#
# --auto-reset clears the glyph back to idle once the session is next
# visited, so this behaves like a one-shot "just finished" flash rather
# than a status that has to be manually cleared.

if [ "${AGTERM_ENABLED:-}" = "1" ] && [ -n "${AGTERM_SESSION_ID:-}" ] && command -v agtermctl >/dev/null 2>&1; then
  agtermctl session status completed --sound default --auto-reset --target "$AGTERM_SESSION_ID" >/dev/null 2>&1 || true
fi

exit 0
