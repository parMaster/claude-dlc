#!/usr/bin/env bash
# PreToolUse hook (Bash): blocks editing files through an inline script —
# a python/node/ruby heredoc or -c/-e one-liner that writes a file, or an
# in-place `sed -i` / `perl -i`.
#
# The approval prompt then shows the user a script they have to decode to
# find the one line being changed. The Edit tool (with replace_all for
# repeated text) does the same job and shows up as a readable diff.
#
# Exception: `perl -i` on a plan under docs/plans/ — the planning skill's
# one-liner for ticking a finished task's checkboxes.

COMMAND=$(jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

B='(^|[[:space:];&|(`])'

INTERP="${B}(python[0-9.]*|node|ruby)[[:space:]]+(-[[:space:]]|-$|-[ce][[:space:]]|<<)"
WRITES="open\([^)]*['\"]([wax]|r\+)[bt+]*['\"]|write_text\(|write_bytes\(|writeFile(Sync)?\(|File\.write\("
SED_I="${B}sed[[:space:]]+([^|;&]*[[:space:]])?(-[A-Za-z]*i|--in-place)"
PERL_I="${B}perl[[:space:]]+([^|;&]*[[:space:]])?-[A-Za-z]*i"

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

MSG="Editing files through an inline script or in-place sed/perl is blocked: the user has to read the script to see what changes. Use the Edit tool instead (replace_all: true for text that repeats), so the change shows as a diff."

if echo "$COMMAND" | grep -Eq "$INTERP" && echo "$COMMAND" | grep -Eq "$WRITES"; then
  deny "$MSG"
fi

if echo "$COMMAND" | grep -Eq "$SED_I"; then
  deny "$MSG"
fi

if echo "$COMMAND" | grep -Eq "$PERL_I" && ! echo "$COMMAND" | grep -q 'docs/plans/'; then
  deny "$MSG"
fi

exit 0
