# Changelog

Personal Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries sorted newest first.

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
