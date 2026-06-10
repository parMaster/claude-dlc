#!/usr/bin/env bash
# On plugin install/update: write statusLine to ~/.claude/settings.json
# Uses the stable marketplace path so version bumps don't break the config.

SETTINGS="${HOME}/.claude/settings.json"

# Derive stable marketplace path from CLAUDE_PLUGIN_ROOT
# CLAUDE_PLUGIN_ROOT = .../plugins/cache/<marketplace>/<plugin>/<version>
PLUGINS_DIR=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|/cache/.*||')
MARKETPLACE_ID=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|.*/cache/||' | cut -d'/' -f1)
PLUGIN_NAME=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|.*/cache/||' | cut -d'/' -f2)
STABLE_SCRIPT="${PLUGINS_DIR}/marketplaces/${MARKETPLACE_ID}/plugins/${PLUGIN_NAME}/scripts/statusline.sh"

if [ ! -f "$SETTINGS" ]; then
  exit 0
fi

CURRENT=$(jq -r '.statusLine.command // ""' "$SETTINGS" 2>/dev/null)

# Skip if already pointing to this stable path
if [ "$CURRENT" = "bash $STABLE_SCRIPT" ]; then
  exit 0
fi

# Skip if user has a non-plugin statusLine configured (don't overwrite)
if [ -n "$CURRENT" ] && [[ "$CURRENT" != *"/plugins/"* ]]; then
  exit 0
fi

tmpfile=$(mktemp)
if jq --arg cmd "bash $STABLE_SCRIPT" \
  '.statusLine = {"type": "command", "command": $cmd}' \
  "$SETTINGS" > "$tmpfile" 2>/dev/null && [ -s "$tmpfile" ]; then
  mv "$tmpfile" "$SETTINGS"
else
  rm -f "$tmpfile"
  exit 1
fi
