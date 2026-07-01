---
name: review-plan
description: Review an implementation plan for completeness, correctness, over-engineering, and test coverage. Iterates review rounds until no critical issues remain or round limit hit. Activates on "review plan", "check the plan", "critique this plan", or as an optional step after planning:plan.
allowed-tools: Read, Glob, Grep, Bash, Agent, AskUserQuestion, Edit, Skill
---

# Plan Review

Iterative structured critique of an implementation plan. A read-only review agent finds issues; the main session presents them and applies fixes on approval.

## Step 0: Find the plan file

1. If `$ARGUMENTS` contains a file path, use it
2. Otherwise check `docs/plans/` — most recently modified `.md` (excluding `completed/`)
3. If multiple plans exist and it's unclear which, list them and ask

## Step 1: Spawn review agent

Track the current round (start at 1, max 3). Use the Agent tool with `subagent_type: general-purpose` and the prompt below. Replace `PLAN_FILE` with the actual path and `ROUND` with the current round number.

---
You are reviewing an implementation plan before implementation begins. Find real problems — do not nitpick style.

READ-ONLY: Do not create, edit, or delete any files.

Plan file: PLAN_FILE  
Review round: ROUND

**Go symbol lookup rule — CRITICAL:**
NEVER use grep, rg, or find to locate Go symbols (functions, types, methods, interfaces).
ALWAYS use gosymdb skills instead:
- `gosymdb:sym --auto-reindex` — find where a symbol is defined
- `gosymdb:trace --auto-reindex` — full profile: definition + callers + callees
These are available as Skill tool calls. Grep for Go symbols will be wrong or incomplete — use gosymdb.

Steps:
1. Read the plan file fully
2. Read `CLAUDE.md` for project conventions
3. Identify the source files and packages the plan touches — read 2–4 of the most relevant ones to understand current patterns and interfaces
4. **Behavior verification (not just existence):** For each external function, method, or API the plan depends on — things it will CALL, not things it will CREATE — use `gosymdb:sym --auto-reindex` to locate it, then READ its body. Verify the plan's claims match what the function actually does: privileges granted, errors returned and how they're wrapped, side effects, state left behind. Flag as CRITICAL any gap between what the plan claims and what the body does.
5. **Error/status tracing:** For every asserted error outcome or HTTP status code in the plan, trace it end-to-end: follow the sentinel or error from where it originates, through each `%w` re-wrap, to the handler that maps it to a response. Flag as CRITICAL if the plan's expected outcome doesn't match what the handler actually returns.
6. **Test setup preconditions:** Walk the test setup steps in execution order. For each step, check it against the API's enforced preconditions — state-transition rules, creation-order constraints, required prior state. Flag as CRITICAL any step that would be rejected because it violates ordering requirements.
7. **Multi-phase state:** For anything touching a multi-phase process (migrations, workflows, staged operations), inspect what earlier phases leave in place before asserting on later state. Flag as CRITICAL if the plan assumes absent state that an earlier phase already established.
8. If ROUND > 1: note that fixes were applied since the last round — re-evaluate all areas independently, do not assume previous fixes are correct or complete.

Review checklist:

**Problem & Solution (Critical)**
- Goal clearly stated and specific?
- Proposed solution actually solves it — no missing steps?
- Edge cases considered?
- Does the "Verified Dependency Behaviors" section exist and does each entry's actual behavior support the plan's logic? (A function named "GrantAccess" that grants USAGE+DML but not CREATE is not "full access.")

**Over-engineering (Critical)**
- Unnecessary abstractions or interfaces for a single implementation?
- YAGNI violations — features "just in case"?
- Pattern abuse — design patterns where simple code would do?

**Testing (Critical)**
- Every task includes test steps as separate checklist items?
- Tests name specific cases — happy path, error cases, edge cases — not just "write tests"?
- Single happy-path test where multiple named cases are needed?

**Task Granularity (Important)**
- Each task is ONE logical unit?
- Specific descriptive names, not generic "[Core Logic]" or "[Implementation]"?
- Clear progression task to task?

**Convention Adherence (Important)**
- Follows naming and patterns from CLAUDE.md?
- Uses project's existing libraries rather than introducing new ones without justification?

**Scope (Important)**
- No scope creep — unrelated features bundled in?
- Task dependencies are logical?

Output format (use exactly this structure):

```
## Plan Review: [filename] (round ROUND)

### Summary
[2–3 sentence honest assessment]

### Critical Issues
[omit section if none]
1. **[Section › Task/subsection]** — [what's wrong] — [how to fix it]

### Important Issues
[omit section if none]
1. **[Section › Task/subsection]** — [what's wrong] — [how to fix it]

### Minor Issues
[omit section if none]
1. **[Section › Task/subsection]** — [suggestion]

### Verdict
**APPROVE** or **NEEDS REVISION**

[If NEEDS REVISION — top priority fixes:]
1. [most critical]
2. [second]
3. [third]
```
---

## Step 2: Present findings

Show the agent's full report to the user.

## Step 3: Decide next action

**If verdict is NEEDS REVISION and round < 3**: use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan needs revision. What would you like to do?",
    "header": "Next step",
    "options": [
      {"label": "Fix and re-review", "description": "Apply fixes from the findings, then run another review round"},
      {"label": "Switch to revdiff", "description": "Open the plan in revdiff for manual inline annotation instead"},
      {"label": "Done", "description": "Stop here — I'll handle the fixes manually"}
    ],
    "multiSelect": false
  }]
}
```

- **Fix and re-review**: apply fixes to the plan file based on the findings (Edit tool), increment round counter, go to Step 1
- **Switch to revdiff**: invoke the `revdiff:revdiff` skill on the plan file. When it returns, go to Step 5
- **Done**: stop completely — do NOT suggest or begin implementation

**If verdict is APPROVE**: go to Step 5.

## Step 4: Round limit

After 3 rounds without APPROVE, stop the auto-review loop. Show any remaining issues and tell the user: "Review limit reached (3 rounds). Remaining issues listed above." Then go to Step 5.

## Step 5: Post-review menu

This is the hub every review path returns to — auto-review approval, round limit, or a revdiff pass finishing. Never stop silently here; always ask. Only "Done" ends the loop.

Use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan review complete. What would you like to do next?",
    "header": "Next step",
    "options": [
      {"label": "Run auto-review", "description": "Run another round of structured agent review"},
      {"label": "Review with revdiff", "description": "Open plan in revdiff for inline annotations"},
      {"label": "Done", "description": "Stop here — plan is ready for implementation"}
    ],
    "multiSelect": false
  }]
}
```

- **Run auto-review**: reset the round counter to 1, go to Step 1
- **Review with revdiff**: invoke the `revdiff:revdiff` skill on the plan file. When it returns, repeat Step 5
- **Done**: stop completely — do NOT suggest or begin implementation
