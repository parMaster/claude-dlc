# Changelog

Personal Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries sorted newest first.

## statusline v1.0.2 - 2026-06-10

### Bug Fixes

- Replace non-functional `statusLine` key in hooks.json with a `Setup` hook that writes the correct `statusLine` entry to `~/.claude/settings.json` on install
- Uses stable marketplace path so version bumps don't break the config

## global-rules v1.0.0 - 2026-06-10

### New Features

- setup hook appends `@import` line to `~/.claude/CLAUDE.md` on install — non-destructive, idempotent
- ships plan-first workflow, commit hygiene, Go tooling (gosymdb), CLI best practices rules

## statusline v1.0.1 - 2026-06-10

### Bug Fixes

- hooks.json: add required `hooks` key to satisfy plugin schema validator (was causing "Hook load failed" on install)

## statusline v1.0.0 - 2026-06-09

### New Features

- custom status line script (robbyrussell-style): dir, git branch + dirty indicator, model name, context %, 5h/7d usage rates with reset time

## planning v1.1.0 - 2026-06-09

### New Features

- `pr` — draft PR creation skill; interactive title composition (type/ticket/title), description generated from plan file following writing-style principles
- plan template: final task now includes `planning:pr` invocation step

## planning v1.0.0 - 2026-06-09

### New Features

- `plan` — implementation plan creation skill with context gathering, approach exploration, revdiff review loop; adapted from cc-thingz (MIT), exec machinery and custom rules removed, single-summary-commit constraint baked in

## brainstorm v1.0.0 - 2026-06-09

### New Features

- `brainstorm` — collaborative design dialogue skill; adapted from cc-thingz (MIT), custom rules machinery removed

## style v1.0.0 - 2026-06-09

### New Features

- `writing-style` — direct, brief style guide for PRs, tickets, code review comments, and commit messages; adapted from cc-thingz (MIT)

## go-tools v1.0.0 - 2026-06-09

### New Features

- `block-explore-in-go` — PreToolUse hook that blocks the Explore agent in Go projects and redirects to gosymdb skills
- `block-gosymdb-pipe` — PreToolUse hook that blocks piping gosymdb output to python/jq
