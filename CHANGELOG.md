# Changelog

Personal Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries sorted newest first.

## planning v1.1.2 - 2026-06-16

### Bug Fixes

- `pr`: check for existing PR before creating — if one exists, read current description and amend it with new plan content rather than replacing it; use `gh pr edit` for updates

## planning v1.1.1 - 2026-06-16

### Bug Fixes

- `plan`: stop invoking `revdiff:revdiff` as a nested skill — instead tell the user to run `/revdiff:revdiff <plan-file>` directly; fixes overlay not opening due to timeout/terminal detection issues in nested skill context
- `plan`: remove auto-commit of plan file after creation — user decides if/when to commit

## global-rules v1.0.2 - 2026-06-15

### New Features

- Verification Before Commit: require linter check before committing (e.g. `golangci-lint run ./...` for Go, `eslint .` for JS/TS)

## git-tools v1.0.1 - 2026-06-11

### Bug Fixes

- `squash-rebase`: when heuristic cut point looks wrong, show `git log --oneline <parent-branch>` to help user pick the correct one manually

## git-tools v1.0.0 - 2026-06-11

### New Features

- `squash-rebase` — rebase current branch onto main after its parent was squash-merged; auto-detects cut point via file overlap heuristic, confirms with user before running `git rebase --onto`

## statusline v1.0.3 - 2026-06-10

### Bug Fixes

- hooks.json: add `matcher: "init"` to Setup hook — fires on install/init only, not on maintenance runs
- README: document that `claude --init-only` must be run once after install to activate setup

## global-rules v1.0.1 - 2026-06-10

### Bug Fixes

- hooks.json: add `matcher: "init"` to Setup hook — fires on install/init only, not on maintenance runs
- README: document that `claude --init-only` must be run once after install to activate setup

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
