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

allow() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# mailbox-chat.py: `status`, or `say --stdin` fed by one quoted heredoc. A quoted
# heredoc expands nothing, so its body is plain text; the end marker must be the
# last line, or the shell would run whatever follows it.
if REST=$(strip_prefix python3 mailbox-chat.py); then
  [ "$REST" = status ] && allow "agterm mailbox chat: status of the other pane"
  case "$REST" in *$'\r'*) exit 0 ;; esac
  FIRST=${REST%%$'\n'*}
  [ "$FIRST" != "$REST" ] || exit 0
  [[ "$FIRST" =~ ^say\ --stdin\ \<\<\'([A-Za-z_][A-Za-z0-9_]*)\'$ ]] || exit 0
  TAG=${BASH_REMATCH[1]}
  BODY=${REST#*$'\n'}
  [ "${BODY##*$'\n'}" = "$TAG" ] || [ "$BODY" = "$TAG" ] || exit 0
  case "$BODY" in "$TAG") ;; *) BODY=${BODY%$'\n'*} ;; esac
  [ "$BODY" = "$TAG" ] && exit 0
  while IFS= read -r line; do
    [ "$line" = "$TAG" ] && exit 0
  done <<< "$BODY"
  allow "agterm mailbox chat: send a message to the other pane"
fi

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
