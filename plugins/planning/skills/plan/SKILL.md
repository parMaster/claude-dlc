---
name: plan
description: Create a structured implementation plan in docs/plans/. Activates on "make a plan", "create a plan", "plan this feature", "write a plan", or when the user wants to document implementation steps before coding.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill, AskUserQuestion, EnterPlanMode
---

# Implementation Plan Creation

Create an implementation plan in `docs/plans/yyyymmdd-<task-name>.md` with interactive context gathering.

## Step 0: Parse intent and gather context

Before asking questions, understand what the user is working on:

1. **Parse user's arguments** to identify intent:
   - "add feature Z" / "implement W" → feature development
   - "fix bug" / "debug issue" → bug fix plan
   - "refactor X" / "improve Y" → refactoring plan
   - "migrate to Z" / "upgrade W" → migration plan
   - generic request → explore current work

2. **Gather relevant context quickly** — use direct tool calls (Read, Glob, Grep), NOT an Agent. Keep discovery under 30 seconds:

   **for feature development:**
   - glob for files matching the feature area
   - read 1-3 most relevant files to understand existing patterns
   - check project structure with a quick `ls` of key directories

   **for bug fixing:**
   - grep for error messages or function names mentioned in the request
   - read the specific file(s) involved
   - check `git log --oneline -5` for recent changes

   **for refactoring/migration:**
   - glob for files matching the area being refactored
   - read 2-3 key files to understand current structure
   - grep for imports/references to identify dependencies

   **for generic/unclear requests:**
   - check `git status` and `git log --oneline -5`
   - read README.md or CLAUDE.md for project overview
   - `ls` the top-level directory structure

   **CRITICAL: do NOT launch an Agent or read more than 5 files in this step.**

3. Synthesize findings into a brief context summary (3-5 bullet points)

## Step 1: Present context and ask focused questions

Show the discovered context, then ask questions **one at a time** using AskUserQuestion:

1. **Plan purpose**: "what is the main goal?" — multiple choice with suggested answer based on discovered intent
2. **Scope**: "which components/files are involved?" — multiple choice with discovered files
3. **Constraints**: "any specific requirements or limitations?"
4. **Testing approach**: "TDD or regular?" — options: "TDD (tests first)" / "Regular (code first, then tests)"
5. **Plan title**: "short descriptive title?" — suggest based on intent

## Step 1.5: Explore approaches

Once the problem is understood, propose implementation approaches:

1. **Propose 2-3 different approaches** with trade-offs
2. **Lead with recommended option** and explain reasoning
3. **Present conversationally** — not a formal document yet

Example format:
```
I see three approaches:

**Option A: [name]** (recommended)
- how it works: ...
- pros: ...
- cons: ...

**Option B: [name]**
- how it works: ...
- pros: ...
- cons: ...

Which direction appeals to you?
```

Use AskUserQuestion to select the preferred approach before creating the plan.

**Skip this step** if the approach is obvious, user specified it, or it's a clear bug fix.

## Step 2: Create plan file

Check `docs/plans/` for existing files, then create `docs/plans/yyyymmdd-<task-name>.md` (use current date).

### Plan structure

```markdown
# [Plan Title]

## Overview
- clear description of the feature/change being implemented
- problem it solves and key benefits
- how it integrates with existing system

## Context (from discovery)
- files/components involved: [list from step 0]
- related patterns found: [patterns discovered]
- dependencies identified: [dependencies]

## Development Approach
- **testing approach**: [TDD / Regular - from user preference]
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all implementation when complete
- run tests after each change
- maintain backward compatibility

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Solution Overview
- high-level approach and architecture chosen
- key design decisions and rationale

## Technical Details
- data structures and changes
- parameters and formats
- processing flow

## Implementation Steps

### Task 1: [specific name]

**Files:**
- Create: `exact/path/to/new_file`
- Modify: `exact/path/to/existing`

- [ ] [specific action]
- [ ] [specific action]
- [ ] write tests for new/changed functionality (success cases)
- [ ] write tests for error/edge cases
- [ ] run tests - must pass before next task

### Task N-1: Verify acceptance criteria
- [ ] verify all requirements from Overview are implemented
- [ ] run full test suite: `<project test command>`
- [ ] verify test coverage meets project standard

### Task N: [Final] Update documentation
- [ ] update README.md if needed
- [ ] update CLAUDE.md if new patterns discovered
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Items requiring manual intervention or external systems*
```

## Step 3: Next steps

After creating the file, tell the user: "created plan: `docs/plans/yyyymmdd-<task-name>.md`"

Then use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan created. What's next?",
    "header": "Next step",
    "options": [
      {"label": "Review with revdiff", "description": "Open plan in revdiff for inline annotations and feedback loop"},
      {"label": "Done", "description": "Commit plan and stop"}
    ],
    "multiSelect": false
  }]
}
```

- **Review with revdiff**: invoke the `revdiff:revdiff` skill on the plan file. It will handle the annotation loop — when the user quits with annotations, revise the plan and re-open until they quit with no changes.
- **Done**: commit plan with message `docs: add <topic> implementation plan`

## Key principles

- **One question at a time** — do not overwhelm with multiple questions
- **Multiple choice preferred** — easier than open-ended when possible
- **YAGNI ruthlessly** — minimal scope, no unnecessary features
- **Lead with recommendation** — have an opinion, explain why, but let user decide
- **Explore alternatives** — always propose 2-3 approaches before settling
- **Single summary commit** — never commit per task; one commit at the end covers everything
