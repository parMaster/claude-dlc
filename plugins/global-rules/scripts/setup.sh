#!/usr/bin/env bash
# On plugin install/update:
# 1. append an @import line for shared rules into ~/.claude/CLAUDE.md
# 2. ensure CLAUDE_AFK_TIMEOUT_MS is set in ~/.claude/settings.json
# Never overwrites existing content — only adds what's missing, idempotently.

GLOBAL_CLAUDE="${HOME}/.claude/CLAUDE.md"
SETTINGS="${HOME}/.claude/settings.json"

# Derive stable marketplace path from CLAUDE_PLUGIN_ROOT
# CLAUDE_PLUGIN_ROOT = .../plugins/cache/<marketplace>/<plugin>/<version>
PLUGINS_DIR=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|/cache/.*||')
MARKETPLACE_ID=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|.*/cache/||' | cut -d'/' -f1)
PLUGIN_NAME=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|.*/cache/||' | cut -d'/' -f2)
STABLE_RULES="${PLUGINS_DIR}/marketplaces/${MARKETPLACE_ID}/plugins/${PLUGIN_NAME}/CLAUDE.md"

IMPORT_LINE="@${STABLE_RULES}"

# Create CLAUDE.md if it doesn't exist yet
if [ ! -f "$GLOBAL_CLAUDE" ]; then
  touch "$GLOBAL_CLAUDE"
fi

# Skip if already imported
if ! grep -qF "$IMPORT_LINE" "$GLOBAL_CLAUDE"; then
  echo "" >> "$GLOBAL_CLAUDE"
  echo "$IMPORT_LINE" >> "$GLOBAL_CLAUDE"
fi

# Ensure AskUserQuestion dialogs (e.g. review-plan's post-review menu) don't
# auto-timeout after the 60s default. Only set it if the user hasn't already
# configured their own value — never clobber an existing setting.
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

CURRENT_TIMEOUT=$(jq -r '.env.CLAUDE_AFK_TIMEOUT_MS // ""' "$SETTINGS" 2>/dev/null)
if [ -z "$CURRENT_TIMEOUT" ]; then
  tmpfile=$(mktemp)
  if jq '.env.CLAUDE_AFK_TIMEOUT_MS = "86400000"' "$SETTINGS" > "$tmpfile" 2>/dev/null && [ -s "$tmpfile" ]; then
    mv "$tmpfile" "$SETTINGS"
  else
    rm -f "$tmpfile"
  fi
fi
