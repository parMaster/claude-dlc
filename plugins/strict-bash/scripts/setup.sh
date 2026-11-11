#!/usr/bin/env bash
# On plugin install/update: add read-only output filters to permissions.allow
# in ~/.claude/settings.json, so `cmd | head`, `cmd | grep` and the like run
# without a prompt once `cmd` itself is allowed. Appends only missing entries
# and never reorders or removes existing ones. Also adds tmp/ to the global
# gitignore.
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

# Add tmp/ to the global gitignore, so the repo-local tmp/ that session-start.sh
# steers Claude to never shows up in git status. Appends once, never rewrites.
if command -v git >/dev/null 2>&1; then
  IGNORE=$(git config --global --get core.excludesFile 2>/dev/null)
  if [ -z "$IGNORE" ]; then
    IGNORE="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
  fi
  # Git expands a leading ~ in core.excludesFile; bash doesn't.
  IGNORE="${IGNORE/#\~/$HOME}"

  if ! grep -qxE '/?tmp/?' "$IGNORE" 2>/dev/null; then
    mkdir -p "$(dirname "$IGNORE")"
    # Keep the last pattern intact when the file lacks a final newline.
    if [ -s "$IGNORE" ] && [ -n "$(tail -c1 "$IGNORE")" ]; then
      echo >> "$IGNORE"
    fi
    echo 'tmp/' >> "$IGNORE"
  fi
fi
