# Sourced, not executed. Resolves the agtermctl binary into $AGTERMCTL.
#
# A Claude Code hook runs with a restricted PATH — it does NOT inherit your
# interactive shell's PATH, so `command -v agtermctl` can (and did) fail here
# even though it resolves fine in a normal terminal. agterm's own installer
# works around this in its bundled agent-status hook
# (~/.config/agterm/agent-status/agterm-agent-status.sh) by baking in an
# absolute path instead of trusting PATH; this mirrors that approach.
#
# Resolution order:
#   1. $AGTERMCTL — an explicit override, if the caller set one
#   2. /usr/local/bin/agtermctl — where Help > Install Command Line Tool
#      symlinks it
#   3. /Applications/agterm.app/Contents/MacOS/agtermctl — the bundled
#      binary, present regardless of whether the CLI tool was installed
#   4. `agtermctl` bare — PATH-based, last resort, kept so this still works
#      if none of the above matched but PATH happens to have it

if [ -z "${AGTERMCTL:-}" ]; then
  for candidate in /usr/local/bin/agtermctl /Applications/agterm.app/Contents/MacOS/agtermctl; do
    if [ -x "$candidate" ]; then
      AGTERMCTL="$candidate"
      break
    fi
  done
fi
AGTERMCTL="${AGTERMCTL:-agtermctl}"
