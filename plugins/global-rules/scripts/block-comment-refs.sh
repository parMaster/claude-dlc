#!/usr/bin/env bash
# PreToolUse hook (Edit/Write/MultiEdit): blocks new code comments that point
# somewhere else instead of explaining — a ticket ID, a Jira/Confluence/PR
# link, a commit SHA, a slice marker, or a path to a plan/spec doc.
#
# Only lines being added are checked, and only comment lines in code files,
# so an old comment never blocks an edit near it and Markdown/JSON are free
# to hold ticket IDs and links.

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
FILE=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")
[[ -z "$FILE" ]] && exit 0

EXT=$(tr '[:upper:]' '[:lower:]' <<<"${FILE##*.}")
case "$EXT" in
  go|js|jsx|ts|tsx|mjs|cjs|py|sh|bash|zsh|rb|java|kt|kts|rs|swift|c|h|cc|cpp|hpp|sql|yaml|yml|toml|tf) ;;
  *) exit 0 ;;
esac

# lines of $1 not present verbatim in $2
added_lines() {
  grep -vxF -f <(printf '%s\n' "$2") <<<"$1" || true
}

case "$TOOL" in
  Edit)
    ADDED=$(added_lines "$(jq -r '.tool_input.new_string // empty' <<<"$INPUT")" \
                        "$(jq -r '.tool_input.old_string // empty' <<<"$INPUT")")
    ;;
  MultiEdit)
    ADDED=""
    N=$(jq '.tool_input.edits | length' <<<"$INPUT")
    for ((i = 0; i < N; i++)); do
      ADDED+=$(added_lines "$(jq -r ".tool_input.edits[$i].new_string // empty" <<<"$INPUT")" \
                           "$(jq -r ".tool_input.edits[$i].old_string // empty" <<<"$INPUT")")
      ADDED+=$'\n'
    done
    ;;
  Write)
    CONTENT=$(jq -r '.tool_input.content // empty' <<<"$INPUT")
    if [[ -f "$FILE" ]]; then
      ADDED=$(added_lines "$CONTENT" "$(cat "$FILE")")
    else
      ADDED=$CONTENT
    fi
    ;;
  *) exit 0 ;;
esac

COMMENTS=$(grep -E '^[[:space:]]*(//|#|/\*|\*|--)' <<<"$ADDED" || true)
[[ -z "$COMMENTS" ]] && exit 0

# Standard names shaped like ticket IDs: UTF-8, SHA-256, RFC-7231, ...
STANDARD='^(UTF|SHA|RFC|AES|ISO|CRC|TLS|SSL|HTTP|PKCS|ECMA|IEEE|CVE|UUID|MD|ES|X)-'

find_ref() {
  local line="$1" m
  m=$(grep -oE '(^|[^A-Za-z0-9_-])[A-Z][A-Z0-9]+-[0-9]+' <<<"$line" | sed -E 's/^[^A-Z]//' \
      | grep -vE "$STANDARD" | head -1)
  [[ -n "$m" ]] && { echo "ticket ID \"$m\""; return; }

  m=$(grep -oiE 'https?://[^[:space:]]*(atlassian\.net|jira\.|confluence\.|/browse/[A-Z]|/pull/[0-9]+|/merge_requests/[0-9]+)[^[:space:]]*' <<<"$line" | head -1)
  [[ -n "$m" ]] && { echo "link \"$m\""; return; }

  m=$(grep -oE 'docs/(plans|specs)/[^[:space:]]*\.md' <<<"$line" | head -1)
  [[ -n "$m" ]] && { echo "plan/spec pointer \"$m\""; return; }

  m=$(grep -oE '(^|[^A-Za-z])Slice [0-9A-Z]([^A-Za-z0-9]|$)' <<<"$line" | grep -oE 'Slice [0-9A-Z]' | head -1)
  [[ -n "$m" ]] && { echo "slice marker \"$m\""; return; }

  # Commit SHA: 7–40 hex chars with both a digit and a letter, standing alone
  # (so 1234567, 0xdeadbeef and UUID segments don't count).
  for m in $(grep -oE '(^|[^0-9A-Za-z_-])[0-9a-f]{7,40}([^0-9A-Za-z_-]|$)' <<<"$line" | grep -oE '[0-9a-f]{7,40}'); do
    if [[ "$m" =~ [0-9] && "$m" =~ [a-f] ]]; then
      echo "commit SHA \"$m\""
      return
    fi
  done
}

while IFS= read -r line; do
  REF=$(find_ref "$line")
  if [[ -n "$REF" ]]; then
    TRIMMED=$(sed -E 's/^[[:space:]]+//' <<<"$line")
    jq -n --arg r "New comment in $FILE points somewhere instead of explaining — $REF in: $TRIMMED. Rewrite it to state the why a reader needs at this spot, in 1–2 lines, with no ticket, link, SHA, slice or plan reference." '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
  fi
done <<<"$COMMENTS"

exit 0
