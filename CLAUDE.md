# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Purpose

Personal Claude Code plugins and skills — hooks, skills, and commands organized as a marketplace of independent plugins.

Inspired by [cc-thingz](https://github.com/umputun/cc-thingz) (MIT licensed, Umputun). The philosophy here is intentionally lighter: skills are right-sized for actual daily use rather than maximum capability. When adapting from cc-thingz, strip out phases or complexity that aren't needed.

## Installing on a New Machine

Add the marketplace and install individual plugins:

```
/plugin marketplace add parmaster/claude-dlc
/plugin install <plugin-name>@parmaster-claude-dlc
```

## Key Rules

- **README.md must be kept up to date** — whenever a plugin or skill is added or changed, update README.md with what it does and how to use it.
- This is a personal project. Content is MIT-licensed.
- **No personal configuration** — no hardcoded paths, editor preferences, or machine-specific settings. Use environment variables (e.g., `$EDITOR`) for user-specific values.
- **Self-contained documentation** — all docs must refer only to what exists in this repository.

## Structure

- `.claude-plugin/marketplace.json` — marketplace catalog listing all available plugins
- `plugins/` — each subdirectory is an independent plugin:
  - Each plugin has `.claude-plugin/plugin.json` with name, description, version, author
  - Standard subdirs (use only what's needed): `skills/`, `commands/`, `hooks/`, `scripts/`, `references/`
- `CHANGELOG.md` — version history, one section per plugin version bump

## Conventions

- Hook scripts use `${CLAUDE_PLUGIN_ROOT}` for path resolution — plugin files are copied to a cache on install, so absolute/relative paths fail.
- **Versioning** — each plugin has its own `version` in `plugins/<name>/.claude-plugin/plugin.json`. Use semver: patch for fixes, minor for new components, major for breaking changes. Bump on *any* change to bundled content (skills, scripts, references, hooks) — not just plugin.json.
- **Changelog** — when bumping a version, update `CHANGELOG.md` in the same commit. Heading format: `## plugin-name vX.Y.Z - YYYY-MM-DD`.
- **Version bump is part of the change** — NEVER make a content change to a plugin without bumping its version and updating `CHANGELOG.md` in the same commit. Do not leave version bumps for a follow-up commit.
- **Cross-references** — within the same plugin: `/skill-name`. Across plugins: `/plugin-name:skill-name`.
- **Skill files** — `plugins/<plugin>/skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`, `allowed-tools`).

## Adapting from cc-thingz

The sibling repo `../cc-thingz` (MIT, Umputun) is the upstream reference. When pulling something from there:
1. Read the original skill/hook fully first
2. Strip phases or sub-flows that won't be used
3. Remove custom-rules injection unless actually needed
4. Keep `description:` in SKILL.md frontmatter accurate — Claude uses it for intent matching

## Local Development

- Test a plugin locally: `claude --plugin-dir plugins/<name>`
- Reload without restarting: `/reload-plugins`
- Skills are invokable by full name (e.g., `/planning:exec`) — they don't appear in `/` autocomplete dropdown (only `commands/*.md` files do)

## Known Claude Code Limitations

- Plugin skills don't appear in `/` autocomplete. Invoke by typing the full name or via natural language.
- PreToolUse hook denials render as "blocking error" in TUI — cosmetic issue, not fixable from the plugin side.
