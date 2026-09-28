#!/usr/bin/env bash
# PreToolUse hook (Bash): approves a single plain call of this plugin's
# overlay.sh with a viewer kind (md, html, url), so opening a plan or page
# works in auto mode without a permission rule in settings. Skill
# allowed-tools can't do this: it doesn't bypass the auto-mode classifier.
#
# Anything else gets no output, leaving the normal permission flow in charge;
# this hook never denies.

COMMAND=$(jq -r '.tool_input.command // empty')
[ -n "$COMMAND" ] || exit 0

# Must be this plugin's script, not any file named overlay.sh.
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || exit 0
REST=$COMMAND
for prefix in "bash \"$ROOT/scripts/overlay.sh\" " "bash $ROOT/scripts/overlay.sh " \
              'bash "${CLAUDE_PLUGIN_ROOT}/scripts/overlay.sh" ' 'bash ${CLAUDE_PLUGIN_ROOT}/scripts/overlay.sh '; do
  if [ "${COMMAND#"$prefix"}" != "$COMMAND" ]; then REST=${COMMAND#"$prefix"}; break; fi
done
[ "$REST" != "$COMMAND" ] || exit 0

# No chaining, substitution, redirects or expansions in the arguments.
case "$REST" in
  *[\;\&\|\<\>\`\$]* | *$'\n'* | *$'\r'*) exit 0 ;;
esac

case "$REST" in
  md | "md "* | "html "* | "url "*) ;;
  *) exit 0 ;;
esac

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "agterm overlay viewer (md/html/url) on the current session"
  }
}'
exit 0
