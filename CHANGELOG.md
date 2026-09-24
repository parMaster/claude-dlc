# Changelog

Personal Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries sorted newest first.

## planning 1.23.3 - 2026-09-24

Plan template's Progress Tracking section now says how to tick boxes: Edit
one at a time (with the line above for context, since checkbox text repeats
across tasks), or a portable `perl` range one-liner to tick a whole task.
Stops agents from writing Python scripts to flip a few checkboxes.

## planning 1.23.2 - 2026-09-24

`plan-review` agent's "Test setup preconditions" check now covers full test
lifecycle, not just setup ordering: verifies each new/modified test file is
actually registered with the test runner, and traces interactions with
earlier/later ordered tests, suite cleanup hooks, and repeat-run/`KEEP_*`
flows. Flags a test that's never invoked, or a created resource that
contaminates later specs or survives a declared cleanup path, as CRITICAL.

## statusline 1.0.6 - 2026-09-24

Add an opt-in Codex support path: `scripts/setup-codex.sh` configures Codex's
native footer (`tui.status_line`) to mirror the Claude status line as closely
as Codex's native item set allows — current dir, Git branch, model +
reasoning effort, context use, five-hour use, weekly use. Comment-preserving,
idempotent TOML edit via an embedded Python updater; validates before and
after, atomic replace. README documents the command and Codex's native
rendering limits (no prompt symbol, dirty marker, custom colors, or reset
time).

## global-rules 1.7.1 - 2026-09-21

`block-coauthor` hook now also denies commit/PR commands carrying a claude.ai
session link: the `Claude-Session:` trailer on commits and the bare
`claude.ai/code/session_…` URL on PR descriptions, both injected by Claude
Code's attribution system-reminder even when `attribution` is set to `""` in
settings. The script keeps its name.

## planning 1.23.1 - 2026-09-24

`spawn-session` Step 5 now gates against a real failure: a spawned session
whose prompt opens with "Spawn a new session to..." instead of a direct
imperative, so the recipient tries to spawn yet another session rather than
doing the work. Before invoking the spawn script, the first line of
`$PROMPT_FILE` is checked against known hand-off phrasing ("spawn", "start",
"delegate", "hand off" + "session"/"agent"); a match exits non-zero with a
message telling the author to fix line 1 and rerun. Recovery is a one-line
`Edit` on the already-written prompt file, not a full re-author, since the
expensive part (the task body) is untouched by the check.

## planning 1.23.0 - 2026-09-16

`oversight` skill now closes out an epic instead of leaving it at "every
iteration done" with no next step. Once all iterations in the WBS doc are
`done`, Step 5 routes to a new Step 6: ask whether any housekeeping is needed
before closing out, do it (or spawn a session for it) if so, then append a
final Progress Log entry marking the epic complete and move the WBS doc into
`docs/plans/completed/`, matching the convention plan docs already follow.
Based on feedback from the skill's first successful real-world run.

## global-rules 1.7.0 - 2026-09-16

`setup.sh` now sets `bashOutputMaxChars` to 4000 (the harness floor) in
`~/.claude/settings.json` if the user hasn't already set their own value.
Motivated by a real recurring problem: models running commands like `go test
./... > log; tail -300 log` and dumping hundreds of lines into context
despite CLAUDE.md instructions not to. A `tail`-pattern-matching PreToolUse
hook was considered and rejected — a model can trivially reproduce the same
dump via Python/awk/cat, defeating a command-shape match. `bashOutputMaxChars`
instead caps by actual output size regardless of the command that produced
it: anything over the limit is saved to a file and the model sees a preview
plus the path, which is the workflow the CLAUDE.md rule was already asking
for.

## planning 1.22.1 - 2026-09-16

`codex-handoff.sh` (the `handoff` skill's implementation hand-off) now
launches Codex with `--sandbox danger-full-access --ask-for-approval
on-request` instead of `--sandbox workspace-write --ask-for-approval
never`. Real-world use found workspace-write too restrictive for
implementation sessions: `gofmt`, `golangci-lint`, and `docker` all need to
write to caches/temp dirs outside the repo, and workspace-write blocked
that with no way to grant an exception. `on-request` still lets Codex pause
and ask when it judges an action risky, rather than dropping all gating.
`codex-review-handoff.sh` (the `review-plan` skill's review hand-off) is
unaffected — it stays on `workspace-write`/`never` since review sessions
don't run formatters/linters/containers, only edit the plan file directly.

## planning 1.22.0 - 2026-09-15

Adds `oversight`, a new skill for the epic-scoping phase before any
individual iteration gets planned — the owner's "Over" session, which
previously had no skill and got re-derived from scratch at the start of
every epic. Gathers scope, proposes grouping tickets into iterations only
when planning them one-by-one would produce throwaway stubs discarded
minutes later by a grouped ticket's real implementation, then checks each
proposed iteration against INVEST (not the raw tickets — a ticket can
legitimately fail INVEST alone precisely because it's meant to be
grouped), and pins down an epic-level Definition of Done. Persists to a
new doc type, `docs/plans/wbs-<epic-slug>.md`, distinct from per-iteration
plans — `review-plan`, `handoff`, and `pr`'s "most recent plan" discovery
now all exclude `wbs-*.md` so an epic-scope doc never gets picked up as an
implementation plan to review or hand off. Unlike `plan`/`review-plan`
(which report and stop), `oversight` is meant to be revisited across an
epic's lifetime: its iteration hub can kick off an iteration — which
spawns a new session via the existing `planning:spawn-session` skill,
passing a self-contained prompt (tickets + grouping rationale) so the new
session never has to read the WBS doc itself — mark an iteration done, or
add/re-scope tickets, and resumes from the WBS doc if the session
restarts mid-epic instead of re-deriving everything. Status tracking is
deliberately just two states (`not started`/`done`), not a finer-grained
machine, since nobody would reliably remember to update intermediate
states by hand.

## planning 1.21.1 - 2026-09-15

Trims two unused options from `review-plan`'s prompts, both observed live:
the per-round model question now offers only Opus and Sonnet (Inherit and
Haiku dropped — the owner always makes an explicit choice, never falls
back to a default or picks the mechanical tier for a full round), and the
NEEDS REVISION menu drops "Switch to revdiff" (the owner never switches to
revdiff mid-review — it's still reachable afterward, manually, same as
`/planning:handoff`).

## global-rules 1.6.3 - 2026-09-15

Adds a `block-coauthor` PreToolUse hook that denies any `git commit`/`git
commit --amend` or `gh pr create`/`gh pr edit` whose command string contains
a `Co-Authored-By` line — observed live: Claude Code's own attribution
system-reminder tells the model to add one to every commit and PR, which
conflicts with this repo's "never include a co-authored tag line" rule, and
the model doesn't reliably notice the conflict. Moves the enforcement from
CLAUDE.md prose to this hook, per the repo's own "harness before prose"
principle, and removes the now-redundant prose line.

## planning 1.21.0 - 2026-09-15

`review-plan` can now hand the whole review off to a freshly spawned Codex
CLI session running this same skill there, instead of always reviewing in
the current session — a new Step 0.3 asks "this session or spawn Codex
session," gated on agterm availability same as the existing hand-off
options. The Codex path uses a new `codex-review-handoff.sh` (mirroring
`codex-handoff.sh`, sharing its canned-prompt infrastructure via a new
`build_review_prompt` in `handoff-prompt.sh`) and, per owner's explicit
call, never asks which model to run on — the spawned session always uses
whatever model Codex is configured to use by default.

Separately, removes the two end-of-skill "what's next" menus — `plan` Step
3 and `review-plan` Step 5 — now that `review-plan`, `revdiff:revdiff`, and
`handoff` are all directly invocable, making the menus' options a stale
duplicate of that same surface (the "Implement in a Separate Session"
option, in particular, only ever offered a Claude session, unlike
`handoff`'s Claude/Codex choice). Both skills now just report what they did
and stop. This also means `plan`/`review-plan` no longer offer one-click
"implement in a background subagent" — that capability now lives only in
`handoff`/`spawn-session`, or by asking directly in plain language.

## global-rules 1.6.2 - 2026-09-15

Fixes a stale code comment in `setup.sh` referencing `review-plan`'s
post-review menu, which planning 1.21.0 removes. No behavior change.

## planning 1.20.1 - 2026-09-14

Hardens the runtime-branch instructions in `spawn-session` and `handoff`'s
model-choice step. Observed live: a session picked Codex as the runtime but
was then asked the Claude Inherit/Opus/Sonnet/Haiku question anyway — the
executing model defaulted to the familiar tier list from other planning
skills instead of checking the runtime answer first. Both skills now open
that step with an explicit instruction not to do that.

## planning 1.20.0 - 2026-09-14

Adds Codex CLI as an alternative runtime for `spawn-session` and `handoff`,
so a task or plan can be handed to a fresh `codex` session instead of always
assuming `claude`. Both skills ask which CLI to run before the model
question. `agterm-spawn.sh`'s session-creation logic (workspace resolution,
`agtermctl session new`, flagging) is factored into a new agent-agnostic
`agterm-session-new.sh`, reused by a new `codex-spawn.sh`; the canned
plan-hand-off prompt is factored into a sourced `handoff-prompt.sh`, reused
by a new `codex-handoff.sh` alongside the existing `agterm-handoff.sh`.
Codex has no Opus/Sonnet/Haiku-style model tiers, so its model question is
Inherit-or-free-text instead of a fixed list; its nearest equivalent to
`--permission-mode acceptEdits` is `--sandbox workspace-write
--ask-for-approval never`, confirmed against `codex --help` output rather
than guessed. `plan` and `review-plan` are unchanged — both still hand off
to `claude` only, via the untouched `agterm-handoff.sh` signature.

## planning 1.19.1 - 2026-09-14

Removes the automatic `SendMessage`-back-to-caller machinery from `handoff`
and `spawn-session`: they no longer call `ListAgents` to learn this session's
own name, thread a `CALLER_NAME` through `agterm-handoff.sh`, or splice a
"message this session back when done" paragraph into every spawned prompt.
Owner reported it doesn't work reliably in practice (a multi-session
oversight/plan/impl chain never got the ping back) and that the addressing
step doesn't need to be pre-baked into the skill at all — a spawned session
already has `SendMessage` and `ListAgents` as ordinary tools, so a one-off
callback request can just be written into the prompt by hand at spawn time
if actually needed, no dedicated plumbing required. `agterm-handoff.sh` drops
its `[caller-session-name]` parameter (now just `<plan-file> [model]`); both
skills drop `ListAgents` from `allowed-tools`.

## global-rules 1.6.1 - 2026-09-10

Fixes the Atlassian MCP Hygiene rule's `subagent_type` reference — plugin
agents register under their plugin's name (`global-rules:atlassian-caller`),
not the bare agent name. Confirmed live: `subagent_type: atlassian-caller`
failed with "Agent type not found" until corrected.

## global-rules 1.6.0 - 2026-09-10

Adds a dedicated `atlassian-caller` subagent (Haiku, 40 Atlassian MCP tools,
no Agent tool) and points the Atlassian MCP Hygiene rule at it by name
instead of a generic Agent-tool subagent. Observed live: a Jira subagent
broke its own delegated goal into sub-steps and spawned a second nested
subagent for one of them — the generic subagent type has every tool,
including Agent, so the rule's "don't re-delegate" instruction depended on
each nested agent correctly recognizing it already was that subagent, and
that reasoning isn't reliable. `atlassian-caller`'s `tools:` allowlist
omits Agent entirely (plus `disallowedTools: Agent` as an explicit
backstop), so it's structurally unable to spawn a child regardless of how
it reasons about the task.

## global-rules 1.5.1 - 2026-09-10

Rewrites the two Atlassian MCP bullets from ~180 words to ~80 and adds the
missing scope rule: a delegation covers a whole goal, and a Jira subagent
makes its own calls rather than re-delegating.

Measured from 20 Jira subagent transcripts: a spawn costs ~32K tokens of
context (median; 2 tokens of it uncached — the rest is cache write and read),
for a median of 6 Jira calls. That price is worth paying once per goal and not
once per call. Reusing a live subagent via `SendMessage` was considered and
dropped: by the time the next Jira request arrives the prompt cache has
usually expired, and the agent's grown context then costs more to resume than
a fresh spawn.

## global-rules 1.5.0 - 2026-09-10

Replaces 1.4.0's wakeup-discipline prose with a `permissions.deny` entry for
`ScheduleWakeup`, added to `~/.claude/settings.json` by the setup hook. Four
bullets carried through every context of every session, still relying on the
model to follow them, to prevent something the permission layer refuses
outright for free. Side effect worth knowing: a bare `/loop` with no interval
now runs once rather than pacing itself — `/loop <interval>` is unaffected.

Also adds an "Enforcement: Harness Before Prose" section to the repo's own
CLAUDE.md. The 1.4.0 rule got written because the proposed wording was
reviewed and improved without anyone asking whether it should be a rule at
all; the section says to check for a mechanism — a deny rule, a `disable*`
setting, a hook, an agent `tools:` list — before adding prose, including when
the user is the one proposing it.

## global-rules 1.4.0 - 2026-09-09

New "Background Work: Wakeup Discipline" section. Sessions were calling
`ScheduleWakeup` on 120–150s intervals to "check back" on spawned subagents
— work the harness already re-invokes them for the instant it finishes — so
the wakeups fired after the work was done, each one a fresh turn repeating
the same prompt. Two turns in one observed session went to re-deriving that
the task was already handled instead of stopping the loop. The rule keeps
the distinction that matters: in a dynamic /loop a wakeup is what keeps the
loop alive, so it isn't optional — it just has to be a long fallback rather
than a poll, and `stop: true` the moment a fire shows the task is complete.

## planning 1.19.0 - 2026-09-10

`plan` now reads, in full, every existing file a task lists under Create or
Modify before writing that task — plus the sibling test files any new test code
will reuse. Step 0's 5-file discovery cap is explicitly scoped to discovery and
no longer caps this pass. Test helpers and fixtures are called out as
dependencies whose real signatures have to be right, and Step 2.5's
type-consistency check now compares names against those real files rather than
only against other tasks.

`review-plan` gains a Haiku mechanical pre-pass (Step 0.5) that clears
grep-provable findings before the first reasoned round. It is deliberately not
numbered as a round: it does not consume the 1–3 budget and its fixes are not
passed into round 1 as a fix list, because `plan-review.md`'s step 8 would then
narrow round 1 against a plan nothing had reasoned over. The agent gained a
matching `Mode: mechanical` that skips its four expensive verification steps and
emits no verdict.

`review-plan`'s fix step now verifies its own REASONED fixes against the source
they make claims about, instead of leaving that to the next round.

Measured from 111 review transcripts across 44 plans (see
`docs/analysis/2026-09-10-plan-review-loop-measurement.md`, and
`docs/analysis/measure-review-rounds.py` to re-run it): 69% of round-1 critical
findings cite a concrete `file:line` in the repo, and 24% are wrong helper
signatures, fixtures, or stale assertions in files the plan itself listed as
Modify. Peak review context is 108K median, of which only 28K is the prompt plus
the plan — the other 79K is codebase reading the planner could have done first.
116 of 296 round-1 findings were grep-provable. Of 569 fixes the reviewer later
judged, 45 were incomplete and 26 had introduced a new problem.

The round limit stays at 3 and the reviewer's severity language is untouched: at
a median of 2 criticals per round-1 review, with a fifth finding none, it was
measured as well-calibrated. Capping the findings list would have lost real
findings without touching the cause.

## planning 1.18.2 - 2026-09-09

`spawn-session` and `handoff` rewritten as instructions rather than prose:
the narrative intros, the re-explanations of rationale, and the redundant
`AGTERM_ENABLED` pre-check (both scripts already check it themselves) are
gone, the 15-line AskUserQuestion JSON blocks are compact option lists, and
the positional-argument rules are shown as example command lines instead of
described. `spawn-session` also gains `AskUserQuestion` in `allowed-tools`,
which Step 3 needed but the frontmatter never listed. Both files had a
`ListAgents` example that wrapped the session name in backticks the real
output doesn't have — following it literally yielded a name with backticks
in it.

## global-rules 1.3.0 - 2026-09-09

Three additions: Jira MCP delegation now has no carve-out for single calls,
skills should be re-invoked via the Skill tool rather than replayed from
memory on repeat use, and the "no co-authored-by tag lines" rule is
reinstated under Git Hygiene (the `attribution.commit`/`attribution.pr`
settings.json fields it was dropped for stopped suppressing the tag line).

## planning 1.18.1 - 2026-09-09

`spawn-session`'s report-back callback note is worded as conditional ("if
asked at any point to return a result there") — fine for most tasks, but a
task the user explicitly wants reported back (e.g. "make it return the
result") never got a follow-up ask, so the spawned session answered in its
own terminal and stopped without ever calling `SendMessage` (confirmed live:
two Haiku *and* two Sonnet spawns both answered locally and went idle).
Step 1 now says to state the report-back requirement unconditionally in the
task prompt itself when the request calls for it, instead of relying on the
generic callback note alone.

## planning 1.18.0 - 2026-09-08

Every agterm hand-off (`spawn-session`, `handoff`, and `plan`'s/`review-plan`'s
"Implement in a Separate Session") now asks which model the new session
should run on (Inherit/Opus/Sonnet/Haiku), matching the question the
background-subagent path already asked. Passed through as `claude --model
<alias>`: `agterm-handoff.sh` gained an optional `[model]` parameter that
appends `--model` alongside its existing `--permission-mode acceptEdits`;
`spawn-session` passes it straight to `agterm-spawn.sh`'s existing
`[claude-flags]` parameter.

## planning 1.17.0 - 2026-09-08

Implementation hand-offs to a fresh agterm session (`handoff`, and `plan`'s/
`review-plan`'s "Implement in a Separate Session") now launch with
`--permission-mode acceptEdits`, so the new session starts implementing right
away instead of asking permission for every edit. `agterm-spawn.sh` gained an
optional `[claude-flags]` parameter to carry this; `spawn-session` (arbitrary,
possibly non-implementation tasks) is unaffected and still starts in the
default permission mode.

## planning 1.16.3 - 2026-09-08

`plan-review` findings could describe a problem category ("needs more test
coverage", "reconcile the docs") without stating the actual fix, forcing
whoever applies the fix to invent specifics — and an invented fix is exactly
what produced the next round's finding on the same issue. Added an explicit
requirement that every finding's "how to fix it" be the literal concrete
change, plus a note keeping specific problems out of the Summary paragraph
and into their own prescriptive findings.

## planning 1.16.2 - 2026-09-08

Fixed `review-plan` skipping straight from "review agent finished" to applying
fixes without ever printing the round's report — the "print the report first"
rule existed but read as a should-statement buried in prose, so it got skipped
once findings were in hand. Reworded Step 2 as an explicit ordering constraint:
no Grep/Read/Edit/fix action of any kind, including the all-MECHANICAL fast
path, may happen before the report is posted.

## planning 1.16.1 - 2026-09-08

Fixed 1.16.0's comment-hygiene check turning into a narrated, separately-announced
Bash step every time it ran — once per plan, then again every single `review-plan`
round — because it was the only Step 2.5 item phrased as a command ("grep the
plan's code blocks") instead of a reasoning check like the other seven. Reworded
`plan`'s Step 2.5 so all 8 checks are explicit internal reasoning, not an announced
procedure, and `review-plan`'s fix step to re-run only the specific finding's own
`verify:` command silently instead of a broader "sanity check" rescan of the whole
plan.

## planning 1.16.0 - 2026-09-08

`plan`'s Step 2.5 self-review now runs the same deep verification the separate
`plan-review` agent applies — error/status tracing, test-precondition ordering,
multi-phase state, and a new comment-hygiene grep — so the author catches these
before the reviewer ever sees the plan. Step 0 discovery and the dependency-contract
check gain a self-declared "deep-discovery mode" for multi-plan/large-feature work,
dropping the flat 5-file / 3-6-function caps when the plan says so.

`review-plan`'s fix step now scans the whole plan for every instance of a
reviewer-flagged pattern instead of fixing one occurrence per round, and no longer
resolves "needs more explanation" findings by pointing back to a spec or ticket.

Both `plan` and `plan-review` gained an explicit code-comment-content rule: no
ticket IDs, links, PR numbers, commit SHAs, `(Slice N)` markers, or
docs/specs/Technical-Details pointers in example code — comments must be
self-contained. Plan-level cross-references are unaffected.

The plan template drops the `Solution Overview` section — it duplicated the
top-level `Architecture` field and `Context` section.

## planning 1.15.0 - 2026-09-04

`spawn-session` and `handoff` now unconditionally tell every
spawned/handed-off session this session's own cross-session address (via
`ListAgents`) and how to send a result back with `SendMessage` — so a
result can still be routed back even if you only decide you want one
after the session is already running, not just when you say so up front.
`agterm-handoff.sh` gained an optional second `caller-session-name`
argument; omitted (as `plan`/`review-plan` still call it), the prompt is
unchanged. Both skills' `allowed-tools` gained `ListAgents`.

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
