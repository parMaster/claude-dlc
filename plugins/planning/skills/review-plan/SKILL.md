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

## Step 0.3: Choose review runtime

Before running any review round, check availability: `[ "$AGTERM_ENABLED" = "1" ] && command -v agtermctl >/dev/null 2>&1`. If unavailable, skip this step entirely and continue to Step 0.5 — there's only one real choice (this session), so there's nothing to ask.

If available, ask with AskUserQuestion:

```json
{
  "questions": [{
    "question": "Where should this review run?",
    "header": "Runtime",
    "options": [
      {"label": "This session", "description": "Continue here — delegates each review round to the plan-review subagent, as it already does"},
      {"label": "Spawn Codex session", "description": "Hand the whole review off to a freshly spawned Codex CLI session running this same skill there — this session's job ends once it's spawned"}
    ],
    "multiSelect": false
  }]
}
```

**This session**: continue to Step 0.5.

**Spawn Codex session**: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-review-handoff.sh" "PLAN_FILE"` (substitute the real plan path for `PLAN_FILE`). No model question — the spawned session always uses whatever model Codex is configured to use by default.

On success (exit 0), the script's last stdout line is the new session's display name (e.g. `Review: foo`) — tell the user the review has been handed off to a new Codex session with that name, in this same workspace, and they can switch to it to watch or drive it directly. On failure (non-zero exit), tell the user the hand-off failed, quoting the script's stderr output. Do not fall back to reviewing in this session silently. Either way, stop completely — do NOT run Step 0.5 or any review round in this session.

## Step 0.5: Mechanical pre-pass

Run once per plan, before the first review round, without asking which model — this one is always Haiku. Roughly 40% of round-1 findings in the measured history were grep-provable; clearing them here means the reasoned round spends its context on judgment instead of stale identifiers.

Use the Agent tool with `subagent_type: planning:plan-review` and `model: "haiku"`, passing:

```
Plan file: PLAN_FILE
Mode: mechanical
```

Print its report verbatim as your own chat message, same as Step 2 requires for a full round. Then apply every finding with the Edit tool and re-run each finding's own `verify:` command, fixing anything that still fails before continuing.

Then go to Step 1 with the round counter at **1**. The pre-pass is not a round: it does not consume the 1–3 budget, and its fixes are **not** passed into round 1 as "Fixes applied since last round" — round 1 is still the first reasoned look at the whole plan, and telling the reviewer otherwise would make it narrow itself per step 8 of its own instructions.

## Step 1: Spawn review agent

Track the current round (start at 1, max 3 — the Step 0.5 pre-pass is not counted). Every time this step runs — first review, or a "Fix and re-review" continuation — first ask which model should run this round, using AskUserQuestion:

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

Use the Agent tool with `subagent_type: planning:plan-review` — a dedicated read-only agent (`plugins/planning/agents/plan-review.md`) that only has Read/Glob/Grep/Bash; it cannot call Write, Edit, or NotebookEdit, so it cannot create, modify, or delete files no matter what its prompt says. Pass `model` set to the chosen tier (`opus`, `sonnet`, or `haiku`); for **Inherit**, omit the `model` parameter entirely. The review methodology, checklist, and output format live in the agent definition — this step only supplies what changes per call:

```
Plan file: PLAN_FILE
Review round: ROUND
```

For ROUND > 1, append the "Fixes applied since last round" list (built in Step 3) to the prompt, each line as `[finding] → [what you did]`.

## Step 2: Present findings

The instant the review agent returns — foreground or background — your next action, before anything else, is to print its full report verbatim as your own chat message. Not a summary, not "let me look into these first": paste the report, then stop. Do not Grep, Read, Edit, or otherwise start acting on findings before it's posted — that includes the "every finding was MECHANICAL, skip straight to Step 5" path in Step 3, which still needs the report shown first. This is mandatory, not optional, when Step 1 ran as a background agent: once a background agent finishes, its output is gone from the transcript — there is no panel or log the user can expand to see it afterward. Printing the report here is the only way the user ever sees it. Nothing — not Step 3's AskUserQuestion, not a fix already in progress — may be the first thing the user sees after a review round.

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
  1. Apply fixes to the plan file based on the findings (Edit tool). For any finding that reveals a pattern repeated across multiple tasks (the same wrong assumption about a function's behavior, the same stale reference, reused in several places) — grep/scan the whole plan for every other instance of that pattern and fix all of them now, not just the line(s) the reviewer flagged. When a finding says code needs more explanation, inline it per `planning:plan`'s "Code comment rules" — never resolve it by adding a comment that points back to Technical Details, a spec doc, or a ticket. Keep a running list of what you changed, phrased as one line per finding: `[finding] → [what you did]`.
  2. For every MECHANICAL finding, re-run exactly its own `verify:` command and compare against the expected result — not a broader rescan of the whole plan "while you're at it." Do this silently alongside applying the fixes, not as an announced separate step; only surface it if a result doesn't match what the finding expected. Any that still fail must be fixed before continuing — do not spawn a new round with an unverified mechanical fix.
  3. For every REASONED finding, check your own fix before moving on: read the source the fix now claims something about, and confirm the claim holds. A fix that rewrites a call must match the real signature in the file; a fix that changes an expected value must match what the code actually returns. Of the fixes measured across this loop's history, 45 were later judged incomplete and 26 had introduced a new problem — the next round is not the place to discover that. If a fix touches a task other than the flagged one, re-read that task in full too. Do this silently; surface only what you had to correct.
  4. If **every** finding in this round was MECHANICAL (no REASONED findings at all): do not spawn a new agent round. All fixes are now verified by command, which is strictly stronger evidence than another read of the plan. Report the verify results to the user and go to Step 5.
  5. Otherwise (at least one REASONED finding was present): increment the round counter, and go to Step 1. Pass the fix list from step 1 into the round prompt as "Fixes applied since last round" — this is what step 8 of the reviewer's instructions and the "Fix verdicts" output section require.
- **Switch to revdiff**: invoke the `revdiff:revdiff` skill on the plan file. When it returns, go to Step 5
- **Done**: stop completely — do NOT suggest or begin implementation

**If verdict is APPROVE**: go to Step 5.

## Step 4: Round limit

After 3 rounds without APPROVE, stop the auto-review loop. Show any remaining issues and tell the user: "Review limit reached (3 rounds). Remaining issues listed above." Then go to Step 5.

## Step 5: Report and stop

This is where every review path ends — auto-review approval, round limit, or a revdiff pass finishing. Report the outcome and stop. Do not ask what to do next — the user calls `/planning:handoff`, `revdiff:revdiff`, or begins implementation directly when ready.

- **Arriving with an APPROVE verdict** (Step 3): tell the user the plan is approved and ready for implementation.
- **Arriving after the round limit** (Step 4, which already reported "Review limit reached (3 rounds). Remaining issues listed above."): nothing further to report — just stop.
- **Arriving after a revdiff pass returns** (Step 3's "Switch to revdiff" branch): tell the user the revdiff pass is done and review is complete.
