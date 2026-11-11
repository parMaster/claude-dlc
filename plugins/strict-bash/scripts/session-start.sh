#!/usr/bin/env bash
# SessionStart hook: tells Claude the Bash rules before its first Bash call,
# turns off color in Bash output so Claude doesn't pipe it through sed (not
# allowlisted, since sed can write files) to strip it, and creates tmp/ at
# the repo root so Claude can send temp files there from its first call.
# SessionStart input carries no permission_mode, so this runs in every mode.

if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export NO_COLOR=1' >> "$CLAUDE_ENV_FILE"
fi

# Only inside a git repo, so a session started in $HOME gets no stray tmp/.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
if TOPLEVEL=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  mkdir -p "$TOPLEVEL/tmp"
fi

echo "Run each command as its own Bash call: chained commands (&&, ||, ;, \$(...), loops) are denied so each call can match an allow rule. Pipes into filters like head, tail or grep are fine. Use Read, Grep or Glob to read and search files. Write paths out literally instead of using variables like \$TMPDIR: a command with \$VAR in it always asks for permission. Put a path with spaces in double quotes; a backslash-escaped space always asks too.

Temp files: the user wants temp files and saved command output in tmp/<name> at the repo root, like \`make test > tmp/test.out 2>&1\`. Git ignores tmp/. Run \`mkdir -p tmp\` first if it is missing. This replaces the system prompt's instruction to use the session scratchpad. Never put the scratchpad path (/tmp/claude-<uid>/... or /private/tmp/claude-<uid>/...) in a Bash command: it is wider than the user's screen, and such commands are denied."
