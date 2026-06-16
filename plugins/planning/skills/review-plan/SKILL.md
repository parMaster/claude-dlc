---
name: review-plan
description: Review an implementation plan for completeness, correctness, over-engineering, and test coverage. Iterates review rounds until no critical issues remain or round limit hit. Activates on "review plan", "check the plan", "critique this plan", or as an optional step after planning:plan.
allowed-tools: Read, Glob, Grep, Bash, Agent, AskUserQuestion, Edit
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

Steps:
1. Read the plan file fully
2. Read `CLAUDE.md` for project conventions
3. Identify the source files and packages the plan touches — read 2–4 of the most relevant ones to understand current patterns and interfaces
4. For Go code: use `gosymdb:sym` and `gosymdb:trace` skills to verify that types, functions, and interfaces mentioned in the plan actually exist in the codebase. Flag plans that reference non-existent symbols as CRITICAL.
5. If ROUND > 1: note that fixes were applied since the last round — re-evaluate all areas independently, do not assume previous fixes are correct or complete.

Review checklist:

**Problem & Solution (Critical)**
- Goal clearly stated and specific?
- Proposed solution actually solves it — no missing steps?
- Edge cases considered?

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

**If verdict is APPROVE**: inform the user the plan passed review. Done.

**If verdict is NEEDS REVISION**: use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan needs revision. What would you like to do?",
    "header": "Next step",
    "options": [
      {"label": "Fix and re-review", "description": "Apply fixes from the findings, then run another review round"},
      {"label": "Done", "description": "Stop here — I'll handle the fixes manually"}
    ],
    "multiSelect": false
  }]
}
```

- **Fix and re-review**: apply fixes to the plan file based on the findings (Edit tool), increment round counter, go to Step 1
- **Done**: stop

## Step 4: Round limit

After 3 rounds, stop regardless of verdict. Show any remaining issues and tell the user: "Review limit reached (3 rounds). Remaining issues listed above."
