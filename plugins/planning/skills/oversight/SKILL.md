---
name: oversight
description: Establish scope, Definition of Done, and iteration chunking for a multi-plan epic, before any iteration gets individually planned. Activates on "let's scope this epic", "start an oversight session", "oversight session for X", "break this epic into iterations", "how should we chunk this epic", or when deciding how to group tickets into chunks of work before planning any of them.
argument-hint: "[epic or scope description]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Skill, AskUserQuestion
---

# Oversight: Scope, Definition of Done, and Iteration Chunking

A standing session for the whole duration of a multi-plan epic: establish
scope, pin down Definition of Done, decide how to chunk the scope into
iterations, and track iteration status in a persistent
`docs/plans/wbs-<slug>.md` doc — so restarting this session mid-epic resumes
from that doc instead of re-deriving the framework from scratch.

Not `plan` (which plans one iteration in detail once scope is already
decided) and not `brainstorm` (creative design dialogue for a single idea).
This is the layer above both: deciding *what* the iterations are before any
of them gets individually planned.

## Step 0: New scope or resume?

Find existing WBS docs: `ls -t docs/plans/wbs-*.md 2>/dev/null`.

- **No WBS docs found**: this is new scope. Go to Step 1.
- **One WBS doc found**: read it fully. If `$ARGUMENTS` was given and clearly
  names a *different* epic than this doc, treat the request as new scope (go
  to Step 1) instead of forcing it into an unrelated doc. Otherwise, this is
  a resume: go to Step 5 with the doc's current state.
- **Multiple WBS docs found**: if `$ARGUMENTS` narrows it to one (matches a
  slug or title), read that one and go to Step 5. Otherwise list each one
  (title + a one-line iteration-status summary) and ask which one, or
  "start a new epic."

## Step 1: Gather scope

Ask (one question at a time) what makes up this epic's scope: the
ticket/epic reference if there is one (a Jira key, an epic name, or just a
description), and a rough list of the individual tickets/tasks involved.
Free text is fine — this doesn't need a formal ticket system; a plain list
of "things that need to happen" works.

This skill does not integrate with Jira/Confluence directly — if the user
has a Jira epic, they paste the ticket list/titles in themselves rather than
this skill fetching them.

## Step 2: Decide chunking into iterations

Explain the grouping heuristic, then propose a grouping:

> Group tickets into one iteration when planning and implementing them
> one-by-one, in isolation, would produce throwaway work — stubs, fake or
> interim implementations that get discarded minutes later when the next
> ticket's real implementation replaces them. Otherwise, leave each ticket
> as its own iteration. Some scopes don't need grouping at all — either
> every ticket is already big enough to stand alone, or the initial
> decomposition is already good and each ticket is genuinely independent.

Propose a specific grouping (which tickets share an iteration, and why —
cite the actual dependency/stub-avoidance reason, not just "these seem
related"), or propose no grouping at all if none of the scope needs it. Go
to Step 3 to check the proposal against INVEST before asking for
confirmation — a grouping that fails INVEST needs adjusting before it's
worth confirming, not after.

## Step 3: INVEST pass on the proposed iterations

Check the grouping from Step 2 against INVEST, per iteration — not per raw
ticket. An iteration, not a single ticket, is the actual unit that gets
handed to `plan` and delivered, so it's what needs to satisfy INVEST; a
ticket can legitimately fail this alone precisely because it's meant to be
part of a group:

- **Independent** — can this iteration be delivered without waiting on
  another iteration in this scope?
- **Negotiable** — is it a rough contract, not an overspecified spec?
- **Valuable** — does it deliver something a user/stakeholder actually
  cares about on its own?
- **Estimable** — can its size be judged with reasonable confidence?
- **Small** — does it fit in a single `plan` invocation, not a mini-epic
  itself?
- **Testable** — is there a clear, checkable condition for "this iteration
  is done"?

Flag anything that fails a criterion and discuss it with the user — this
usually means adjusting the grouping (go back to Step 2), not accepting a
flawed iteration. Once every iteration holds up, ask for the epic-level
Definition of Done: one clear sentence describing what "the whole scope is
done" means. Then confirm the final grouping with AskUserQuestion before
writing anything down — this is a real decision, not a formality:

```json
{
  "questions": [{
    "question": "Proposed iteration grouping — does this look right?",
    "header": "Chunking",
    "options": [
      {"label": "Yes, use this grouping", "description": "Write the WBS doc with the iterations as proposed"},
      {"label": "No, let me adjust", "description": "Discuss changes before writing anything down"}
    ],
    "multiSelect": false
  }]
}
```

## Step 4: Write the WBS doc

Create `docs/plans/wbs-<epic-slug>.md` (slug from the epic name/ticket
reference, kebab-case):

```markdown
# WBS: [Epic Title]

**Scope source:** [ticket/epic reference, or "ad hoc — no ticket system"]
**Definition of Done (epic-level):** [one sentence]

---

## Scope

| Ticket | Title |
|--------|-------|
| [ID or n/a] | [title] |

## Chunking Decision

[the grouping rationale from Step 2, in full — which tickets are grouped and why, or why nothing is grouped]

## Iterations

### Iteration 1: [name]
**Tickets:** [ticket IDs/titles in this iteration]
**Status:** not started
**Grouping rationale:** [why these tickets are together, or "ungrouped — stands alone"]
**INVEST notes:** [anything flagged in Step 3, or "clean"]

### Iteration 2: [name]
**Tickets:** [...]
**Status:** not started
**Grouping rationale:** [...]
**INVEST notes:** [...]

## Progress Log
- [today's date]: WBS created. [N] iterations defined.
```

Two statuses only: `not started` and `done`. Every iteration starts at
`not started`.

## Step 5: Iteration hub

This is where every path lands — a fresh WBS doc from Step 4, or a resumed
one from Step 0. Show the current iteration list with status, then ask:

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Next step",
    "options": [
      {"label": "Kick off an iteration", "description": "Spawn a new session to plan a specific iteration, via planning:spawn-session"},
      {"label": "Mark an iteration done", "description": "Update status once an iteration is actually finished"},
      {"label": "Add or re-scope tickets", "description": "Add new tickets to this epic, or revisit the chunking decision"},
      {"label": "Done for now", "description": "Stop here — this session stays available to resume later"}
    ],
    "multiSelect": false
  }]
}
```

- **Kick off an iteration**: ask which iteration — with only two statuses
  there's no "next" to infer, and the user typically already knows which
  one they mean ("let's start iteration 1", "the third part is done, kick
  off the next one"). Build a self-contained task prompt from what this
  doc already has: the iteration's tickets and its grouping rationale, plus
  an instruction to run `/planning:plan` against that scope. The new
  session doesn't need to read the WBS doc itself — everything it needs is
  already in the prompt, so it isn't pulled into reasoning about the rest
  of the epic (other iterations, the full scope table) for no reason:

  ```
  Plan [iteration name]: [tickets, comma-separated].

  [grouping rationale for this iteration, copied from the WBS doc's
  Iterations section — verbatim, so the new session knows why these
  tickets are bundled together]

  Run /planning:plan against this scope.
  ```

  Invoke the `planning:spawn-session` skill (Skill tool) with that prompt
  as its argument — it handles the rest itself: asking which CLI/runtime
  and model, naming and spawning the session. This skill doesn't ask those
  questions; `spawn-session` already does. Append a Progress Log entry
  noting the iteration was kicked off (date + iteration name) — status
  stays `not started` until the user reports it done. Go back to Step 5
  once `spawn-session` reports the outcome.

- **Mark an iteration done**: ask which iteration, update its status to
  `done` in the WBS doc and append a Progress Log entry (date + what
  changed). Go back to Step 5.

- **Add or re-scope tickets**: run Step 1 for the new tickets, then re-run
  Step 2/Step 3's chunking and INVEST pass — new tickets might join an
  existing iteration or form a new one; iterations already `done` should
  not be silently reshuffled without telling the user. Update the WBS doc
  (Scope table, Chunking Decision, Iterations), append a Progress Log
  entry, go back to Step 5.

- **Done for now**: stop. The WBS doc is already saved — the next time this
  skill runs against the same epic, it resumes from here (Step 0).

## Key principles

- **One question at a time** — do not overwhelm with multiple questions
- **This session is long-lived** — unlike `plan`/`review-plan`, which report
  and stop, oversight's whole job is the Step 5 hub: it's meant to be
  revisited across the epic's lifetime, in this session or a resumed one
- **Persist, don't re-derive** — every decision (scope, DoD, chunking,
  status) lives in the WBS doc, not just this conversation's memory
- **Delegate spawning, don't reimplement it** — kicking off an iteration
  goes through `planning:spawn-session`, which already owns the
  runtime/model questions and session creation; this skill only builds the
  task prompt
- **Chunk only to avoid throwaway work** — grouping tickets into one
  iteration is justified by "isolated planning would produce stubs
  discarded minutes later," never by vague relatedness
- **Context economy** — this session's context is often rebuilt from
  scratch after long (1h+) gaps between tasks. Keep step text and prompts
  minimal; don't load or write anything "just in case"
