#!/usr/bin/env bash
# On plugin install/update: append an @import line for shared rules into ~/.claude/CLAUDE.md.
# Never overwrites existing content — only adds one line, idempotently.

GLOBAL_CLAUDE="${HOME}/.claude/CLAUDE.md"

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
if grep -qF "$IMPORT_LINE" "$GLOBAL_CLAUDE"; then
  exit 0
fi

echo "" >> "$GLOBAL_CLAUDE"
echo "$IMPORT_LINE" >> "$GLOBAL_CLAUDE"
