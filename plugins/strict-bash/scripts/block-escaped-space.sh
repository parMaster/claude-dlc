#!/usr/bin/env bash
# PreToolUse hook (Bash): denies a call with a backslash-escaped space or tab,
# like `Application\ Support`. Claude Code asks for permission on any such
# command, even one an allow rule matches, so a quoted path is the only form
# that runs without a prompt. Backslashes inside quotes are left alone.
# This hook never approves anything; it only denies or stays silent.

INPUT=$(cat)

# These modes don't prompt for Bash, so a retry buys nothing there.
case "$(jq -r '.permission_mode // empty' <<< "$INPUT")" in
  bypassPermissions | auto) exit 0 ;;
esac

CMD=$(jq -r '.tool_input.command // empty' <<< "$INPUT")
[[ $CMD == *\\* ]] || exit 0

# Byte indexing; in a UTF-8 locale ${CMD:i:1} rescans the string every time.
export LC_ALL=C

n=${#CMD}
i=0
state=normal   # normal | sq | dq

while (( i < n )); do
  c=${CMD:i:1}
  case $state in
    sq) [ "$c" = "'" ] && state=normal ;;
    dq)
      case $c in
        "\\") ((i++)) ;;
        '"') state=normal ;;
      esac ;;
    normal)
      case $c in
        "'") state=sq ;;
        '"') state=dq ;;
        "\\")
          if [[ ${CMD:i+1:1} == [$' \t'] ]]; then
            jq -n '{
              hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: "Backslash-escaped spaces always ask for permission, even when an allow rule matches. Put the path in double quotes instead, like \"/Library/Application Support/x\"."
              }
            }'
            exit 0
          fi
          ((i++)) ;;
      esac ;;
  esac
  ((i++))
done

exit 0
