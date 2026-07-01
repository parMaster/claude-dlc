# Changelog

Personal Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries sorted newest first.

## planning v1.4.4 - 2026-07-01

### Bug Fixes

- `plan`: Step 1 questions must each go through their own AskUserQuestion call — the tool's schema requires ≥2 options per question, and batching several questions into one call risked one of them (e.g. "Scope," built from discovered files) landing with a single fabricated option and failing validation. The Scope question now falls back to free text when discovery finds only one file/component.

## planning v1.4.3 - 2026-07-01

### Bug Fixes

- `review-plan`: after an APPROVE verdict or hitting the round limit, the skill used to stop silently with "ready for implementation," dead-ending the review loop. It now lands on a "what's next" menu (run auto-review again, switch to revdiff, or Done) and keeps re-asking after every revdiff pass — only an explicit "Done" ends the loop.

## planning v1.4.2 - 2026-06-30

### Bug Fixes

- `plan` + `review-plan`: after a review completes (APPROVE verdict, round limit, or revdiff with no annotations), stop completely — do NOT proceed to implementation. The model was treating "planning is done" as a cue to begin implementing; now both skills have an explicit hard stop with "do NOT suggest or begin implementation."

## global-rules v1.0.5 - 2026-06-26

### Bug Fixes

- Plan-First rule: name the mechanism explicitly — use the `planning:plan` skill (writes `docs/plans/`), even when planning arises organically without the trigger words, and do NOT substitute built-in plan mode (which only prints the plan and saves no document). Closes the trigger-word gap that let the model fall back to plan mode.

## global-rules v1.0.4 - 2026-06-26

### New Features

- Go codebases: add "Vendored dependencies" rule — on stale/inconsistent vendoring (after branch switches or merges), run `go mod tidy && go mod vendor` to resync instead of investigating. Stops agents burning tokens on investigations the user has to interrupt.

## planning v1.4.1 - 2026-06-26

### Bug Fixes

- `plan`: the final "move this plan to completed/" task now specifies plain `mkdir -p && mv` instead of leaving it open (the model was reaching for `git mv`, which fails because the plan is untracked until the single summary commit at the end). Plain `mv` + the final `git add -A` stages the move whether or not the plan was already tracked.

## global-rules v1.0.3 - 2026-06-26

### New Features

- CLI Best Practices: don't prepend `cd <path>` to a Bash command when the session is already rooted in that directory — the shell resets to the working dir each call, so it's redundant. Only `cd` (or `make -C`) when operating outside the session root.

## statusline v1.0.4 - 2026-06-26

### Changes

- statusline: show minutes in the rate-limit reset time — `↺3pm` becomes `↺3:51pm` (format `%l:%M%p`). The epoch was already available; only the hour was being rendered.

## go-tools v1.1.0 - 2026-06-26

### New Features

- `block-go-symbol-grep`: new Bash PreToolUse hook that enforces the "never grep Go symbols" rule. Denies grep/rg/egrep/git-grep when it targets `.go` files, or searches for a Go declaration keyword (`func`/`type`/`interface`/`struct`) inside a Go module, and redirects to `gosymdb:sym` / `gosymdb:trace` / `gosymdb:impact`. The existing `block-gosymdb-pipe` hook only covered gosymdb output piping, so raw symbol greps slipped through with nothing but CLAUDE.md guidance behind them. The go.mod gate keeps it from firing on non-Go projects (e.g. `grep type styles.css`).

### Changes

- `block-explore-in-go`: narrowed from blocking *every* Explore agent in a Go project to only blocking when the Explore prompt/description signals Go-symbol intent (mentions `func`/`type`/`interface`/`struct`/`method`/`receiver`/`symbol`/`caller`/`implementation`/`signature`/`definition`/`.go`, etc.). General exploration of a Go repo (docs, YAML/CI config, Dockerfiles, frontend) is no longer over-blocked.

## planning v1.4.0 - 2026-06-17

### New Features

- `plan`: add "Dependency contract check" step before task writing — for external functions the plan calls, read their bodies and record actual guarantees (privileges, error wrapping, side effects, state); skip for net-new plans with no existing dependencies
- `plan`: add "Verified Dependency Behaviors" section to plan template — quotes source behavior, not names
- `plan`: add dependency behavior check to Step 2.5 self-review
- `review-plan`: replace existence check with behavior verification — read function bodies, confirm plan's claims match implementation
- `review-plan`: add 4 standing checks: (1) behavioral claim vs body, (2) error/status tracing end-to-end through wrapping chain, (3) test setup against API preconditions/ordering, (4) multi-phase state inspection
- `review-plan`: add "Verified Dependency Behaviors" section check to review checklist

## planning v1.3.2 - 2026-06-17

### Bug Fixes

- `review-plan`: bake gosymdb rule directly into agent prompt — subagents don't inherit CLAUDE.md, so the "never grep Go symbols" rule wasn't enforced; now explicitly blocks grep/rg/find for symbol lookup and requires gosymdb:sym/gosymdb:trace with --auto-reindex

## planning v1.3.1 - 2026-06-16

### Bug Fixes

- `pr`: move existing-PR check to Step 2, before any questions — skip type/ticket/title prompts entirely when PR already exists and go straight to amending the description

## planning v1.3.0 - 2026-06-16

### New Features

- `review-plan` — new skill: structured agent-based plan critique loop; spawns a general-purpose agent (gosymdb-capable) that checks correctness, over-engineering, test coverage, task granularity, and convention adherence; presents findings by severity (Critical/Important/Minor) with APPROVE/NEEDS REVISION verdict; iterates up to 3 rounds on user approval; invocable manually on any plan file
- `plan`: "Auto-review" added as a third post-creation option alongside revdiff and Done

## planning v1.2.0 - 2026-06-16

### New Features

- `plan`: testing approach (TDD vs Regular) is now asked as Q2 — before scope — since it shapes every task in the plan
- `plan`: task template has two explicit variants based on the chosen approach: TDD (failing tests → implementation → passing tests) vs Regular (implementation → tests → passing tests)
- `plan`: "No placeholders" rule now explicitly bans single happy-path tests — all test blocks must enumerate error cases, boundary values, and edge cases by name

## planning v1.1.3 - 2026-06-16

### Bug Fixes

- `plan`: restore "Review with revdiff" question at end of planning — invokes `revdiff:revdiff` skill and lets it handle the full annotation loop; no longer manages the loop from the planning side

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
