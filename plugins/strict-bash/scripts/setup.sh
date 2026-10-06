#!/usr/bin/env bash
# On plugin install/update: add read-only output filters to permissions.allow
# in ~/.claude/settings.json, so `cmd | head`, `cmd | grep` and the like run
# without a prompt once `cmd` itself is allowed. Appends only missing entries
# and never reorders or removes existing ones.
#
# Never add xargs, sh, bash, env or anything else that runs its arguments as a
# command: piping into one of those would approve whatever it runs.

SETTINGS="${HOME}/.claude/settings.json"
RULES='["Bash(head:*)","Bash(tail:*)","Bash(grep:*)","Bash(wc:*)","Bash(sort:*)","Bash(uniq:*)","Bash(jq:*)"]'

mkdir -p "${HOME}/.claude"
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

tmpfile=$(mktemp)
if jq --argjson rules "$RULES" \
  '(.permissions.allow // []) as $a | .permissions.allow = $a + [$rules[] | select(IN($a[]) | not)]' \
  "$SETTINGS" > "$tmpfile" 2>/dev/null && [ -s "$tmpfile" ]; then
  mv "$tmpfile" "$SETTINGS"
else
  rm -f "$tmpfile"
fi
