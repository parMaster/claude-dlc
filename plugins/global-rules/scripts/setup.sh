#!/usr/bin/env bash
# On plugin install/update:
# 1. append an @import line for shared rules into ~/.claude/CLAUDE.md
# 2. ensure CLAUDE_AFK_TIMEOUT_MS is set in ~/.claude/settings.json
# 3. ensure ScheduleWakeup is in permissions.deny in ~/.claude/settings.json
# 4. ensure bashOutputMaxChars is set in ~/.claude/settings.json
# 5. ensure spinnerVerbs is set in ~/.claude/settings.json
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

# Ensure AskUserQuestion dialogs (e.g. review-plan's runtime/model-choice
# prompts) don't auto-timeout after the 60s default. Only set it if the user
# hasn't already configured their own value — never clobber an existing
# setting.
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

# Deny ScheduleWakeup. Self-scheduled wakeups were only ever used to poll work
# the harness already reports on completion, so every firing was a wasted turn.
# The permission layer settles it once instead of a rule in every context.
# Appends without reordering existing deny entries; re-added on update if
# removed by hand.
HAS_DENY=$(jq -r '(.permissions.deny // []) | index("ScheduleWakeup") // "" ' "$SETTINGS" 2>/dev/null)
if [ -z "$HAS_DENY" ]; then
  tmpfile=$(mktemp)
  if jq '.permissions.deny = ((.permissions.deny // []) + ["ScheduleWakeup"])' "$SETTINGS" > "$tmpfile" 2>/dev/null && [ -s "$tmpfile" ]; then
    mv "$tmpfile" "$SETTINGS"
  else
    rm -f "$tmpfile"
  fi
fi

# Cap inline Bash/PowerShell output at the harness floor (4000 chars). Output
# past this is saved to a file with a short preview + path instead of being
# dumped into context — this is what stops a model from polluting context
# with `tail -300`-style debug dumps no matter what command shape it uses
# (tail, cat, a script), since it acts on the actual output size rather than
# pattern-matching commands. Only set if the user hasn't already configured
# their own value — never clobber an existing setting.
CURRENT_MAX_CHARS=$(jq -r '.bashOutputMaxChars // ""' "$SETTINGS" 2>/dev/null)
if [ -z "$CURRENT_MAX_CHARS" ]; then
  tmpfile=$(mktemp)
  if jq '.bashOutputMaxChars = 4000' "$SETTINGS" > "$tmpfile" 2>/dev/null && [ -s "$tmpfile" ]; then
    mv "$tmpfile" "$SETTINGS"
  else
    rm -f "$tmpfile"
  fi
fi

# Replace the whimsical spinner verbs ("Kerfuffling…") with plain ones. Only
# set if the user hasn't already configured their own spinnerVerbs — never
# clobber an existing setting.
CURRENT_SPINNER=$(jq -r '.spinnerVerbs // "" | tostring' "$SETTINGS" 2>/dev/null)
if [ -z "$CURRENT_SPINNER" ]; then
  tmpfile=$(mktemp)
  if jq '.spinnerVerbs = {"mode": "replace", "verbs": ["Thinking", "Processing", "Working"]}' "$SETTINGS" > "$tmpfile" 2>/dev/null && [ -s "$tmpfile" ]; then
    mv "$tmpfile" "$SETTINGS"
  else
    rm -f "$tmpfile"
  fi
fi
