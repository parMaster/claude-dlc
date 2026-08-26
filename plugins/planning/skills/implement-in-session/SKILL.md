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

## Step 2: Hand off

Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "PLAN_FILE"`, substituting the plan path resolved in Step 1.

This one call also performs the `AGTERM_ENABLED`/`agtermctl` availability check
internally — unlike `plan`/`review-plan`, which check availability separately
to decide whether to even show their menu option, this skill has no menu, so
there's no reason to check twice. If it exits non-zero, tell the user why
(its stderr says either "not available" or the specific hand-off failure) and
stop.

## Step 3: Confirm

On success, the script's last stdout line is the new session's display name
(e.g. `Implement: foo`) — tell the user: implementation has been handed off
to a new agterm session with that name, in this same workspace, and they can
switch to it to watch or drive it directly. Stop completely.
