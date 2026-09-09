---
name: handoff
description: Hand off an implementation plan directly to a fresh agterm session, skipping the plan/review-plan menus. Explicit invocation only.
argument-hint: "[plan-file]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, ListAgents
---

# Handoff to a Separate Session

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

## Step 2: Learn this session's own name

Call `ListAgents`. Its result opens with a self-identifying line:

```
This session is claude-dlc-c7 [39feef] — the name other sessions use to message it
```

`CALLER_NAME` is the bare name before the ` [` — no brackets, no backticks
(`claude-dlc-c7` above). If no line matches that shape, pass an empty
`CALLER_NAME` in Step 4 — a missing name must never block the hand-off.

## Step 3: Choose a model

Ask with `AskUserQuestion` — question "Which model should the new session
use?", header "Model", single-select, options:

- **Inherit** — whatever `claude` launches with by default
- **Opus** — most capable; complex or subtle implementations
- **Sonnet** — faster and cheaper; straightforward plans
- **Haiku** — fastest and cheapest; simple mechanical changes

`MODEL` is the lower-cased label, or an empty string for **Inherit**.

## Step 4: Hand off

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "PLAN_FILE" "CALLER_NAME" "MODEL"
```

Arguments are positional, so a missing value still needs its slot:

```bash
# plan, caller name, model
... "docs/plans/2026-09-09-foo.md" "claude-dlc-c7" "opus"
# no caller name (Step 2 found none), model chosen
... "docs/plans/2026-09-09-foo.md" "" "opus"
# caller name, Inherit
... "docs/plans/2026-09-09-foo.md" "claude-dlc-c7" ""
```

The script checks agterm availability itself; don't pre-check. On non-zero
exit, report its stderr and stop.

## Step 5: Report the outcome

On success, the script's last stdout line is the new session's display name
(e.g. `Implement: foo`) — tell the user: implementation has been handed off
to a new agterm session with that name, in this same workspace (noting the
chosen model, unless Inherit), and they can switch to it to watch or drive it
directly. Stop completely.
