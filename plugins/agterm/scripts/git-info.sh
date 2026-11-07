#!/bin/bash
# Claude Code hook that shows the branch's ticket key and commits ahead/behind on the agterm session's sidebar
# info line. Synchronous on purpose: a detached refresh could land after SessionEnd's clear.
# Prints nothing, since SessionStart hook stdout becomes model context.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0

# a headless `claude -p` inherits AGTERM_* and would overwrite its spawner's line with its own cwd.
[ "${CLAUDE_CODE_ENTRYPOINT:-cli}" = cli ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
agtermctl=${AGTERMCTL:-agtermctl}

# the CLI never reads AGTERM_SOCKET, so pass it: it names the instance this session belongs to.
info() {
  "$agtermctl" session info "$@" --target "$AGTERM_SESSION_ID" \
    ${AGTERM_SOCKET:+--socket "$AGTERM_SOCKET"} >/dev/null 2>&1 || :
}

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)

if [ "$event" = SessionEnd ]; then
  info --clear
  exit 0
fi
[ -n "$cwd" ] || exit 0

# --no-optional-locks keeps status off index.lock, so a commit Claude runs at the same moment never
# fails on it. Outside a repository the line is cleared, so a project switch drops the old repo.
status=$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch \
  --untracked-files=no 2>/dev/null) || {
  info --clear
  exit 0
}

read -r head oid ahead behind <<EOF
$(printf '%s\n' "$status" | awk '
  /^# branch\.oid /  { oid = substr($3, 1, 7) }
  /^# branch\.head / { head = $3 }
  /^# branch\.ab /   { a = substr($3, 2); b = substr($4, 2) }
  END { printf "%s %s %d %d\n", head, oid, a, b }')
EOF

if [ "$head" = "(detached)" ]; then
  name=$oid
else
  name=$(printf '%s' "$head" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
  if [ -z "$name" ]; then
    name=$head
    [ "${#name}" -le 20 ] || name="${name:0:20}…"
  fi
fi
# cut before escaping, so the cut never splits a backslash from its character. Git allows backticks,
# underscores and brackets in branch names; escaped, they show as typed instead of opening markup.
name=$(printf '%s' "$name" | sed 's/[][\\`*_{}()<>#+!|~^&.-]/\\&/g')

line="**$name**"
[ "$ahead" -gt 0 ] && line="$line ^[↑$ahead](color: \"blue\")"
[ "$behind" -gt 0 ] && line="$line ^[↓$behind](color: \"purple\")"

# 24 hours, the API's ceiling: a Claude killed before SessionEnd still leaves no line behind for good.
info --markdown --hide-after 86400 "$line"
