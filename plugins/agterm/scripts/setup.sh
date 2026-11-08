#!/usr/bin/env bash
# Setup hook (claude --init-only): wires mailbox-chat.py into the places the plugin
# itself can't reach. Idempotent; never rewrites a line the user wrote.
# 1. ~/.local/bin/mailbox-chat.py -> the stable marketplace copy, so Codex and the
#    reply line inside every chat message can call it by bare name
# 2. ~/.codex/rules/default.rules: let Codex run `mailbox-chat.py say --file` outside
#    its sandbox, which refuses agterm's socket (only when ~/.codex exists)
# 3. agterm hooks.conf: an `on message` line that hands mail to Codex (only when the
#    file exists), then reload agterm's hooks

# CLAUDE_PLUGIN_ROOT = .../plugins/cache/<marketplace>/<plugin>/<version>; the marketplace
# checkout keeps one path across version bumps.
PLUGINS_DIR=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|/cache/.*||')
MARKETPLACE_ID=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|.*/cache/||' | cut -d'/' -f1)
PLUGIN_NAME=$(echo "$CLAUDE_PLUGIN_ROOT" | sed 's|.*/cache/||' | cut -d'/' -f2)
STABLE_SCRIPT="${PLUGINS_DIR}/marketplaces/${MARKETPLACE_ID}/plugins/${PLUGIN_NAME}/scripts/mailbox-chat.py"

BIN_DIR="${HOME}/.local/bin"
LINK="${BIN_DIR}/mailbox-chat.py"
CODEX_DIR="${HOME}/.codex"
CODEX_RULES="${CODEX_DIR}/rules/default.rules"
HOOKS_CONF="${XDG_CONFIG_HOME:-${HOME}/.config}/agterm/hooks.conf"

# 1. PATH link; a regular file there is the user's own copy and stays
mkdir -p "$BIN_DIR"
if [ -L "$LINK" ] || [ ! -e "$LINK" ]; then
  ln -sfn "$STABLE_SCRIPT" "$LINK"
else
  echo "agterm setup: $LINK exists and is not a link; left as is" >&2
fi
case ":${PATH}:" in
  *":${BIN_DIR}:"*) ;;
  *) echo "agterm setup: $BIN_DIR is not on PATH; add it so mailbox-chat.py runs by name" >&2 ;;
esac

# 2. Codex sandbox rule; host_executable pins the name to these files, so a
#    mailbox-chat.py written into the workspace doesn't run outside the sandbox
if [ -d "$CODEX_DIR" ]; then
  mkdir -p "$(dirname "$CODEX_RULES")"
  touch "$CODEX_RULES"
  if ! grep -qF 'host_executable(name="mailbox-chat.py"' "$CODEX_RULES"; then
    printf 'host_executable(name="mailbox-chat.py", paths=["%s", "%s"])\n' "$LINK" "$STABLE_SCRIPT" >> "$CODEX_RULES"
  fi
  if ! grep -qF 'prefix_rule(pattern=["mailbox-chat.py", "say", "--file"]' "$CODEX_RULES"; then
    echo 'prefix_rule(pattern=["mailbox-chat.py", "say", "--file"], decision="allow")' >> "$CODEX_RULES"
  fi
fi

# 3. agterm message hook
if [ -f "$HOOKS_CONF" ] && ! grep -qF 'mailbox-chat.py agterm-hook' "$HOOKS_CONF"; then
  printf '\n# Hand pane mail to a Codex in a mailbox chat.\non message %s agterm-hook\n' "$STABLE_SCRIPT" >> "$HOOKS_CONF"
  if command -v agtermctl >/dev/null 2>&1; then
    agtermctl hooks reload >/dev/null 2>&1 || true
  fi
fi

exit 0
