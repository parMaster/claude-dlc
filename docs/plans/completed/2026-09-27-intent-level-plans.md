# Intent-level plans

**Goal:** Plans say what, why and how we'll know it's done — not the code. Plan review becomes one light pass.

**Kind of change:** refactor of the `planning` plugin, major bump 1.24.1 → 2.0.0 (plan format changes).

## Intent

Plans written by `plan` are pre-written diffs: ~860 lines each on a simple app
(cards-v2), full of code, line numbers and signatures. Nobody reads them, and
`review-plan` burns most of its tokens checking that markdown code would compile
— which the compiler, tests and linter do for free at implementation time. The
reviewer is also pushed to always find something.

Current models can take a plan at the level of the oversight WBS (intent,
decisions, DoD) and pick the code themselves. The plan should be short enough
that the user reads it in two minutes and still knows where the change is going
and how we'll know it got there.

## Decisions

- **Rewrite in place, not a parallel plugin.** Two `plan` skills would fight over
  "make a plan", and `oversight`, `handoff`, `pr` and global-rules all point at
  `planning:plan`. Fallback is the local tag `planning-v1.24.1` loaded with
  `claude --plugin-dir` from a worktree.
- **New plan format**, in this order:
  - Goal — one sentence
  - Kind of change — bug fix / refactor / feature / migration
  - Intent — what and why, a short paragraph
  - Decisions — chosen approach, the alternatives dropped, why
  - Constraints / out of scope
  - Traps — dependency behavior that differs from its name, state left by an
    earlier phase, anything a fresh implementer would get wrong. Replaces
    "Verified Dependency Behaviors". Omitted when there are none.
  - Definition of Done — checkboxes, each a checkable outcome plus how it's proven
    (a test, a command, what to observe)
  - Work order — optional, one line per step, only when order matters
  - Wrap-up — fixed footer: full tests + lint, README/CLAUDE.md if needed, move
    plan to `completed/`, single commit, `planning:pr`
- **No code in plans.** Exception: a small snippet for one genuinely tricky item
  (a query, a migration step) where prose would be ambiguous.
- **Test order lives in the DoD, set by kind of change:**
  - bug fix → a test reproduces the bug and fails before the fix
  - refactor → behavior pinned by tests before the change, same tests green after
  - feature / migration → DoD lists what must be proven; implementer picks order
  The "TDD or regular?" question goes away.
- **Planner still investigates.** It reads the code and dependencies it relies on;
  what it finds goes into Traps and Decisions, not into code blocks.
- **`review-plan` is one pass.** No rounds, no mechanical Haiku pre-pass, no
  MECHANICAL/REASONED tags or `verify:` commands. Model question asked once.
  Codex hand-off option stays. "Nothing to flag" is a normal result.
- **`plan-review` agent checks only:** does the DoD prove the intent; are the
  decisions sound given the code; is a trap missing (it may read source to check);
  is scope right (creep, YAGNI). Findings: what's wrong + suggested change, at
  most a few, no severity tiers beyond "should fix" / "consider".

## Constraints / out of scope

- Flow stays plan → (review) → implement → pr. `oversight`, `backlog`,
  `spawn-session` keep working unchanged unless they reference removed parts.
- Old plans in other repos' `completed/` are not migrated.
- `block-inline-edit`'s `perl -i` exception for `docs/plans/` stays (DoD
  checkboxes still get ticked).
- No evals or metrics for the new format — judged by use.

## Traps

- `pr` reads the **Goal** line and the "task list" to build Changes/Testing.
  There is no task list any more — it must use the DoD and Decisions, and take
  Changes from the actual diff (`git diff <base>...HEAD --stat`), since the plan
  no longer names files.
- `handoff-prompt.sh` tells the implementer to "implement every task in order,
  following its stated testing approach" and the review prompt says "iterate
  review rounds". Both texts go stale.
- `review-plan` Step 3 cites `planning:plan`'s "Code comment rules" — that
  section is being deleted.
- `plan/SKILL.md` self-review says it "mirrors what the plan-review agent
  verifies" — the two checklists must stay in step.
- global-rules CLAUDE.md says the `docs/plans/` doc is what "review-plan and pr
  depend on" — still true, but check its wording after the rewrite. Changing it
  means a global-rules bump too.

## Definition of Done

- [x] `plan/SKILL.md` produces the new format: template above, no code-block
  task template, no TDD/regular question, no "zero context / show the code"
  principle. Proof: read it; `grep -nE 'If TDD|Complete code|Zero context|Code comment rules' plugins/planning/skills/plan/SKILL.md` → no matches.
- [x] `plan/SKILL.md` is well under half its current 327 lines. Proof: `wc -l`.
- [x] `plan`'s self-review covers: every intent point has a DoD item, every DoD
  item says how it's proven, Traps checked against source, no code beyond the
  snippet exception.
- [x] `plan-review.md` checks only the four things in Decisions and allows an
  empty result. Proof: `grep -nE 'MECHANICAL|verify:|Mode: mechanical|round' plugins/planning/agents/plan-review.md` → no matches.
- [x] `review-plan/SKILL.md` runs one pass: no Step 0.5, no round counter, no
  round limit, Codex hand-off kept. Proof: `grep -niE 'round|haiku|pre-pass' plugins/planning/skills/review-plan/SKILL.md` → nothing but incidental wording.
- [x] `pr` builds the description from Goal/Intent, DoD and the branch diff.
- [x] `handoff-prompt.sh` texts match the new format (implement to the DoD;
  single review pass). Proof: `bash -n` on the script; read both functions.
- [x] No leftover references to removed parts anywhere in the repo. Proof:
  `grep -rnE 'Verified Dependency Behaviors|Code comment rules|review round|Mode: mechanical' plugins README.md` → no matches.
- [x] README planning section and table describe the new behavior; mermaid flow
  unchanged.
- [x] planning `plugin.json` at 2.0.0 and a `## planning 2.0.0 - <date>` CHANGELOG
  entry naming the fallback tag. global-rules bumped only if its CLAUDE.md changed.
- [x] This plan itself fits the new format and is under ~150 lines.

## Work order

1. `plan/SKILL.md` (defines the format everything else refers to)
2. `plan-review.md`, then `review-plan/SKILL.md`
3. `pr`, `handoff-prompt.sh`, other references
4. README, version, CHANGELOG

## Wrap-up

- [x] resync with remote (`git fetch && git status`)
- [x] move this plan to `docs/plans/completed/`
- [ ] single commit: all changes + plan move
- [ ] push the `planning-v1.24.1` tag with the commit (ask first)

## Post-Completion

- Try the new `plan` on a side project; note what hurts, patch.
- Then use it on main-job work, where Traps will carry the most weight.
