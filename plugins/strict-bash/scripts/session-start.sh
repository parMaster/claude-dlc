#!/usr/bin/env bash
# SessionStart hook: tells Claude the one-command-per-call rule before its first
# Bash call, and turns off color in Bash output so Claude doesn't pipe it
# through sed (not allowlisted, since sed can write files) to strip it.
# SessionStart input carries no permission_mode, so this runs in every mode.

if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export NO_COLOR=1' >> "$CLAUDE_ENV_FILE"
fi

echo "Run each command as its own Bash call: chained commands (&&, ||, ;, \$(...), loops) are denied so each call can match an allow rule. Pipes into filters like head, tail or grep are fine. Use Read, Grep or Glob to read and search files. Write paths out literally instead of using variables like \$TMPDIR: a command with \$VAR in it always asks for permission."
