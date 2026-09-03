# Changelog

Personal Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries sorted newest first.

## global-rules 1.2.0 - 2026-09-03

Added "Atlassian MCP Hygiene" rule: scope Jira MCP calls (`getJiraIssue`,
`searchJiraIssuesUsingJql`) with an explicit minimal `fields` array and
`responseContentFormat: "markdown"` instead of relying on the default
field set, which pulls in nested `assignee`/`reporter`/`project` objects
full of avatar URLs and self-links even for a one-line status check.
Also documents delegating multi-step Jira work (status transition +
comment + subtask listing, bulk JQL) to a subagent so raw multi-call
output stays out of the main session. Considered and rejected a
`PreToolUse` hook enforcing this on the same two tool names — too narrow
against the ~40-tool Atlassian MCP surface, would give false confidence.

## planning 1.14.0 - 2026-08-31

Added `spawn-session` — hand off an arbitrary task (not just a plan file)
to a fresh, independent agterm session. Triggers from natural language
("spawn a new session for this", "hand this off to a separate session",
etc.) as well as `/planning:spawn-session [task]`. Can group related
slices of one job under a shared named workspace. The new session's
terminal shows the launch command (`claude "$(cat <tmpfile>)"`) rather
than the prompt text itself — cosmetic, the spawned Claude session
receives and echoes the real prompt once it starts. Split the agterm
hand-off script into a generic primitive (`agterm-spawn.sh`) and a thin
plan-specific wrapper (`agterm-handoff.sh`) — no behavior change for
`plan`/`review-plan`/`handoff`.

## planning 1.13.3 - 2026-08-31

Renamed the `implement-in-session` skill to `handoff` — shorter and clearer
now that `/planning:implement-in-session` is `/planning:handoff`. No
behavior change.

## planning 1.13.2 - 2026-08-31

plan-review agent instructions were telling it to shell out via Bash for
`grep`/`rg`/`cat`/`ls`/`find`, triggering needless permission prompts even
though the agent already has the no-prompt Grep/Glob/Read tools. Now
points it at those tools for search/read and reserves Bash for `go doc`
and `go env`.

## global-rules 1.1.5 - 2026-08-31

Auto-Memory Discipline reworked into two gates instead of one. Previously
any write just needed the user's confirmation; now a save must first pass
relevance checks — not already recorded elsewhere (code/CLAUDE.md/git
history) and useful in a future unrelated session — before confirmation
is even asked, so feedback/corrections stop auto-triggering a save
proposal on their own. Also narrowed the "explicit ask" exception so it
only fires on an unambiguous instruction to write to memory itself
("remember this", "save that to memory"), not a colloquial "remember" used
about a task ("we should remember to update the ticket").

## planning 1.13.1 - 2026-08-31

`review-plan`'s Step 2 now explicitly requires printing the review agent's
full report as a chat message before moving to Step 3's AskUserQuestion.
Previously the step just said "show the report", which a background-agent
round could satisfy without ever printing it — once a background agent
finishes there is no panel left to expand, so the user would see the "Fix
and re-review?" prompt with the findings nowhere in the conversation.

## planning 1.13.0 - 2026-08-31

`plan` skill no longer hardcodes `go test ./...` as the full-suite test
command. Step 0 context gathering now resolves the repo's actual test
command (`make test` if a Makefile has a `test` target, else the invocation
from `.github/workflows/*.yml`/`.gitlab-ci.yml`, else falls back to
`go test ./...`), and generated plans use that resolved command. Also adds
guidance to retry once with `-p=1` when full-suite failures look like
shared-state flakiness between parallel tests rather than a real bug —
distinguished by whether the failure reproduces when the same test is run
alone.

## go-tools — removed 2026-08-27

Removed the plugin entirely, at the owner's request. All three hooks
(`block-explore-in-go`, `block-go-symbol-grep`, `block-gosymdb-pipe`) existed
only to enforce use of gosymdb, which was disabled over a month ago because
it didn't work as intended and won't be used going forward. Dropped from
`marketplace.json` and README.md along with it.

## agterm-hooks — removed 2026-08-27

Removed the plugin entirely. Its `Stop`/`Notification` sidebar-status hooks
duplicated agterm's own built-in agent-status glyphs (`~/.config/agterm/agent-status/`,
wired directly into `~/.claude/settings.json`, predating this plugin), and the
one thing it added on top — a completion sound — never worked. Only the
auto-flag-on-hand-off change (`planning` v1.12.0, `agterm-handoff.sh`) is kept.

## agterm-hooks v1.0.1 - 2026-08-27

### Fixes

- `stop-status.sh`/`notification-status.sh` resolved `agtermctl` via `command -v agtermctl` (PATH lookup), which silently fails: a Claude Code hook runs with a restricted PATH that doesn't include `/opt/homebrew/bin` or wherever an interactive shell's PATH resolves it, so the hooks never actually called `agtermctl` and no status/sound ever fired. Fixed by adding `resolve-agtermctl.sh`, a shared resolver mirroring the approach agterm's own installer already uses for its bundled agent-status hook (`~/.config/agterm/agent-status/agterm-agent-status.sh`): check `$AGTERMCTL` override, then `/usr/local/bin/agtermctl`, then the bundled `/Applications/agterm.app/Contents/MacOS/agtermctl`, then bare `agtermctl` on PATH as a last resort. Both scripts also now forward `--socket "$AGTERM_SOCKET"` when set, and gate on `AGTERM_SESSION_ID` alone instead of also requiring `AGTERM_ENABLED=1` (redundant — both are always set together), matching that same reference script.

## agterm-hooks v1.0.0 - 2026-08-27

### Features

- New plugin: `Stop` and `Notification` hooks that flag the current agterm session's sidebar status (`completed`/`blocked`, with sound on completion) when Claude Code running inside agterm finishes responding or needs attention. Not planning-specific — applies to any Claude Code session hosted in an agterm pane, not just plan hand-offs. No-op outside agterm.

## planning v1.12.0 - 2026-08-27

### Features

- `agterm-handoff.sh` (shared by `plan`, `review-plan`, `implement-in-session`) now flags the newly created session (`agtermctl session flag on`), so every hand-off shows up in agterm's flagged sidebar view / flagged-dashboard grid instead of having to be found and flagged by hand.

## planning v1.11.1 - 2026-08-26

### Fixes

- Deduped the agterm hand-off sequence: `plan`, `review-plan`, and `implement-in-session` each embedded their own copy of the `agtermctl` session-creation/type sequence. All three now call one shared `plugins/planning/scripts/agterm-handoff.sh`. A `Skill`-tool-based dedup (having `plan`/`review-plan` invoke `implement-in-session` directly) wasn't possible: `implement-in-session` has `disable-model-invocation: true`, which blocks any Claude-initiated `Skill` call, not just natural-language auto-triggering — a bundled shell script has no such gate.

## planning v1.11.0 - 2026-08-26

### Features

- Added `implement-in-session` — an explicit-only skill (`disable-model-invocation: true`) that hands a plan straight to a fresh agterm session, skipping `plan`'s and `review-plan`'s menus entirely. Resolves the plan file from an argument or falls back to the most recently modified plan under `docs/plans/`, then runs the same agterm hand-off sequence those two skills already offer inline.

## planning v1.10.1 - 2026-08-26

### Fixes

- `review-plan`: fixed `subagent_type` — the skill called `plan-review`, but plugin agents are namespaced (`planning:plan-review`), causing an "Agent type not found" error before the harness fell back to the correct name.

## planning v1.10.0 - 2026-08-26

### Features

- `plan` and `review-plan`: added "Implement in a Separate Session" alongside the existing "Implement in a Subagent" option — hands off implementation to a brand-new agterm terminal session (a fresh `claude` CLI invocation) in the same workspace, instead of a background subagent. Runs interactively; the user can switch to it and watch or drive it directly. `plan`'s Step 3 menu also gained "Implement in a Subagent" itself (copied verbatim from `review-plan`'s), so both menus now offer the same four terminal options. Both hand-offs are gated on `AGTERM_ENABLED=1` and `agtermctl` resolving on PATH — silently omitted from the menu when the session isn't running inside agterm.

## global-rules v1.1.4 - 2026-08-19

### Fixes

- Response Brevity: added "Conclusion before justification, always" and "No self-critique preamble" rules — responses were leaking self-correction monologue and process commentary ("You're right, that was made up...", "I made this harder than it needed to be...") before the actual answer, forcing the user to read through it to reach content that turned out not to matter. Conclusion now leads unconditionally; any reasoning trail worth keeping goes after it, and self-critique of the prior turn gets cut rather than fronted.

## statusline v1.0.5 - 2026-08-01

### Improvements

- `ctx:N%` now renders in magenta once context usage exceeds 30% (was always dim), as an early visual warning before compaction.

## planning v1.9.0 - 2026-08-13

### Fixes

- `review-plan`: the review agent ran as `general-purpose` (all tools), so its prompt-only "READ-ONLY" instruction was advisory, not enforced — it was observed writing plan-derived `.go` files and tests, running them, then deleting them, in the name of "verification." It's now a dedicated `plan-review` subagent (`plugins/planning/agents/plan-review.md`) restricted to Read/Glob/Grep/Bash — Write, Edit, and NotebookEdit aren't in its tool list, so it cannot create, modify, or delete files regardless of what its prompt says. Its instructions also now explicitly forbid executing code (`go run`/`go test`/etc.) or redirecting Bash output to a file, even "to check."
- `review-plan`: round > 1 was re-running the expensive verification steps (dependency behavior, error tracing, test preconditions, multi-phase state) against the *entire* plan every time, on top of a fresh full read of source and vendor code — burning hundreds of thousands of tokens per round for mostly-repeat findings. Rounds > 1 now scope those steps to just the sections/tasks the last round's fixes touched (plus shared dependencies); the cheap checklist pass still covers the whole plan.

## planning v1.8.0 - 2026-08-13

### Features

- `review-plan`: every time the review agent is about to spawn — first review, a "Fix and re-review" continuation, or "Run auto-review" from the post-review menu — asks which model should run that round (Inherit/Opus/Sonnet/Haiku), matching the existing model choice for the implementer handoff.

## global-rules v1.1.3 - 2026-08-13

### Improvements

- Response Brevity: the "plain words" rule now names concrete swaps (utilize→use, leverage→use, facilitate→help, ...), caps technical terms at one per sentence, and requires a reread-before-send check — the old wording was a soft aspiration that kept fading back into jargon over the course of a session. Added a stickiness clause: a correction on this holds for the rest of the session, not just the next reply.

## global-rules v1.1.2 - 2026-07-30

### Improvements

- Removed the "never include co-authored tag line" prompt rule — superseded by the `attribution.commit`/`attribution.pr` settings (see `~/.claude/settings.json`), which is the mechanism Claude Code actually consults to build the commit/PR trailer, rather than a prompt instruction that has to be re-followed every commit.

## planning v1.7.0 - 2026-07-28

### Features

- `review-plan`: reviewer now classifies each finding as MECHANICAL (provable by a command — counts, stale identifiers, un-updated locations) or REASONED (needs judgment), and every MECHANICAL finding must ship a `verify:` command with expected output.
- `review-plan`: after a fix pass, the orchestrating session re-runs the `verify:` command for every MECHANICAL finding before continuing — an unverified mechanical fix can't trigger a new round.
- `review-plan`: if a round's findings were all MECHANICAL, the loop skips spawning another review agent (all fixes are already verified by command) and goes straight to the post-review menu instead of burning a full round on bookkeeping.
- `review-plan`: round 2+ prompts now carry a concrete "fixes applied since last round" list, and the reviewer must return a correct/incomplete/introduced-a-new-problem verdict per fix instead of a vague independence reminder.
- `review-plan`: added a "Decision conflict" checklist item (Critical) — flags plans that contradict a recorded decision elsewhere in the repo (decision log, WBS scope note, prior plan) without a full, command-backed enumeration of every stale location.

### Why

Owner reported that after the Opus 4.8 → 5 upgrade, later review rounds stopped finding real issues and instead manufactured minor nitpicks to justify NEEDS REVISION — because the reviewer reasons well but never counts, and fix passes mostly introduce bookkeeping errors (missed locations, stale references) that reasoning alone doesn't reliably catch. Distinguishing provable findings from judgment calls, and gating rounds on actually running the proof, targets that failure mode directly.

## planning v1.6.0 - 2026-07-21

### Features

- `review-plan`: the "Implement in a Subagent" hand-off now asks which model the implementer should run on (Inherit / Opus / Sonnet / Haiku) and passes it via the Agent tool's `model` parameter. Previously the subagent always inherited the main session's model with no way to choose.

## global-rules v1.1.1 - 2026-07-17

### Improvements

- Added a "Dependency source lookup" rule to the Go codebases section: check `./vendor/<module-path>` in the current repo before falling back to `go env GOMODCACHE` when reading a dependency's source. Owner kept catching Claude going straight to GOMODCACHE despite the repo already having the dependency vendored.

## planning v1.5.2 - 2026-07-17

### Improvements

- `review-plan`: added a "When NOT to flag" counter-list (reasonable abstractions, domain-inherent complexity, patterns matching existing conventions) and a confidence-framing rule — uncertain over-engineering calls should be raised as a question, not a finding. Adapted from cc-thingz's `plan-review` agent, which had this as an explicit checklist but our skill only had a one-line "do not nitpick style" reminder.

## global-rules v1.1.0 - 2026-07-06

### New Features

- Add `block-root-find` — PreToolUse hook on Bash that denies `find` commands rooted at `/` (a full-filesystem scan). Regex-matches the raw command string, so it catches the pattern even inside `$(...)` command substitution or a variable assignment, which a plain `permissions.deny` rule can't see into. Triggered by an owner catching an agent running `find / -type d ...` unprompted. Covered by `tests/run.sh`.

## global-rules v1.0.9 - 2026-07-03

### New Features

- Add "Response Brevity" rule — short answers to simple questions, plain vocabulary over jargon, small text diagrams instead of prose for describing flows/relationships, no recaps or restating the question before acting. Owner reported feeling overwhelmed by multi-paragraph, jargon-heavy responses across both Opus and Sonnet 5.

## planning v1.5.1 - 2026-07-03

### Bug Fixes

- `review-plan`: Step 4 ("Behavior verification") now tells the review subagent to check `vendor/` (or `go env GOMODCACHE`) for dependency source before grepping, and explicitly forbids whole-filesystem `find /` searches. Without this, a fresh `general-purpose` subagent had no way to know dependencies are vendored in-repo and resorted to scanning the entire filesystem to locate a library's source.

## global-rules v1.0.8 - 2026-07-03

### New Features

- Add "Auto-Memory Discipline" rule — confirm with the user before writing to the auto-memory system instead of saving silently, except when the user explicitly asked to remember something. Prevents unconfirmed memory writes from stacking up several at a time.

## global-rules v1.0.7 - 2026-07-03

### New Features

- Setup hook now also ensures `CLAUDE_AFK_TIMEOUT_MS` is set to `86400000` (24h) in `~/.claude/settings.json`, so `AskUserQuestion` dialogs (e.g. review-plan's post-review menu) don't auto-submit after the 60s default on every machine the plugin is installed/updated on. Idempotent and non-destructive — only sets it if the user hasn't already configured their own value.

## global-rules v1.0.6 - 2026-07-02

### New Features

- Add "Git Hygiene" section with a "Stale branch" rule — check `git fetch`/`git status` against the remote tracking branch before planning/implementing and again right before the final commit, resyncing (`git pull --rebase`) immediately instead of discovering drift only when `git push` is rejected.

### Bug Fixes

- Removed the "Go codebases" gosymdb rule and its stray reference under "Verification Before Commit" — gosymdb is temporarily disabled, so the instruction was steering every project (Go or not, gosymdb-equipped or not) toward a tool that isn't available. The unrelated "Vendored dependencies" rule stays, since it doesn't depend on gosymdb.

## planning v1.5.0 - 2026-07-02

### New Features

- `review-plan`: added "Implement in a Subagent" to the post-review menu — dispatches a background `general-purpose` agent with the plan file and a plain hand-off prompt (no per-task review scaffolding), reports back on completion. Lighter-weight alternative to superpowers' `subagent-driven-development` for people who found the per-task review loop token-heavy for little visible benefit.

## planning v1.4.5 - 2026-07-01

### Bug Fixes

- `review-plan`: removed the inline gosymdb rule and its use in the dependency-behavior-verification step. The review subagent already inherits the gosymdb rule from global-rules CLAUDE.md, so restating it here was redundant — and gosymdb is temporarily disabled, so the explicit instruction was steering the agent toward a tool it can't use. Falls back to grep/Read for symbol lookup.

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
