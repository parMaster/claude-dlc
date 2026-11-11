---
name: review-plan
description: Review an implementation plan in one pass — does the Definition of Done prove the intent, do the decisions hold up against the code, is a trap missing, is scope right. Runs as a read-only subagent, or by Codex in the other agterm pane. Activates on "review plan", "check the plan", "critique this plan", "have codex review the plan", or as an optional step after planning:plan.
allowed-tools: Read, Glob, Grep, Bash, Agent, AskUserQuestion, Edit, Skill
---

# Plan Review

One review pass by a read-only `plan-review` agent. The main session shows the findings and applies the ones that hold up. No repeat passes: the plan is short, and anything code-level gets caught during implementation by tests, the compiler and the linter.

## Step 0: Find the plan file

1. If `$ARGUMENTS` contains a file path, use it
2. Otherwise check `docs/plans/` — most recently modified `.md` (excluding `completed/` and `wbs-*.md`)
3. If multiple plans exist and it's unclear which, list them and ask

## Step 1: Choose the reviewer

The review's findings come back to this session, the context that wrote the plan, which is what applying them needs. Ask with AskUserQuestion who runs it:

```json
{
  "questions": [{
    "question": "Who should review this plan?",
    "header": "Reviewer",
    "options": [
      {"label": "Opus", "description": "Most capable — best at spotting a wrong decision or a missing trap"},
      {"label": "Sonnet", "description": "Faster and cheaper — fine for most plans"},
      {"label": "Codex", "description": "A second model family, in the other agterm pane — same checklist"}
    ],
    "multiSelect": false
  }]
}
```

Offer Codex only when `AGTERM_SESSION_ID` is set (check with `echo "$AGTERM_SESSION_ID"`). Outside agterm, drop that option.

## Step 2: Run the review

### Opus or Sonnet

Use the Agent tool with `subagent_type: planning:plan-review` and `model` set to the chosen tier. The agent can't write files — its `tools:` list has no Write or Edit. Its checklist and output format live in `plugins/planning/agents/plan-review.md`; pass only:

```
Plan file: PLAN_FILE
```

The moment the agent returns, print its full report verbatim as your own message, before doing anything else. A background agent's output is gone once it finishes — this is the only way the user sees it.

### Codex

Codex follows the same instructions file the subagent uses. Its absolute path is `../../agents/plan-review.md` from this skill's base directory; resolve it to a full path, because Codex has no `CLAUDE_PLUGIN_ROOT`.

Send the request with `/agterm:mailbox-chat`. That skill owns the send command, the `status` check, and starting Codex when it isn't there. Picking Codex here is a request for Codex only: if another Claude Code answers in the other pane, stop and ask. The message:

```
Please review the plan PLAN_FILE (absolute path).
Follow the instructions in PLAN_REVIEW_MD exactly: what to check, what not to flag, and the Output format.
Read-only: don't edit, create or delete files, and don't run builds or tests.
Reply with the report in that Output format.
```

Then end the turn. Don't wait or poll. The report arrives later as a `[peer chat]` message. Print it in full; if Codex sent a file path instead, read the file and print its contents. Then go to Step 3. Don't answer the report with a mailbox message.

## Step 3: Apply and stop

**Verdict READY with nothing listed**: tell the user the plan is ready and stop.

**Otherwise** triage every finding, Should fix and Consider alike, without asking first. The plan is in git and the user reviews it before implementing, so a wrong edit is cheap to undo.

A finding is a claim, not a fact. The reviewer may be wrong, and "a reviewer said so" is never a reason to apply it. Reject a finding when:

- it says something about the code, and your own Read or Grep of the source doesn't back it
- it asks for something `plan-review.md` says not to flag: code, file lists, signatures, test names, wording
- it would not lead to wrong or wasted work if left alone — padding, a style preference, a restatement of what the plan already says
- it contradicts a decision the user made in this conversation, and gives no new fact

Then:

1. Check each finding against those grounds with your own tool calls.
2. Apply the findings that hold up. Edit the plan at its own level — change Intent, Decisions, Traps or DoD lines; don't answer a finding by adding code or file-by-file steps.
3. Report a short list: each applied finding with what changed, and each rejected finding with a one-line reason. The rejected list lets the user overrule a skip in one message.

Then stop. No second review pass.

A finding that's real but outside the plan's scope — a pre-existing defect the plan doesn't cause or need fixed — isn't a plan edit. Offer to file it with `/backlog` instead.

Don't start implementation from here — the user calls `/agterm:handoff`, `/agterm:webrev`, `revdiff:revdiff`, or starts implementing when ready.
