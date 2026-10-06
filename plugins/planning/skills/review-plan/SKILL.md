---
name: review-plan
description: Review an implementation plan in one pass — does the Definition of Done prove the intent, do the decisions hold up against the code, is a trap missing, is scope right. Activates on "review plan", "check the plan", "critique this plan", or as an optional step after planning:plan.
allowed-tools: Read, Glob, Grep, Bash, Agent, AskUserQuestion, Edit
---

# Plan Review

One review pass by a read-only `plan-review` agent. The main session shows the findings and applies the ones the user wants. No repeat passes: the plan is short, and anything code-level gets caught during implementation by tests, the compiler and the linter.

## Step 0: Find the plan file

1. If `$ARGUMENTS` contains a file path, use it
2. Otherwise check `docs/plans/` — most recently modified `.md` (excluding `completed/` and `wbs-*.md`)
3. If multiple plans exist and it's unclear which, list them and ask

## Step 1: Choose the model

The review runs in this session: the subagent's findings come back to the context that wrote the plan, which is what applying them needs. Ask with AskUserQuestion which model runs it:

```json
{
  "questions": [{
    "question": "Which model should review this plan?",
    "header": "Model",
    "options": [
      {"label": "Opus", "description": "Most capable — best at spotting a wrong decision or a missing trap"},
      {"label": "Sonnet", "description": "Faster and cheaper — fine for most plans"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: Run the review

Use the Agent tool with `subagent_type: planning:plan-review` and `model` set to the chosen tier. The agent can't write files — its `tools:` list has no Write or Edit. Its checklist and output format live in `plugins/planning/agents/plan-review.md`; pass only:

```
Plan file: PLAN_FILE
```

The moment the agent returns, print its full report verbatim as your own message, before doing anything else. A background agent's output is gone once it finishes — this is the only way the user sees it.

## Step 3: Apply and stop

**Verdict READY with nothing listed**: tell the user the plan is ready and stop.

**Otherwise** ask with AskUserQuestion:

```json
{
  "questions": [{
    "question": "Apply the review findings to the plan?",
    "header": "Findings",
    "options": [
      {"label": "Apply 'Should fix'", "description": "Edit the plan for the Should-fix items only"},
      {"label": "Apply all", "description": "Also apply the Consider items"},
      {"label": "Done", "description": "Leave the plan as is — I'll handle it"}
    ],
    "multiSelect": false
  }]
}
```

When applying, edit the plan at its own level — change Intent, Decisions, Traps or DoD lines; don't answer a finding by adding code or file-by-file steps. If a finding says something about the code, check the source before writing it into the plan. Then report in one line what changed and stop. No second review pass.

A finding that's real but outside the plan's scope — a pre-existing defect the plan doesn't cause or need fixed — isn't a plan edit. Offer to file it with `/backlog` instead.

Don't start implementation from here — the user calls `/agterm:handoff`, `revdiff:revdiff`, or starts implementing when ready.
