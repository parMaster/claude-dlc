---
name: plan
description: Create a structured implementation plan in docs/plans/. Activates on "make a plan", "create a plan", "plan this feature", "write a plan", or when the user wants to document implementation steps before coding.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill, AskUserQuestion, EnterPlanMode
---

# Implementation Plan Creation

Create an implementation plan in `docs/plans/yyyy-mm-dd-<task-name>.md`. Write as if the engineer implementing it has zero context about the codebase — document everything they need: which files to touch, actual code to write, exact commands to run, how to test it. Assume they are skilled but know nothing about this toolset or problem domain.

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

Show the discovered context, then ask questions **one at a time** — a separate AskUserQuestion tool call per question, never multiple questions batched into one call's `questions` array:

1. **Plan purpose**: "what is the main goal?" — multiple choice with suggested answer based on discovered intent
2. **Testing approach**: "TDD or regular?" — options: "TDD (tests first)" / "Regular (code first, then tests)". Ask this early because it shapes the task structure throughout the plan.
3. **Scope**: "which components/files are involved?" — multiple choice with discovered files. The tool requires ≥2 options per question — if discovery turned up only one file/component, do not force a second fabricated option; ask this one as free text instead.
4. **Constraints**: "any specific requirements or limitations?"
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

Check `docs/plans/` for existing files, then create `docs/plans/yyyy-mm-dd-<task-name>.md` (use current date).

### File structure first

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces — each file should have one clear responsibility
- Prefer smaller, focused files; you reason best about code you can hold in context at once
- Files that change together should live together; split by responsibility, not by technical layer
- In existing codebases, follow established patterns; if a file is unwieldy, a split in the plan is reasonable

This structure informs task decomposition — each task should produce self-contained changes that make sense independently.

### Dependency contract check

**Skip this step** if the plan introduces net-new code with no existing dependencies to verify.

Otherwise, before writing tasks: identify every external function, method, or API the plan's correctness depends on — things the plan will CALL, not things it will CREATE. For each one:

1. Read its body (not just its name or signature)
2. Record what it actually guarantees: privileges granted, errors returned and how they're wrapped, side effects, state left behind after it runs
3. Flag any gap between the name's implied behavior and the body's actual behavior — these are the places plans silently go wrong

This is a focused pass — typically 3–6 functions, not broad exploration. Record findings in the "Verified Dependency Behaviors" section of the plan.

### Plan structure

```markdown
# [Plan Title]

**Goal:** [one sentence describing what this builds]

**Architecture:** [2-3 sentences about the approach]

**Tech Stack:** [key technologies/libraries involved]

---

## Context (from discovery)
- files/components involved: [list from step 0]
- related patterns found: [patterns discovered]
- dependencies identified: [dependencies]

## Verified Dependency Behaviors
*External functions/APIs this plan calls — verified by reading their bodies, not inferred from names. Omit if plan is net-new with no existing dependencies.*

- `FunctionName` (`path/to/file.go:NN`): [what it actually does — privileges granted, errors returned/wrapped, side effects, state left behind]
- ...

## Development Approach
- **testing approach**: [TDD / Regular - from user preference]
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all implementation + plan move when complete
- **CRITICAL: run `golangci-lint run ./...` before committing** — fix all linter issues first
- run tests after each change
- maintain backward compatibility

## Solution Overview
- high-level approach and architecture chosen
- key design decisions and rationale
- how it fits into the existing system

## Technical Details
- data structures and changes
- parameters and formats
- processing flow

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: [specific name]

**Files:**
- Create: `exact/path/to/new_file`
- Modify: `exact/path/to/existing`

**If TDD:**

- [ ] **Write failing tests** — happy path + error cases + edge cases

```go
func TestFunctionName_HappyPath(t *testing.T) { ... }
func TestFunctionName_InvalidInput(t *testing.T) { ... }
func TestFunctionName_EmptyResult(t *testing.T) { ... }
```

- [ ] **Run tests to verify they fail**

  Run: `go test ./path/... -run TestFunctionName -v`
  Expected: FAIL

- [ ] **Write minimal implementation**

```go
func FunctionName(input Type) ReturnType {
    // implementation
}
```

- [ ] **Run tests to verify all pass**

  Run: `go test ./path/... -run TestFunctionName -v`
  Expected: PASS

**If Regular:**

- [ ] **Write implementation**

```go
func FunctionName(input Type) ReturnType {
    // implementation
}
```

- [ ] **Write tests** — happy path + error cases + edge cases

```go
func TestFunctionName_HappyPath(t *testing.T) { ... }
func TestFunctionName_InvalidInput(t *testing.T) { ... }
func TestFunctionName_EmptyResult(t *testing.T) { ... }
```

- [ ] **Run tests to verify all pass**

  Run: `go test ./path/... -run TestFunctionName -v`
  Expected: PASS

### Task N-1: Verify acceptance criteria
- [ ] verify all requirements from Goal are implemented
- [ ] run full test suite: `go test ./...`
- [ ] run `golangci-lint run ./...` — fix all issues before proceeding
- [ ] verify test coverage meets project standard

### Task N: [Final] Wrap up and commit
- [ ] update README.md if needed
- [ ] update CLAUDE.md if new patterns discovered
- [ ] move this plan to `docs/plans/completed/` — use `mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/` (plain `mv`, not `git mv`: the plan is usually untracked, and the final `git add -A` stages the move either way)
- [ ] single summary commit: all implementation changes + plan move in one commit
- [ ] open draft PR — invoke `planning:pr`

## Post-Completion
*Items requiring manual intervention or external systems*
```

### No placeholders

Every step must contain the actual content an engineer needs. These are plan failures — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases" (without showing the code)
- "Write tests for the above" (without actual test code)
- A single happy-path test when error cases or edge cases clearly exist — always enumerate: what inputs cause errors? what are the boundary values? what does the function return when there's nothing to return? Each scenario that can fail Sonar coverage gets its own named test function.
- "Similar to Task N" (repeat the code — the engineer may read tasks out of order)
- Steps that describe what to do without showing how — if a step changes code, show the code
- References to types, functions, or methods not defined in any task

## Step 2.5: Self-review

After writing the complete plan, check it yourself before offering next steps:

1. **Spec coverage** — skim each requirement. Can you point to a task that implements it? Add tasks for any gaps.
2. **Placeholder scan** — search for any patterns from the "No placeholders" section above. Fix them.
3. **Type consistency** — do method signatures and names used in later tasks match what's defined in earlier tasks? A function called `ParseConfig()` in Task 3 but `LoadConfig()` in Task 7 is a bug.
4. **Dependency behavior check** — for each entry in "Verified Dependency Behaviors": does the plan's logic actually hold given what that function does? A function that grants USAGE+DML but not CREATE is not "full access" even if named that way.

Fix issues inline. No need to re-review after fixing.

## Step 3: Next steps

After self-review, tell the user: "created plan: `docs/plans/yyyymmdd-<task-name>.md`"

Then use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan created. What's next?",
    "header": "Next step",
    "options": [
      {"label": "Auto-review", "description": "Run structured agent review — checks correctness, over-engineering, test coverage"},
      {"label": "Review with revdiff", "description": "Open plan in revdiff for inline annotations"},
      {"label": "Done", "description": "Stop here"}
    ],
    "multiSelect": false
  }]
}
```

- **Auto-review**: invoke the `planning:review-plan` skill on the plan file — it handles the review/fix loop internally. When it returns, stop completely. Do NOT proceed to implementation.
- **Review with revdiff**: invoke the `revdiff:revdiff` skill on the plan file — it handles the full annotation and revision loop internally. When it returns, stop completely. Do NOT proceed to implementation.
- **Done**: stop.

## Key principles

- **Zero context** — write as if the implementer knows nothing about this codebase; show the code, show the commands, show expected output
- **One question at a time** — do not overwhelm with multiple questions
- **Multiple choice preferred** — easier than open-ended when possible
- **YAGNI ruthlessly** — minimal scope, no unnecessary features
- **Lead with recommendation** — have an opinion, explain why, but let user decide
- **Explore alternatives** — always propose 2-3 approaches before settling
- **Single summary commit** — never commit per task; one commit at the end covers everything
- **Complete code in every step** — if a step changes code, include the actual code block
