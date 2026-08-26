---
name: implement-in-session
description: Hand off an implementation plan directly to a fresh agterm session, skipping the plan/review-plan menus. Explicit invocation only.
argument-hint: "[plan-file]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash
---

# Implement in a Separate Session

Hand a plan straight to a fresh agterm session — the same mechanism `plan` and
`review-plan` offer inline, without going through either skill's menus.

## Step 1: Resolve the plan file

1. If an argument was given (`$0`), use it as the plan file path.
2. Otherwise, find the most recently modified plan:

   Run: `ls -t docs/plans/*.md 2>/dev/null | head -1`

   (this already excludes `docs/plans/completed/`, since `*.md` only globs
   files directly under `docs/plans/`, not its subdirectories)

3. If step 2 produced no output (no `.md` files directly under `docs/plans/`),
   tell the user there's no active plan to hand off and stop.
4. Verify the resolved path exists: `test -f "<path>"`. If it doesn't, tell
   the user the file wasn't found and stop.

## Step 2: Check agterm availability

Run: `[ "$AGTERM_ENABLED" = "1" ] && command -v agtermctl >/dev/null 2>&1 && echo AVAILABLE`

Unlike `plan`/`review-plan`, which simply omit their inline option when this
check fails, this skill has no menu to hide behind. If the check doesn't
print `AVAILABLE`, tell the user plainly: "This only works inside an agterm
session with `agtermctl` on PATH — `AGTERM_ENABLED` is unset or `agtermctl`
wasn't found." Then stop. Do not fall back to a subagent or any other
mechanism.

## Step 3: Hand off

Run the following as a single Bash tool call (one shell invocation, `&&`-chained)
— this is the exact sequence `plan`'s and `review-plan`'s "Implement in a
Separate Session" option already use, parameterized by the plan file resolved
in Step 1 (`PLAN_FILE` below):

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel) && \
SLUG=$(basename "PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//') && \
SID=$(agtermctl session new --cwd "$PROJECT_ROOT" --workspace "$AGTERM_WORKSPACE_ID" --name "Implement: $SLUG" --json | jq -r '.result.id') && \
[ -n "$SID" ] && [ "$SID" != "null" ] && \
agtermctl session type "claude 'You have a new implementation plan to execute: PLAN_FILE

Read it fully, then implement every task in order, following its stated
testing approach. Run the project'\''s tests and linter before treating any
task as done.'" --target "$SID" && \
agtermctl session type $'\n' --target "$SID"
```

Substitute the real resolved plan path for both occurrences of `PLAN_FILE`.
If the command's exit status is non-zero, the `&&` chain short-circuited
before typing anything into a nonexistent target — tell the user the handoff
failed with the captured error output, and stop.

## Step 4: Confirm

Tell the user: implementation has been handed off to a new agterm session
(named `Implement: SLUG`) in this same workspace — they can switch to it to
watch or drive it directly. Stop completely.
