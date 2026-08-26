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

Track the current round (start at 1, max 3). Every time this step runs — first review, a "Fix and re-review" continuation, or "Run auto-review" from the post-review menu — first ask which model should run this round, using AskUserQuestion:

```json
{
  "questions": [{
    "question": "Which model should review this round?",
    "header": "Model",
    "options": [
      {"label": "Inherit", "description": "Use the same model as this session (default)"},
      {"label": "Opus", "description": "Most capable — best for catching subtle logic gaps or over-engineering"},
      {"label": "Sonnet", "description": "Faster and cheaper — good for most plans"},
      {"label": "Haiku", "description": "Fastest and cheapest — for a quick mechanical pass"}
    ],
    "multiSelect": false
  }]
}
```

Use the Agent tool with `subagent_type: plan-review` — a dedicated read-only agent (`plugins/planning/agents/plan-review.md`) that only has Read/Glob/Grep/Bash; it cannot call Write, Edit, or NotebookEdit, so it cannot create, modify, or delete files no matter what its prompt says. Pass `model` set to the chosen tier (`opus`, `sonnet`, or `haiku`); for **Inherit**, omit the `model` parameter entirely. The review methodology, checklist, and output format live in the agent definition — this step only supplies what changes per call:

```
Plan file: PLAN_FILE
Review round: ROUND
```

For ROUND > 1, append the "Fixes applied since last round" list (built in Step 3) to the prompt, each line as `[finding] → [what you did]`.

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

- **Fix and re-review**:
  1. Apply fixes to the plan file based on the findings (Edit tool). Keep a running list of what you changed, phrased as one line per finding: `[finding] → [what you did]`.
  2. For every MECHANICAL finding, re-run its `verify:` command and compare against the expected result. Any that still fail must be fixed before continuing — do not spawn a new round with an unverified mechanical fix.
  3. If **every** finding in this round was MECHANICAL (no REASONED findings at all): do not spawn a new agent round. All fixes are now verified by command, which is strictly stronger evidence than another read of the plan. Report the verify results to the user and go to Step 5.
  4. Otherwise (at least one REASONED finding was present): increment the round counter, and go to Step 1. Pass the fix list from step 1 into the round prompt as "Fixes applied since last round" — this is what step 8 of the reviewer's instructions and the "Fix verdicts" output section require.
- **Switch to revdiff**: invoke the `revdiff:revdiff` skill on the plan file. When it returns, go to Step 5
- **Done**: stop completely — do NOT suggest or begin implementation

**If verdict is APPROVE**: go to Step 5.

## Step 4: Round limit

After 3 rounds without APPROVE, stop the auto-review loop. Show any remaining issues and tell the user: "Review limit reached (3 rounds). Remaining issues listed above." Then go to Step 5.

## Step 5: Post-review menu

This is the hub every review path returns to — auto-review approval, round limit, or a revdiff pass finishing. Never stop silently here; always ask. Only "Done" ends the loop.

Before building this menu, check availability: `[ "$AGTERM_ENABLED" = "1" ] && command -v agtermctl >/dev/null 2>&1`. Only include the "Implement in a Separate Session" option below when that check succeeds; omit it otherwise (the other four options are always shown).

Use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Plan review complete. What would you like to do next?",
    "header": "Next step",
    "options": [
      {"label": "Run auto-review", "description": "Run another round of structured agent review"},
      {"label": "Review with revdiff", "description": "Open plan in revdiff for inline annotations"},
      {"label": "Implement in a Subagent", "description": "Hand off implementation to a background subagent — reports back when done, keeps this session clean"},
      {"label": "Implement in a Separate Session", "description": "Hand off implementation to a fresh agterm session, in the same workspace as this one — runs interactively, you can watch and drive it directly"},
      {"label": "Done", "description": "Stop here — plan is ready for implementation"}
    ],
    "multiSelect": false
  }]
}
```

- **Run auto-review**: reset the round counter to 1, go to Step 1
- **Review with revdiff**: invoke the `revdiff:revdiff` skill on the plan file. When it returns, repeat Step 5
- **Implement in a Subagent**: first ask which model the implementer should run on, using AskUserQuestion:

  ```json
  {
    "questions": [{
      "question": "Which model should the implementer subagent use?",
      "header": "Model",
      "options": [
        {"label": "Inherit", "description": "Use the same model as this session (default)"},
        {"label": "Opus", "description": "Most capable — best for complex or subtle implementations"},
        {"label": "Sonnet", "description": "Faster and cheaper — good for straightforward plans"},
        {"label": "Haiku", "description": "Fastest and cheapest — for simple mechanical changes"}
      ],
      "multiSelect": false
    }]
  }
  ```

  Then use the Agent tool with `subagent_type: general-purpose` and `run_in_background: true` to dispatch the plan below. Pass `model` set to the chosen tier (`opus`, `sonnet`, or `haiku`); for **Inherit**, omit the `model` parameter entirely. Do NOT add task-by-task review scaffolding or extra process — this is a plain hand-off, matching what a fresh session would get:

  ```
  You have a new implementation plan to execute: PLAN_FILE

  Read it fully, then implement every task in order, following its stated
  testing approach. Run the project's tests and linter before treating any
  task as done. When the whole plan is implemented, report a concise
  summary of what changed, and flag any deviations from the plan or open
  concerns.
  ```

  Tell the user implementation has been handed off to a background subagent (noting the chosen model) and they'll be notified when it completes. Stop completely — do NOT continue the review loop.
- **Implement in a Separate Session**: hand off to a fresh agterm session in this same workspace — no model-tier question (agterm has no model picker; the new session runs whatever `claude` launches with by default).

  Run the whole handoff as **one Bash tool call** — `session new` always steals UI focus (no flag suppresses it), so splitting this into several calls forces the user to approve one, get yanked to the new session, switch back to approve the rest, then switch again to actually watch it. One chained call means one approval, and the UI lands on the new session — already running — when it's done:

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

  Substitute the real plan path for both occurrences of `PLAN_FILE`. If the command's exit status is non-zero (`session new` failed, or `SID` came back empty/`null` — `agtermctl` present but the socket unreachable, or some other agterm-side error), the `&&` chain short-circuits before typing anything into a nonexistent target; tell the user the handoff failed with the captured error output, and stop. Do not fall back to a subagent silently.

  Then tell the user: implementation has been handed off to a new agterm session (named `Implement: SLUG`) in this same workspace — they can switch to it to watch or drive it directly. Stop completely — do NOT continue the review loop.
- **Done**: stop completely — do NOT suggest or begin implementation
