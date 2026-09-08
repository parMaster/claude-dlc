# Fix Planning-Skill Review-Loop Waste and Plan Verbosity

**Goal:** Stop `planning:review-plan` from routinely burning 3 full rounds on plans that `planning:plan` should have gotten right the first time, and stop plans/code comments from accumulating prose and reference-garbage on every review round.

**Architecture:** Move the separate `plan-review` agent's deep verification (dependency behavior, error tracing, test preconditions, multi-phase state) into `planning:plan`'s own self-review step, so the author catches it before the reviewer ever sees the plan. Make the reviewer's fix step sweep whole patterns instead of one flagged line at a time. Trim one genuinely redundant template section. Add an explicit, grep-verifiable rule against reference-garbage in code comments, enforced by both skills.

**Tech Stack:** Markdown skill/agent instruction files only — no application code, no runtime.

---

## Context (from discovery)
- files involved: `plugins/planning/skills/plan/SKILL.md`, `plugins/planning/skills/review-plan/SKILL.md`, `plugins/planning/agents/plan-review.md`, `plugins/planning/.claude-plugin/plugin.json` (currently `1.15.0`), `CHANGELOG.md`
- confirmed via grep: no *instruction* file outside `plan/SKILL.md` references the plan template's `Solution Overview`, `Development Approach`, or `Technical Details` section names. 7 completed plan documents under `docs/plans/completed/` carry a `## Solution Overview` heading — harmless historical artifacts written under the old template, not something this change touches. One active (non-completed) plan, `docs/plans/2026-08-28-block-search-dump-hook.md`, also carries the heading — also untouched; this plan only changes the template new plans are created from, not plans already written. `README.md`'s pipeline diagram only says "create plan + dependency check + self-review" and survives unmodified, but the `plan`/`review-plan` table rows describe finer-grained behavior and need updating (Task 10)
- confirmed via grep: `Verified Dependency Behaviors` is referenced by both `plan/SKILL.md` (writer) and `plan-review.md` (reviewer) — untouched by this plan
- confirmed: the `planning:plan-review` subagent type this session resolves lives in the installed plugin cache (`~/.claude/plugins/cache/parmaster-claude-dlc/planning/1.14.0/...`), a separate versioned copy already stale relative to this repo's `1.15.0` `plugin.json` — a live agent spawn in this session cannot exercise this plan's edits (see Task 9)
- cross-checked against upstream `cc-thingz` (`../../cc-thingz` sibling repo, pulled to `92e1d84`): it has no equivalent for any of these four fixes — its `plan-review` agent is lighter than ours (no dependency/error/precondition verification at all) and its template has the same section overlap. Nothing to port; this is original work.
- deep-mode trigger decision (asked and answered): self-declared only — either the user says this plan is part of a larger multi-plan effort, or `docs/plans/` (including `completed/`) already holds a sibling plan for the same feature. No auto-detection heuristic. Checked twice: once at Step 0 (only the sibling-plan-on-disk condition can fire that early — a user rarely announces "this is part of a bigger effort" before being asked anything) and again after Step 1's scope/constraints answers.

This plan introduces no new code dependencies — skip "Verified Dependency Behaviors".

## Development Approach
- testing approach: N/A in the code-test sense (no application code changes). Validation is Task 9 below: dry-run the new instructions against existing completed plans, and hand-apply the plan-review checklist against this plan document (a live agent spawn in this session would resolve the installed, pre-edit plugin copy, not these edits — see Task 9).
- one section edited at a time, re-read the whole file after each edit to catch cross-references broken by earlier edits in the same file
- **CRITICAL: bump `plugins/planning/.claude-plugin/plugin.json` version and add a `CHANGELOG.md` entry in the same commit** — per repo convention, every content change to a plugin requires this
- **CRITICAL: single summary commit at the end** — no per-task commits

## Technical Details

Four independent fixes land in this plan, each scoped to specific line ranges in specific files. They don't depend on each other — order below is just file-locality (all `plan/SKILL.md` edits first, then `review-plan/SKILL.md`, then `plan-review.md`).

**Why only `Solution Overview` gets removed, not `Development Approach`:** `Development Approach` is an operational checklist (each bullet is an independent, actionable rule — "single summary commit," "run golangci-lint before committing") — it's not prose restating the plan's intent, so merging it away would lose independently-checkable rules. `Solution Overview` has three bullets: "high-level approach and architecture chosen" and "how it fits into the existing system" duplicate the top-level `**Architecture:**` field and `## Context`, but its third bullet — "key design decisions and rationale" — has no other home in the template (it's also what `plan-review.md`'s "Decision conflict" check reads plans for). Task 5 below folds that bullet into `## Technical Details` before deleting the section, so the rationale content survives the merge; only the duplicated two-thirds actually goes away.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: `plan/SKILL.md` — add deep-discovery mode to Step 0

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] In Step 0, immediately after the line `2. **Gather relevant context quickly** — use direct tool calls (Read, Glob, Grep), NOT an Agent. Keep discovery under 30 seconds:`, change it to:

```markdown
2. **Gather relevant context quickly** — use direct tool calls (Read, Glob, Grep), NOT an Agent. Keep discovery under 30 seconds in the default mode; deep-discovery mode below lifts both this budget and the file cap.
```

- [ ] Immediately after the line `**CRITICAL: do NOT launch an Agent or read more than 5 files in this step.**` (and before the "for Go repos" bullet), insert:

```markdown
   **Deep-discovery mode** — the 5-file cap and 30-second budget above are the default, not a hard ceiling. Switch to deep mode when any of these become true:
   - `docs/plans/` (including `completed/`) already contains a sibling plan for the same feature (checkable right here at Step 0)
   - the user states, at any point, that this plan is part of a larger, multi-plan effort (a feature broken into slices, a WBS/parent doc)
   - Step 1's scope/constraints answers reveal multi-plan or large-feature scope that wasn't apparent yet at Step 0

   The first condition can be checked now. The other two usually can't be known until after Step 1 — when either fires there, go back and run the deep pass below before Step 2, rather than proceeding with shallow discovery just because the trigger came late.

   In deep mode: read as many files as it takes to understand the actual call chains the plan's tasks depend on — no fixed file count, no 30-second budget. This is still a discovery pass, not a full audit, so keep it targeted to what the plan's tasks will actually call or touch.
```

- [ ] Re-read Step 0 top to bottom after both inserts — confirm the 30-second line and the deep-discovery paragraph agree (neither claims a bare, unconditional 30-second/5-file budget anymore)

### Task 2: `plan/SKILL.md` — widen the dependency-contract check in deep mode

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] In the "Dependency contract check" section, immediately after the line `This is a focused pass — typically 3–6 functions, not broad exploration. Record findings in the "Verified Dependency Behaviors" section of the plan.`, insert:

```markdown

In deep-discovery mode (Step 0), widen this to every dependency any task actually calls — not a fixed 3–6 count. A function reused across several tasks needs verifying once; a wrong assumption about it otherwise silently reproduces itself into every task that calls it.
```

### Task 3: `plan/SKILL.md` — add "Code comment rules" subsection

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] Immediately after the `### No placeholders` section's last bullet (`- References to types, functions, or methods not defined in any task`) and before `## Step 2.5: Self-review`, insert a new subsection:

```markdown
### Code comment rules

Comments inside example code shown in tasks must be self-contained — never a pointer to something else:

- No ticket IDs, no links to Confluence/Jira/PRs, no commit SHAs
- No `(Slice N)` markers or "see ... in Technical Details" pointers back into this plan
- No `docs/specs/...` references — inline the one clause of context a reader needs, don't point at the spec
- At most 1-2 lines; if it needs more than that to justify itself, the content belongs in this plan's prose, not in a code comment
- State only the "why" a future reader needs at the call site to not re-break the thing — never restate what the code obviously does

This applies to comments in the code itself. Plan-level cross-references (a WBS/slice note, "this plan supersedes the approach in `<prior-plan>`") stay in the plan's own prose sections — this rule doesn't touch those.
```

### Task 4: `plan/SKILL.md` — fold the reviewer's deep checks into Step 2.5 self-review

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] In `## Step 2.5: Self-review`, after existing item `4. **Dependency behavior check**...`, add items 5-8:

```markdown
5. **Error/status tracing** — skip if the plan asserts no error outcomes or status codes. Otherwise, for every one asserted, trace it end-to-end: where the sentinel/error originates, every `%w` re-wrap on the way, and what the handler that receives it actually returns. Fix any task whose expected outcome doesn't match what the trace shows.
6. **Test setup preconditions** — skip if the plan has no test setup steps. Otherwise walk each task's test setup in execution order against the API's actual state-transition/creation-order rules. Fix any step that would be rejected because it violates an ordering requirement.
7. **Multi-phase state** — skip if the plan touches no migration, workflow, or staged operation. Otherwise check what earlier phases actually leave in place before a later task asserts on that state. Fix any assumption of absent state that an earlier phase already establishes.
8. **Comment hygiene** — grep the plan's code blocks for ticket IDs (`[A-Z]{2,}-[0-9]+`), links (`https?://`), commit SHAs (`\b[0-9a-f]{7,40}\b`), `Slice [0-9A-Z]`, `see .* Technical Details`, and `docs/specs`. Skip a match that's actually a standard name, not a reference — `UTF-8`, `SHA-256`, `RFC-7231`, `AES-256`, `ISO-8601` and the like aren't ticket IDs. Rewrite any real hit per "Code comment rules" above.
```

- [ ] Immediately after the existing line `Fix issues inline. No need to re-review after fixing.`, add:

```markdown

These checks mirror what the separate `plan-review` agent verifies. Catching them here means fewer review rounds, not weaker review — the reviewer still runs the same checklist independently.
```

### Task 5: `plan/SKILL.md` — remove the redundant `Solution Overview` section

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] First, fold the one bullet from `Solution Overview` that has no other home into `## Technical Details`. Change:

  ```markdown
  ## Technical Details
  - data structures and changes
  - parameters and formats
  - processing flow
  ```

  to:

  ```markdown
  ## Technical Details
  - key design decisions and rationale
  - data structures and changes
  - parameters and formats
  - processing flow
  ```

- [ ] Then delete the `Solution Overview` block entirely (it sits between `## Development Approach` and `## Technical Details`):

```markdown
## Solution Overview
- high-level approach and architecture chosen
- key design decisions and rationale
- how it fits into the existing system

```

  (`## Development Approach`'s last bullet and `## Technical Details`'s heading become adjacent after deletion. The other two bullets — "high-level approach and architecture chosen" and "how it fits into the existing system" — are dropped, not moved: they duplicate the top-level `**Architecture:**` field and `## Context`.)

### Task 6: `review-plan/SKILL.md` — sweep repeated patterns, not one instance per round

**Files:**
- Modify: `plugins/planning/skills/review-plan/SKILL.md`

- [ ] In Step 3, "Fix and re-review", replace item 1:

  Old:
  ```markdown
  1. Apply fixes to the plan file based on the findings (Edit tool). Keep a running list of what you changed, phrased as one line per finding: `[finding] → [what you did]`.
  ```

  New:
  ```markdown
  1. Apply fixes to the plan file based on the findings (Edit tool). For any finding that reveals a pattern repeated across multiple tasks (the same wrong assumption about a function's behavior, the same stale reference, reused in several places) — grep/scan the whole plan for every other instance of that pattern and fix all of them now, not just the line(s) the reviewer flagged. When a finding says code needs more explanation, inline it per `planning:plan`'s "Code comment rules" — never resolve it by adding a comment that points back to Technical Details, a spec doc, or a ticket. Keep a running list of what you changed, phrased as one line per finding: `[finding] → [what you did]`.
  ```

### Task 7: `plan-review.md` — add a Comment Hygiene checklist item

**Files:**
- Modify: `plugins/planning/agents/plan-review.md`

- [ ] In the "Review checklist" section, after `**Testing (Critical)**` and its bullets, before `**Task Granularity (Important)**`, insert:

```markdown
**Comment Hygiene (Important)**
- Do code comments shown in tasks avoid ticket IDs, Confluence/Jira links, PR numbers, commit SHAs, `(Slice N)` markers, and "see ... in Technical Details"/`docs/specs` pointers? These are MECHANICAL findings — grep for the pattern and cite the match as `verify:`. Skip a match that's actually a standard name, not a reference — `UTF-8`, `SHA-256`, `RFC-7231`, `AES-256`, `ISO-8601` and the like aren't ticket IDs.
```

### Task 8: Version bump and changelog

**Files:**
- Modify: `plugins/planning/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

- [ ] In `plugins/planning/.claude-plugin/plugin.json`, change `"version": "1.15.0"` to `"version": "1.16.0"`
- [ ] In `CHANGELOG.md`, insert a new section at the top of the file's version history (above the current `## planning 1.15.0 - 2026-09-04` entry):

```markdown
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
```

- [ ] Unrelated drift noticed while in this file: `CLAUDE.md`'s "Changelog" rule documents the heading format as `## plugin-name vX.Y.Z - YYYY-MM-DD`. The actual history is split: 56 of 66 existing entries use `vX.Y.Z` (matching the doc), but the last 8 — everything since `2026-08-31`, including the entry this task adds right after `## planning 1.15.0 - 2026-09-04` — write `X.Y.Z` with no `v`. This isn't "the doc is the lone holdout"; it's a real, recent convention change that the doc never caught up to. Since the new entry sits directly beside 8 no-`v` neighbors, match them rather than the older majority: update `CLAUDE.md`'s Conventions section from `vX.Y.Z` to `X.Y.Z`, and leave the 56 historical entries as they are — this documents current practice, it doesn't retroactively rewrite old entries.

  Run: `grep -n "vX.Y.Z" CLAUDE.md`
  Expected before fix: 1 match. After: 0 matches.

### Task 9: Validate the instruction changes

**Files:**
- None (read-only verification)

- [ ] Confirm no stale reference to the removed section remains:

  Run: `grep -rn "Solution Overview" plugins/planning/`
  Expected: no matches

- [ ] One assertion per edit made in Tasks 1-8, confirming each landed exactly once:

  Run: `grep -c "Deep-discovery mode" plugins/planning/skills/plan/SKILL.md` — Expected: 1
  Run: `grep -c "### Code comment rules" plugins/planning/skills/plan/SKILL.md` — Expected: 1
  Run: `grep -c "^5\. \*\*Error/status tracing\*\*" plugins/planning/skills/plan/SKILL.md` — Expected: 1
  Run: `grep -c "key design decisions and rationale" plugins/planning/skills/plan/SKILL.md` — Expected: 1 (moved into Technical Details, not duplicated)
  Run: `grep -c "grep/scan the whole plan for every other instance" plugins/planning/skills/review-plan/SKILL.md` — Expected: 1
  Run: `grep -c "Comment Hygiene (Important)" plugins/planning/agents/plan-review.md` — Expected: 1
  Run: `grep -c '"version": "1.16.0"' plugins/planning/.claude-plugin/plugin.json` — Expected: 1
  Run: `grep -c "^## planning 1.16.0" CHANGELOG.md` — Expected: 1

- [ ] Confirm the new deep-mode and comment-hygiene text reads correctly end-to-end — re-read the full `plugins/planning/skills/plan/SKILL.md` file top to bottom after all edits and check Step 0 → Dependency contract check → Plan structure → No placeholders → Code comment rules → Step 2.5 flow in order with no dangling reference to something deleted or renamed.
- [ ] Pick two existing completed plans — `docs/plans/completed/2026-08-31-agterm-spawn-session.md` and `docs/plans/completed/2026-09-04-spawn-handoff-callback.md` — and run the Task 4 comment-hygiene grep pattern against them as a smoke test that the command itself works:

  Run: `grep -nE '[A-Z]{2,}-[0-9]+|https?://|\b[0-9a-f]{7,40}\b|Slice [0-9A-Z]|docs/specs|see .* Technical Details' docs/plans/completed/2026-08-31-agterm-spawn-session.md docs/plans/completed/2026-09-04-spawn-handoff-callback.md`
  Expected: command runs without error (matches, if any, are pre-existing-plan text predating this rule — not a failure, just confirms the pattern is syntactically valid and greppable)

- [ ] Hand-apply the new Step 2.5 items 5-8 and the `plan-review.md` Comment Hygiene item against this plan document (`docs/plans/2026-09-08-plan-review-loop-quality.md`) yourself — this plan has no error outcomes, test setup, or multi-phase state, so items 5-7 skip per their new skip clauses; item 8's grep (previous bullet) confirms comment hygiene. Confirm each instruction told you unambiguously what to do and what "done" looks like.

  A live agent spawn is deliberately *not* used for this check: this session's `planning:plan-review` subagent type resolves from the installed plugin cache, a separate versioned copy already stale relative to this repo (confirmed in Context above) — it would exercise the pre-edit checklist, not these edits. See Post-Completion for how to actually run a live check against the edited copy.

### Task 10: Wrap up and commit

**Files:**
- None beyond what Task 8 already modified

- [ ] Update `README.md`'s `plan` row (currently line 81) — after "Offers auto-review, revdiff annotation, hand off to a background subagent, or hand off to a fresh agterm session at the end." append: "Self-review also traces error/status handling, walks test preconditions, and checks multi-phase state — the same depth the separate `review-plan` reviewer applies — and enforces a code-comment rule (no ticket IDs, links, PR numbers, commit SHAs, `(Slice N)` markers, or spec/doc pointers in example code). Discovery and dependency verification widen in a self-declared deep-discovery mode for multi-plan/large-feature work."
- [ ] Update `README.md`'s `review-plan` row (currently line 82) — after "Every finding is tagged MECHANICAL (backed by a `verify:` command) or REASONED (needs judgment);" insert: "a finding that's a pattern repeated across multiple tasks gets every instance fixed in one pass, not just the flagged line, and a "needs more explanation" finding gets inlined rather than resolved with a pointer back to a spec or ticket;"

  Run: `grep -n "deep-discovery\|Code comment rules\|every instance" README.md`
  Expected: ≥1 match

- [ ] Run the project's test suite before committing: `bash tests/run.sh` — Expected: 0 failed (no scripts changed in this plan, so this should pass trivially; it's here because the global rule requires it regardless)
- [ ] Move this plan to `docs/plans/completed/`: `mkdir -p docs/plans/completed && mv docs/plans/2026-09-08-plan-review-loop-quality.md docs/plans/completed/`
- [ ] Single summary commit: all four fixes + version bump + changelog + README + CLAUDE.md + plan move in one commit
- [ ] Open draft PR — invoke `planning:pr` (optional; ask the user first since this is a meta/tooling change, not application code)

## Post-Completion
*Items requiring manual intervention or external systems*

- The next real plan written with `planning:plan` in an actual multi-plan work-repo feature is the real test of whether review rounds actually drop — this can't be verified synthetically here since the failure mode (bloat compounding across review rounds) only shows up on a large, multi-task, multi-round plan in a codebase this repo doesn't have.
- To actually exercise the edited `plan-review` agent (not the installed, stale copy — see Task 9), run `claude --plugin-dir plugins/planning` in a fresh session after this commit lands, and spawn `planning:plan-review` there against any plan file. This is the only way to verify the live agent behavior in-session; nothing in this plan's own tasks can do it.
