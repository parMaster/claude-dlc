#!/usr/bin/env bash
# PreToolUse hook (Bash): denies a call that chains several commands, so each
# command arrives alone and can match an allow rule. Pipes stay allowed —
# Claude Code checks each side of a pipe against the allow rules itself.
#
# Operators inside quotes or heredoc bodies are data and pass. So does the
# `"$(cat <<'EOF' ... EOF)"` form Claude uses for multi-line commit messages.
# This hook never approves anything; it only denies or stays silent.

INPUT=$(cat)

# These modes don't prompt for Bash, so splitting buys nothing there.
case "$(jq -r '.permission_mode // empty' <<< "$INPUT")" in
  bypassPermissions | auto) exit 0 ;;
esac

CMD=$(jq -r '.tool_input.command // empty' <<< "$INPUT")
[ -n "$CMD" ] || exit 0

# Byte indexing; in a UTF-8 locale ${CMD:i:1} rescans the string every time.
export LC_ALL=C

deny() {
  jq -n --arg op "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Chained commands are blocked (found " + $op + "). Run each command as its own Bash call so it can match an allow rule. Pipes into filters like head, tail or grep are fine. Use Read, Grep or Glob to read and search files.")
    }
  }'
  exit 0
}

# Matches `$(cat <<'EOF'` + body + `EOF` + `)` starting at $1. On success sets
# SKIP_TO to the index just past the closing paren.
match_cat_heredoc() {
  local start=$1 rest=${CMD:$1} re body line stripped lead consumed nl
  re=$'^\\$\\(cat[[:space:]]*<<-?[[:space:]]*[\'"]?([A-Za-z_][A-Za-z0-9_]*)[\'"]?[ \t]*\n'
  [[ $rest =~ $re ]] || return 1
  local delim=${BASH_REMATCH[1]}
  consumed=${#BASH_REMATCH[0]}
  body=${rest:consumed}
  while [ -n "$body" ]; do
    line=${body%%$'\n'*}
    nl=1; [ "$line" = "$body" ] && nl=0
    consumed=$((consumed + ${#line} + nl))
    body=${body:${#line}+nl}
    stripped=${line#"${line%%[!$'\t']*}"}
    if [ "$stripped" = "$delim" ]; then
      lead=${body%%[!$' \t\n']*}
      [ "${body:${#lead}:1}" = ")" ] || return 1
      SKIP_TO=$((start + consumed + ${#lead} + 1))
      return 0
    fi
  done
  return 1
}

# At a newline that ends a line holding heredoc starts: skips every pending
# body and leaves i on the newline after the last delimiter (or at the end).
skip_heredoc_bodies() {
  local delim line stripped
  for delim in "${HEREDOCS[@]}"; do
    while (( i < n )); do
      ((i++))
      line=${CMD:i}
      line=${line%%$'\n'*}
      ((i += ${#line}))
      stripped=${line#"${line%%[!$'\t']*}"}
      [ "$stripped" = "$delim" ] && break
    done
  done
  HEREDOCS=()
}

n=${#CMD}
i=0
state=normal   # normal | sq | dq
cmd_start=1    # next word is a command name
prev=""        # previous character
lastns=""      # last non-space character
HEREDOCS=()

while (( i < n )); do
  c=${CMD:i:1}

  if [ "$state" = sq ]; then
    [ "$c" = "'" ] && state=normal
    prev=$c; ((i++)); continue
  fi

  if [ "$state" = dq ]; then
    case $c in
      '\') prev=x; ((i += 2)); continue ;;
      '"') state=normal ;;
      '`') deny 'backticks' ;;
      '$')
        if [ "${CMD:i+1:1}" = "(" ]; then
          match_cat_heredoc "$i" && { i=$SKIP_TO; prev=")"; continue; }
          deny '$(...)'
        fi ;;
    esac
    prev=$c; ((i++)); continue
  fi

  if (( cmd_start )) && [[ $c != [[:space:]] ]]; then
    cmd_start=0
    case $c in '(' | '{') deny 'a ( ... ) or { ... } group' ;; esac
    word=${CMD:i}
    word=${word%%[[:space:]\;\&\|\<\>\(\)]*}
    case $word in
      for | while | until | if | case | select | function) deny "a \"$word\" block" ;;
    esac
  fi

  case $c in
    '\') prev=x; lastns=x; ((i += 2)); continue ;;
    "'") state=sq ;;
    '"') state=dq ;;
    '`') deny 'backticks' ;;
    ';') deny '";"' ;;
    '#')
      if [[ -z $prev || $prev == [[:space:]] ]]; then
        line=${CMD:i}
        line=${line%%$'\n'*}
        ((i += ${#line}))
        continue
      fi ;;
    '&')
      nx=${CMD:i+1:1}
      if [ "$nx" = "&" ]; then
        deny '"&&"'
      elif [[ $prev != [\<\>] && $nx != '>' ]]; then
        deny 'a background "&"'
      fi ;;
    '|')
      nx=${CMD:i+1:1}
      [ "$nx" = "|" ] && deny '"||"'
      [ "$nx" = "&" ] && ((i++))
      cmd_start=1 ;;
    '$')
      if [ "${CMD:i+1:1}" = "(" ]; then
        match_cat_heredoc "$i" && { i=$SKIP_TO; prev=")"; lastns=")"; continue; }
        deny '$(...)'
      fi ;;
    '<' | '>')
      [ "${CMD:i+1:1}" = "(" ] && deny "$c(...)"
      if [ "${CMD:i:3}" = "<<<" ]; then
        prev='<'; lastns='<'; ((i += 3)); continue
      fi
      if [ "${CMD:i:2}" = "<<" ]; then
        rest=${CMD:i+2}
        re=$'^-?[ \t]*[\'"]?([A-Za-z_][A-Za-z0-9_]*)[\'"]?'
        if [[ $rest =~ $re ]]; then
          HEREDOCS+=("${BASH_REMATCH[1]}")
          ((i += 2 + ${#BASH_REMATCH[0]}))
          prev=x; lastns=x
          continue
        fi
      fi ;;
    $'\n')
      if (( ${#HEREDOCS[@]} )); then
        skip_heredoc_bodies
        prev=x
        continue
      fi
      [ "$lastns" = "|" ] || deny 'a newline between commands' ;;
  esac

  prev=$c
  [[ $c == [[:space:]] ]] || lastns=$c
  ((i++))
done

exit 0
