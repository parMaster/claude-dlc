---
name: plan
description: Create a structured implementation plan in docs/plans/. Activates on "make a plan", "create a plan", "plan this feature", "write a plan", or when the user wants to document implementation steps before coding.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Skill, AskUserQuestion, EnterPlanMode
---

# Implementation Plan Creation

Create a plan in `docs/plans/yyyy-mm-dd-<task-name>.md` that says **what** the change is, **why**, which **decisions** were made, what could **trip up** the implementer, and how we'll **know it's done**. It does not say what code to write — the implementer reads the codebase and picks files, code and test names itself; the compiler, tests and linter keep that honest.

The reader is the user, who reads the whole plan and thinks it through — up to about ten minutes — and an implementer (often a fresh session) who is skilled and can explore the code but wasn't in this conversation. A small bug fix may need 20 lines; if a plan grows past ~150, the change is probably too big for one plan — say so and suggest splitting it.

## Step 0: Parse intent and gather context

1. **Classify the kind of change** from the user's words: bug fix, refactor, feature, or migration. It sets how the Definition of Done handles tests (see Step 2).

2. **Gather context** with direct tool calls (Read, Glob, Grep), not an Agent:
   - feature: glob the feature area, read the 1–3 most relevant files, `ls` key dirs
   - bug fix: grep for the error or function named, read the files involved, `git log --oneline -5`
   - refactor/migration: read the key files of the area, grep for what imports them
   - unclear: `git status`, `git log --oneline -5`, README.md / CLAUDE.md

   Keep it to about 5 files unless `docs/plans/` (or `completed/`) already holds a sibling plan for this feature, or the user says this is one slice of a bigger effort — then read as much as it takes to understand the call chains the change depends on.

3. **Resolve the real test command** — `Makefile` `test` target, else the CI workflow's test step, else the language default (`go test ./...`). The plan's Wrap-up uses it.

4. Summarize findings in 3–5 bullets.

## Step 1: Ask focused questions

Show the context summary, then ask **one at a time** (a separate AskUserQuestion call each), skipping any the conversation already answered:

1. **Goal** — multiple choice, suggested answer from the discovered intent
2. **Scope** — which components are involved; free text if discovery found only one
3. **Constraints** — requirements, limits, things that must not change

Derive the plan's title (its H1 and the `<task-name>` in the filename) from the Goal; don't ask for it.

## Step 1.5: Explore approaches

Skip if the approach is obvious, the user already chose it, or it's a clear bug fix.

Otherwise propose 2–3 approaches conversationally, recommended one first, each with how it works, pros, cons. Ask the user to pick with AskUserQuestion. The choice and the dropped alternatives go into **Decisions**.

## Step 2: Investigate, then write the plan

### Investigate what the change relies on

Read the code the change will call or build on — function bodies, not just names. You're looking for anything a fresh implementer would get wrong:

- behavior that differs from what the name suggests (a `GrantAccess` that grants USAGE but not CREATE)
- errors that get re-wrapped or mapped to an unexpected status on the way out
- state an earlier phase or migration already leaves in place
- existing tests that pin behavior the change alters
- ordering rules in an API or test setup

Each finding goes into **Traps**, stated as a fact with its location (`path/to/file.go` + function name). Findings that shaped the approach go into **Decisions**. Nothing here turns into code in the plan.

### Backlog items

If `docs/backlog/` exists, match its items' `where` paths against the area the plan touches. For each match marked `worth: yes`, ask with AskUserQuestion whether to fold it in. A folded item gets its own DoD line, including `git rm docs/backlog/<slug>.md` in the final commit, per `/backlog`'s lifecycle. Items marked `later` or `no` are context, not questions.

### Tests by kind of change

The test approach lives in the DoD, not in a separate question:

- **bug fix** — first DoD item: a test reproduces the bug and fails before the fix; it passes after.
- **refactor** — first DoD item: the behavior being refactored is pinned by tests (unit, integration, whatever fits) before the change; the same tests pass unchanged after.
- **feature / migration** — DoD lists what must be proven; the implementer picks the order and the test shape.

### Plan template

```markdown
# [Title]

**Goal:** [one sentence]

**Kind of change:** [bug fix / refactor / feature / migration]

## Intent

[What and why, a short paragraph. What's wrong or missing today, what changes.]

## Decisions

- **[decision]** — [why; which alternatives were dropped and why]

## Constraints / out of scope

- [what must not break, what this plan deliberately doesn't do]

## Traps

*Omit the section if there are none.*

- [non-obvious fact about the code this change relies on] (`path/to/file`, `FuncName`)

## Definition of Done

- [ ] [checkable outcome] — proof: [test that shows it / command + expected output / what to observe]

## Work order

*Omit unless order matters. One line per step.*

1. [step]

## Wrap-up

- [ ] full test suite passes: `<command from Step 0>`
- [ ] linter passes: `<project linter>`
- [ ] README.md / CLAUDE.md updated if behavior or patterns changed
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [ ] single commit: all changes + plan move

## Post-Completion

*Omit if empty. Manual steps or external systems.*
```

### Writing rules

- **No code.** No task-by-task code blocks, no test function bodies, no line numbers. One exception: a short snippet for a single genuinely tricky item (a query, a migration step, a regex) where prose would be ambiguous. A new interface, public signature or endpoint shape that other code will depend on is a decision — state it in Decisions; a signature line is fine, bodies still aren't.
- **DoD items are outcomes, not steps.** "Expired tokens get 401" is a DoD item; "add a check in middleware.go" is not. Each item names its proof.
- **Name files and functions only where they carry meaning** — in Traps, or where a decision is about a specific place. Not as a to-do list.
- **No history lessons** — don't narrate how the plan evolved or reference older plans' line numbers. If a prior decision is being reversed, one line in Decisions says so.
- **Draw what moves.** When the change alters a flow, sequence, state machine or the shape of something (who calls whom, what runs before what), show it as a small plain-text diagram — boxes and arrows, never mermaid, since plans are read in the terminal — as before → after when an existing flow changes. Use a table where the content is a grid: options vs. trade-offs, inputs vs. outcomes, a mapping. Prose carries the why around them and doesn't redescribe what the picture shows.
- **Progress**: the implementer ticks DoD and Wrap-up boxes as they're done, adds found work as new DoD items prefixed ➕, and marks blockers ⚠️.

## Step 2.5: Self-review

Check silently; mention only what you fixed.

1. Every point in Intent has at least one DoD item that proves it.
2. Every DoD item says how it's proven.
3. Every Trap was checked against the source, not inferred from a name.
4. Bug fix / refactor plans start the DoD with the test-first item.
5. No code beyond the snippet and signature exceptions; nothing padded to look thorough. Past ~150 lines, suggest splitting instead of trimming.

These are the same things `plan-review` checks, so a clean self-review usually means a short review.

## Step 3: Report completion

Tell the user: "created plan: `docs/plans/yyyy-mm-dd-<task-name>.md`" and stop. Don't ask what's next — the user calls `/planning:review-plan`, `revdiff:revdiff`, `/planning:handoff`, or starts implementing when ready.

## Key principles

- **Intent over instructions** — say what and why; leave how to the implementer
- **One question at a time**, multiple choice where possible
- **Lead with a recommendation** — have an opinion, let the user decide
- **YAGNI** — minimal scope, nothing "just in case"
- **Single summary commit** — one commit at the end covers everything
