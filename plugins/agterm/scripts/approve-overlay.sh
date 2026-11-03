#!/usr/bin/env bash
# PreToolUse hook (Bash): approves a single plain call of this plugin's
# overlay.sh with a viewer kind (html, url), or of its webrev.py with review,
# wait or result, so opening or reviewing a page works in auto mode without a
# permission rule in settings. Skill allowed-tools can't do this: it doesn't
# bypass the auto-mode classifier.
#
# Anything else gets no output, leaving the normal permission flow in charge;
# this hook never denies.

COMMAND=$(jq -r '.tool_input.command // empty')
[ -n "$COMMAND" ] || exit 0

# Must be this plugin's script, not any file with the same name.
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || exit 0

# Strips "<runner> <script path> " in any of its spellings; prints the rest.
strip_prefix() {
  local runner=$1 script=$2 prefix
  for prefix in "$runner \"$ROOT/scripts/$script\" " "$runner $ROOT/scripts/$script " \
                "$runner \"\${CLAUDE_PLUGIN_ROOT}/scripts/$script\" " "$runner \${CLAUDE_PLUGIN_ROOT}/scripts/$script "; do
    if [ "${COMMAND#"$prefix"}" != "$COMMAND" ]; then printf '%s' "${COMMAND#"$prefix"}"; return 0; fi
  done
  return 1
}

if REST=$(strip_prefix bash overlay.sh); then
  KINDS="html url"
  REASON="agterm overlay viewer (html/url) on the current session"
elif REST=$(strip_prefix python3 webrev.py); then
  # a bare review opens the newest plan
  KINDS="review wait result"
  [ "$REST" = review ] && REST="review "
  REASON="agterm webrev review page on the current session"
else
  exit 0
fi

# No chaining, substitution, redirects or expansions in the arguments.
case "$REST" in
  *[\;\&\|\<\>\`\$]* | *$'\n'* | *$'\r'*) exit 0 ;;
esac

MATCHED=
for kind in $KINDS; do
  [ "${REST#"$kind "}" != "$REST" ] && MATCHED=1
done
[ -n "$MATCHED" ] || exit 0

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: $reason
  }
}'
exit 0
