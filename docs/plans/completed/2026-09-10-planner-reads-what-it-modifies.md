# Move Plan Verification Upstream: Planner Reads What It Modifies

**Goal:** Cut `planning:review-plan` rounds by removing their most common cause — plans written against files the planner never opened — and stop paying Opus rates for grep-provable findings.

**Architecture:** Three independent changes plus a measurement baseline. `plan` gains a hard rule to read, in full, every existing file a task lists under Create/Modify (and the sibling test files any new test code will reuse) before writing that task — the reading the reviewer does anyway, moved to where it prevents the error instead of reporting it. `review-plan` gains a cheap Haiku mechanical pre-pass that clears grep-provable findings before the first Opus round, and its fix step re-checks its own edits against the source it changed rather than deferring that to another round. The measurement that motivated all of this is committed as a re-runnable script plus a dated methodology note, so the same numbers can be produced again in a week and compared.

**Tech Stack:** Markdown skill/agent instruction files, plus one standalone Python 3 analysis script (stdlib only). No application code, no runtime.

---

## Context (from discovery)

- Files involved: `plugins/planning/skills/plan/SKILL.md`, `plugins/planning/skills/review-plan/SKILL.md`, `plugins/planning/agents/plan-review.md`, `plugins/planning/.claude-plugin/plugin.json` (currently `1.18.2`), `CHANGELOG.md`, `README.md`. New: `docs/analysis/2026-09-10-plan-review-loop-measurement.md`, `docs/analysis/measure-review-rounds.py`.
- **All three instruction files were read in full before this plan's tasks were written** — this plan applies its own new rule to itself.
- **Sibling plan on disk** — `docs/plans/completed/2026-09-08-plan-review-loop-quality.md` (shipped as `planning 1.16.0`) already folded the reviewer's deep checks 4–7 into `plan`'s Step 2.5 self-review. It copied the *checks* but not the *reading budget*: Step 0 still caps discovery at 5 files / 30 seconds and the dependency-contract check at 3–6 functions, and neither ever opens a test file. So self-review items 4–7 run against source the planner never read, which is why they catch so little. This plan closes that gap. Its presence is also what put this plan into deep-discovery mode.
- **`review-plan`'s existing round machinery**: round counter starts at 1, max 3 (Step 1 / Step 4). Step 8 of `plan-review.md` scopes the expensive checks down for `round > 1`, keyed on the round number in the prompt. The new pre-pass must therefore **not** be numbered as a round and must **not** pass a fix list into round 1 — either would make round 1 behave as a narrowed re-review of a plan nothing has reasoned over yet.
- **`review-plan` Step 3 already has a mechanical shortcut**: if every finding in a round was MECHANICAL, it verifies by command and skips to Step 5 rather than spawning another round. The new pre-pass sits before round 1 and is a different thing; both stay.
- **Test suite**: `bash tests/run.sh` → `Results: 44 passed, 0 failed` at the time of writing. It covers only `hooks/`/`scripts/` shell behavior, nothing in these markdown files, so it is a regression guard here, not a check on this change.
- **Repo conventions that apply**: bump `plugins/planning/.claude-plugin/plugin.json` and add a `CHANGELOG.md` entry in the same commit; keep `README.md` current; no hardcoded personal paths; heading format `## planning X.Y.Z - YYYY-MM-DD` (no `v`, matching every entry since 2026-08-31).
- **No `docs/analysis/` directory exists yet** in this repo — Task 6 creates it.

This plan introduces no new code dependencies to verify — skip "Verified Dependency Behaviors". The one new script uses only Python 3 stdlib (`json`, `glob`, `os`, `re`, `statistics`, `collections`, `argparse`).

## Development Approach

- **testing approach**: Regular. There is no application code, so "tests" here means the command-level assertions in Task 9 plus one real end-to-end run of the new script against live transcripts.
- One section edited at a time; re-read the whole file after each edit to catch cross-references broken by an earlier edit in the same file.
- **CRITICAL: bump `plugins/planning/.claude-plugin/plugin.json` to `1.19.0` and add a `CHANGELOG.md` entry in the same commit.**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all edits, the new files, the version bump, the changelog, the README, and the plan move.
- **CRITICAL: run `bash tests/run.sh` before committing** — expect 44 passed, 0 failed.
- **CRITICAL: update this plan file if scope changes during implementation.**

## Technical Details

### What the measurement showed, and which change each number motivates

Measured 2026-09-10 across 111 `plan-review` agent transcripts (44 distinct plans) under `~/.claude/projects/*/*/subagents/*.jsonl`:

| Observation | Change it motivates |
|---|---|
| Peak review context median **108K**; of that, the prompt + plan read is only **28K** (the plan file itself ≈ 10K tokens / 42KB median) and **79K** is codebase investigation across ~12 file reads | The review is expensive because of *verification*, not freshness. Moving the reading upstream is not extra cost. |
| **69%** of round-1 CRITICAL findings (n=124) cite a concrete `file:line` in the repo; **24%** are wrong helper signatures, fixtures, or existing assertions in files the plan itself listed under Modify; **32%** are other unread existing source; **13%** vendoring/`go.mod` reality; only **31%** are plan-internal logic | Task 1: read what you modify. This is the single largest class and it is not a judgment failure. |
| **116** of 296 round-1 findings were tagged MECHANICAL (grep-provable) | Tasks 3–4: clear those with Haiku before the Opus round. |
| Of 569 fixes the reviewer issued verdicts on in later rounds: 498 correct, **45 incomplete, 26 introduced a new problem**; 24 of 60 round-2+ reviews caught at least one bad fix | Task 5: the fix step verifies its own edits. Round 2 is largely finding what the fixer broke, not what round 1 missed. |
| Round-1 criticals: median **2**, mean **2.4**, max 9; 10 of 51 round-1 reviews found zero criticals; 6 approved outright | The reviewer is *not* padding a quota. Deliberately **not** doing: capping the findings list, or softening the reviewer's severity language. |
| Rounds per plan: 18 plans at 3, 18 at 2, 4 at 1, 3 at 4, 1 at 5. Per-plan total review context: median **254K**, p90 **465K**, max **567K** | Round limit stays at 3 (decided): let the upstream fixes reduce rounds on their own so next week's re-measurement shows a real drop rather than a cap forcing one. |

### Why the pre-pass is a pre-pass and not "round 0"

`plan-review.md` step 8 changes the reviewer's behavior for `round > 1`: it narrows the expensive checks to whatever the last round's fixes touched, on the grounds that round 1 already covered everything else. If the mechanical pass were numbered as a round, the first *reasoned* round would arrive as `round 2` with a fix list and would narrow itself against a plan no reasoned review had ever seen — the opposite of the intent. So:

- the pre-pass is addressed as `Mode: mechanical` with no round number,
- it does not increment or consume the 1–3 round budget,
- its fixes are **not** passed into round 1 as "Fixes applied since last round",
- round 1 still reviews the whole plan, unchanged.

### Why `Read` and not `Grep` for the Modify rule

The failures being prevented are *what a symbol actually is* — a helper's real parameter list, an existing assertion's current expected value, a fixture's real name. A grep for the symbol returns the definition line and hides the signature's second half, the neighbouring helper that already does the job, and the assertion three lines down that the plan will invalidate. Every finding in the measured 24% class would have survived a grep and died on a read.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

⚠️ **Task 8/9 discrepancy:** the plan's own literal text for the `review-plan` row addition and the new mermaid node label both contain the phrase "mechanical pre-pass", so `grep -c "mechanical pre-pass" README.md` returns 2, not the 1 the plan's verification steps expect. Both insertions were made exactly as the plan specified, verbatim — the count mismatch is in the plan's own verification step, not in either inserted text. Left both as specified rather than reworded to force the count, since reworking either would deviate from this plan's literal instructions.

## Implementation Steps

### Task 1: `plan/SKILL.md` — read every file a task will modify

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] In `## Step 2: Create plan file`, insert a new subsection between the end of `### File structure first` (its last line is `This structure informs task decomposition — each task should produce self-contained changes that make sense independently.`) and the `### Dependency contract check` heading:

```markdown
### Read what you will modify

Before writing a task, read **in full** every file that task lists under `Modify`, and every file it lists under `Create` that already exists. Not a grep for the symbol, not the first 50 lines — the whole file. This is not part of Step 0's discovery budget and is not capped by it: discovery decides *what* the plan touches, this pass establishes *what is actually there* in the files it has already decided to touch.

Two things go wrong when this is skipped, and both produce a plan that cannot compile:

- **Helpers and fixtures.** A task writes `newFakeClientBuilder()` when the real signature is `newFakeClientBuilder(t, scheme)`, or declares a helper that already exists in the same package. Before writing any test code, read the existing test files in that same package — the ones the new tests will sit beside — and reuse their real fixture and helper names, with their real parameter lists.
- **Existing assertions.** A task changes behavior that an existing test already pins (a returned `Result{}`, a status reason, an error string) and never lists the assertion as needing an update. Any test currently asserting on behavior a task changes is itself a `Modify` target — find those assertions while reading, and give each one an explicit checklist item.

If a file is genuinely too large to hold, that is a signal to narrow the task's scope, not to skim the file.
```

- [ ] Update Step 0's cap so it does not contradict the new pass. Change:

  ```markdown
   **CRITICAL: do NOT launch an Agent or read more than 5 files in this step.**
  ```

  to:

  ```markdown
   **CRITICAL: do NOT launch an Agent or read more than 5 files in this step.** This cap is on *discovery* only — Step 2's "Read what you will modify" pass is separate and uncapped.
  ```

- [ ] In `## Step 2.5: Self-review`, replace item 3 so it checks against the files just read rather than only within the plan. Change:

  ```markdown
  3. **Type consistency** — do method signatures and names used in later tasks match what's defined in earlier tasks? A function called `ParseConfig()` in Task 3 but `LoadConfig()` in Task 7 is a bug.
  ```

  to:

  ```markdown
  3. **Type consistency** — do method signatures and names used in later tasks match what's defined in earlier tasks? A function called `ParseConfig()` in Task 3 but `LoadConfig()` in Task 7 is a bug. Then check the same names against the real files: every helper, fixture, and function a task *calls* rather than creates must match the signature in the file you read, and no task may declare something that already exists in that package.
  ```

- [ ] Re-read `plugins/planning/skills/plan/SKILL.md` top to bottom and confirm Step 0's cap, the new Step 2 subsection, and Step 2.5 item 3 agree with each other — nothing claims an unconditional 5-file ceiling, and nothing tells the planner to verify signatures it was never told to read.

### Task 2: `plan/SKILL.md` — widen the dependency-contract check to what tests call

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] In `### Dependency contract check`, the first line currently reads:

  ```markdown
  Otherwise, before writing tasks: identify every external function, method, or API the plan's correctness depends on — things the plan will CALL, not things it will CREATE. For each one:
  ```

  Leave it as is, and after the existing paragraph `In deep-discovery mode (Step 0), widen this to every dependency any task actually calls — not a fixed 3–6 count. A function reused across several tasks needs verifying once; a wrong assumption about it otherwise silently reproduces itself into every task that calls it.` insert:

```markdown

Test-only helpers count as dependencies. A fixture, builder, or assertion helper the plan's test code calls is a function the plan's correctness depends on, even though it never ships — and it is the single most common place plans go wrong. It does not need a "Verified Dependency Behaviors" entry (that section is for shipped behavior), but its real signature does need to be right in every task that calls it.
```

### Task 3: `plan-review.md` — add a mechanical-only mode

**Files:**
- Modify: `plugins/planning/agents/plan-review.md`

- [ ] Immediately after the line `The invoking prompt tells you which plan file to review and the round number. For round > 1, it also gives you a list of fixes applied since the last round, each as `[finding] → [what you did]`.` insert:

```markdown

**`Mode: mechanical`** — when the prompt carries this line instead of a round number, you are the cheap pre-pass that runs before the first full review. Do only what a command can prove:

- Run steps 1–3 (read the plan, read `CLAUDE.md`, identify the files it touches), then **skip steps 4–7 entirely** — no reading dependency bodies, no error tracing, no precondition walking, no multi-phase state.
- From the checklist, run only the items that produce MECHANICAL findings: Decision conflict, Comment Hygiene, and any stale identifier, wrong count, or location the plan failed to update.
- Report **only** MECHANICAL findings, each with its `verify:` command, under `### Critical Issues` and `### Important Issues` as usual.
- Emit **no** `### Verdict` section and no APPROVE/NEEDS REVISION line — you are not judging the plan, only clearing the cheap findings out of the way. If you find nothing, say so in the Summary and stop.
- Anything that needs judgment is out of scope here even if you notice it. Do not report it; the reasoned round that follows will.
```

- [ ] In the output-format block, after the line `### Fix verdicts (round > 1 only)` and its `[omit section if round == 1 ...]` note, and before `### Verdict`, the structure stays as is. Add a note directly under the closing fence of the output-format block:

```markdown

In `Mode: mechanical`, omit `### Fix verdicts` and `### Verdict`; the rest of the structure is unchanged, with `(round ROUND)` in the title replaced by `(mechanical pre-pass)`.
```

### Task 4: `review-plan/SKILL.md` — run the mechanical pre-pass before round 1

**Files:**
- Modify: `plugins/planning/skills/review-plan/SKILL.md`

- [ ] Insert a new step between `## Step 0: Find the plan file` and `## Step 1: Spawn review agent`:

```markdown
## Step 0.5: Mechanical pre-pass

Run once per plan, before the first review round, without asking which model — this one is always Haiku. Roughly 40% of round-1 findings in the measured history were grep-provable; clearing them here means the reasoned round spends its context on judgment instead of stale identifiers.

Use the Agent tool with `subagent_type: planning:plan-review` and `model: "haiku"`, passing:

```
Plan file: PLAN_FILE
Mode: mechanical
```

Print its report verbatim as your own chat message, same as Step 2 requires for a full round. Then apply every finding with the Edit tool and re-run each finding's own `verify:` command, fixing anything that still fails before continuing.

Then go to Step 1 with the round counter at **1**. The pre-pass is not a round: it does not consume the 1–3 budget, and its fixes are **not** passed into round 1 as "Fixes applied since last round" — round 1 is still the first reasoned look at the whole plan, and telling the reviewer otherwise would make it narrow itself per step 8 of its own instructions.

Skip this step only when re-entering the loop from Step 5's "Run auto-review" — it has already run for this plan.
```

- [ ] In `## Step 1: Spawn review agent`, the first line currently reads `Track the current round (start at 1, max 3).` Change it to:

```markdown
Track the current round (start at 1, max 3 — the Step 0.5 pre-pass is not counted).
```

### Task 5: `review-plan/SKILL.md` — the fix step verifies its own edits

**Files:**
- Modify: `plugins/planning/skills/review-plan/SKILL.md`

- [ ] In Step 3, under **Fix and re-review**, item 2 currently reads:

  ```markdown
  2. For every MECHANICAL finding, re-run exactly its own `verify:` command and compare against the expected result — not a broader rescan of the whole plan "while you're at it." Do this silently alongside applying the fixes, not as an announced separate step; only surface it if a result doesn't match what the finding expected. Any that still fail must be fixed before continuing — do not spawn a new round with an unverified mechanical fix.
  ```

  Replace it with:

  ```markdown
  2. For every MECHANICAL finding, re-run exactly its own `verify:` command and compare against the expected result — not a broader rescan of the whole plan "while you're at it." Do this silently alongside applying the fixes, not as an announced separate step; only surface it if a result doesn't match what the finding expected. Any that still fail must be fixed before continuing — do not spawn a new round with an unverified mechanical fix.
  3. For every REASONED finding, check your own fix before moving on: read the source the fix now claims something about, and confirm the claim holds. A fix that rewrites a call must match the real signature in the file; a fix that changes an expected value must match what the code actually returns. Of the fixes measured across this loop's history, 45 were later judged incomplete and 26 had introduced a new problem — the next round is not the place to discover that. If a fix touches a task other than the flagged one, re-read that task in full too. Do this silently; surface only what you had to correct.
  ```

- [ ] The two items that followed (`3.` and `4.`) must be renumbered to `4.` and `5.`. Their text is unchanged:

  ```markdown
  4. If **every** finding in this round was MECHANICAL (no REASONED findings at all): do not spawn a new agent round. All fixes are now verified by command, which is strictly stronger evidence than another read of the plan. Report the verify results to the user and go to Step 5.
  5. Otherwise (at least one REASONED finding was present): increment the round counter, and go to Step 1. Pass the fix list from step 1 into the round prompt as "Fixes applied since last round" — this is what step 8 of the reviewer's instructions and the "Fix verdicts" output section require.
  ```

- [ ] Confirm nothing else in the file refers to those items by number:

  Run: `grep -n "step 1\|item 1\|steps 1-4\|step 2\b" plugins/planning/skills/review-plan/SKILL.md`
  Expected: the only hit inside Step 3's fix list is the existing "Pass the fix list from step 1" in the renumbered item 5, which still points at the fix-applying item — correct as written. If any other numeric cross-reference appears, update it.

### Task 6: Commit the measurement as a re-runnable baseline

**Files:**
- Create: `docs/analysis/measure-review-rounds.py`
- Create: `docs/analysis/2026-09-10-plan-review-loop-measurement.md`

- [ ] Create `docs/analysis/measure-review-rounds.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Measure planning:review-plan loop cost from Claude Code subagent transcripts.

Reads ~/.claude/projects/*/*/subagents/*.jsonl, keeps the transcripts whose
first user message looks like a plan-review dispatch, and reports per-round
findings, context cost, and fix-verdict outcomes.

Usage:
    python3 docs/analysis/measure-review-rounds.py
    python3 docs/analysis/measure-review-rounds.py --since 2026-09-10
"""

import argparse
import collections
import glob
import json
import os
import re
import statistics as st

SECTIONS = ("Critical Issues", "Important Issues", "Minor Issues")


def text_of(content):
    if isinstance(content, str):
        return content
    return "\n".join(
        b.get("text", "")
        for b in content or []
        if isinstance(b, dict) and b.get("type") == "text"
    )


def load(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    return rows


def section(report, name):
    m = re.search(r"###\s*" + name + r"\s*\n(.*?)(?=\n###|\Z)", report, re.S)
    return m.group(1) if m else ""


def numbered(body):
    return [s.strip() for s in re.split(r"\n(?=\s*\d+\.\s)", body) if s.strip()]


def classify(finding):
    if re.search(r"_test\.go|test file|existing test", finding):
        return "existing tests / helpers / fixtures"
    if re.search(r"vendor/|pkg/mod|go\.mod|modules\.txt", finding):
        return "dependency or vendoring reality"
    if re.search(r"\b[\w/.-]+\.(go|ya?ml|md|sql|ts|js|py)[`'\"]?:\d+", finding):
        return "existing source it did not read"
    return "plan-internal (logic, scope, missing steps)"


def parse(path):
    rows = load(path)
    if not rows:
        return None

    prompt = ""
    for r in rows:
        if r.get("type") == "user":
            prompt = text_of((r.get("message") or {}).get("content"))
            break
    if "Review round:" not in prompt and "Mode: mechanical" not in prompt:
        return None

    m = re.search(r"Review round:\s*(\d+)", prompt)
    rnd = int(m.group(1)) if m else 0  # 0 == mechanical pre-pass
    m = re.search(r"Plan file:\s*(\S+)", prompt)
    plan = os.path.basename(m.group(1)) if m else "?"

    report = ""
    for r in reversed(rows):
        if r.get("type") == "assistant":
            t = text_of((r.get("message") or {}).get("content"))
            if t.strip():
                report = t
                break

    counts = {s: len(numbered(section(report, s))) for s in SECTIONS}
    criticals = numbered(section(report, "Critical Issues"))
    verdicts = section(report, r"Fix verdicts.*?")

    first_ctx = peak_ctx = out = 0
    ctx_after_plan = None
    saw_result = False
    for r in rows:
        msg = r.get("message") or {}
        usage = msg.get("usage") or {}
        if usage:
            ctx = (
                usage.get("input_tokens", 0)
                + usage.get("cache_creation_input_tokens", 0)
                + usage.get("cache_read_input_tokens", 0)
            )
            first_ctx = first_ctx or ctx
            peak_ctx = max(peak_ctx, ctx)
            out += usage.get("output_tokens", 0)
            if saw_result and ctx_after_plan is None:
                ctx_after_plan = ctx
        content = msg.get("content")
        if isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    saw_result = True

    tools = collections.Counter()
    for r in rows:
        content = (r.get("message") or {}).get("content")
        if isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    tools[b.get("name")] += 1

    return dict(
        path=path,
        project=path.split(os.sep)[-4],
        plan=plan,
        round=rnd,
        critical=counts["Critical Issues"],
        important=counts["Important Issues"],
        minor=counts["Minor Issues"],
        criticals=criticals,
        mechanical=len(re.findall(r"\[MECHANICAL\]", report)),
        reasoned=len(re.findall(r"\[REASONED\]", report)),
        approve=bool(re.search(r"\*\*APPROVE\*\*", report)),
        fix_correct=len(re.findall(r"\*\*correct\*\*", verdicts)),
        fix_incomplete=len(re.findall(r"\*\*incomplete\*\*", verdicts)),
        fix_broke=len(re.findall(r"introduced a new problem", verdicts)),
        first_ctx=first_ctx,
        ctx_after_plan=ctx_after_plan or 0,
        peak_ctx=peak_ctx,
        output=out,
        reads=tools["Read"],
        greps=tools["Grep"],
    )


def med(values):
    return round(st.median(values)) if values else 0


def pct(part, whole):
    return round(100 * part / whole) if whole else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--root",
        default=os.path.expanduser("~/.claude/projects"),
        help="Claude Code projects directory",
    )
    ap.add_argument(
        "--since",
        help="only transcripts modified on or after this date (YYYY-MM-DD)",
    )
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(args.root, "*", "*", "subagents", "*.jsonl")))
    if args.since:
        import datetime

        cutoff = datetime.date.fromisoformat(args.since)
        paths = [
            p
            for p in paths
            if datetime.date.fromtimestamp(os.path.getmtime(p)) >= cutoff
        ]

    recs = [r for r in (parse(p) for p in paths) if r]
    if not recs:
        print("no plan-review transcripts found")
        return

    plans = {(r["project"], r["plan"]) for r in recs}
    print(f"{len(recs)} review transcripts over {len(plans)} plans")
    if args.since:
        print(f"(filtered to transcripts modified on or after {args.since})")
    print()

    print("per round:")
    for rnd in sorted({r["round"] for r in recs}):
        g = [r for r in recs if r["round"] == rnd]
        label = "pre-pass" if rnd == 0 else f"round {rnd}"
        print(
            f"  {label:9s} n={len(g):3d}  crit_med={med([r['critical'] for r in g]):2d}"
            f"  imp_med={med([r['important'] for r in g]):2d}"
            f"  peak_ctx_med={med([r['peak_ctx'] for r in g]) // 1000:4d}K"
            f"  reads_med={med([r['reads'] for r in g]):3d}"
            f"  approve={sum(1 for r in g if r['approve']):3d}"
        )
    print()

    first = [r for r in recs if r["round"] == 1]
    if first:
        crit = [r["critical"] for r in first]
        print(
            f"round-1 criticals: median {med(crit)}  mean {st.mean(crit):.1f}"
            f"  max {max(crit)}  zero-critical reviews {sum(1 for c in crit if c == 0)}/{len(crit)}"
        )
        after = [r["ctx_after_plan"] for r in first if r["ctx_after_plan"]]
        peak = [r["peak_ctx"] for r in first if r["peak_ctx"]]
        if after and peak:
            print(
                f"context: prompt+plan {med(after) // 1000}K -> peak {med(peak) // 1000}K"
                f"  (investigation adds {(med(peak) - med(after)) // 1000}K)"
            )
        print(
            f"finding tags: {sum(r['mechanical'] for r in first)} MECHANICAL,"
            f" {sum(r['reasoned'] for r in first)} REASONED"
        )
        print()

        cats = collections.Counter()
        for r in first:
            for finding in r["criticals"]:
                cats[classify(finding)] += 1
        total = sum(cats.values())
        print(f"round-1 critical findings by root cause (n={total}):")
        for name, n in cats.most_common():
            print(f"  {name:42s} {n:4d}  ({pct(n, total):2d}%)")
        grounded = total - cats["plan-internal (logic, scope, missing steps)"]
        print(f"  -> cite a concrete repo file:line: {pct(grounded, total)}%")
        print()

    ok = sum(r["fix_correct"] for r in recs)
    inc = sum(r["fix_incomplete"] for r in recs)
    broke = sum(r["fix_broke"] for r in recs)
    later = [r for r in recs if r["round"] > 1]
    hit = sum(1 for r in later if r["fix_broke"])
    print(
        f"fix verdicts: {ok} correct, {inc} incomplete, {broke} introduced a new problem"
        f"  ({pct(inc + broke, ok + inc + broke)}% bad of {ok + inc + broke})"
    )
    print(f"  reviews catching a fix that broke something: {hit}/{len(later)}")
    print()

    per_plan = collections.Counter()
    ctx_per_plan = collections.Counter()
    for r in recs:
        key = (r["project"], r["plan"])
        per_plan[key] += 1
        ctx_per_plan[key] += r["peak_ctx"]
    rounds = sorted(per_plan.values())
    totals = sorted(ctx_per_plan.values())
    print(f"rounds per plan: {dict(collections.Counter(rounds))}")
    print(
        f"review context per plan: median {med(totals) // 1000}K"
        f"  p90 {totals[int(len(totals) * 0.9)] // 1000}K"
        f"  max {max(totals) // 1000}K"
    )


if __name__ == "__main__":
    main()
```

- [ ] Make it executable: `chmod +x docs/analysis/measure-review-rounds.py`

- [ ] Run it and confirm it reproduces the baseline:

  Run: `python3 docs/analysis/measure-review-rounds.py`
  Expected: `111 review transcripts over 44 plans` (or more, if new reviews have run since), a round-1 critical median of `2`, a root-cause table whose `plan-internal` share is near 31%, and a fix-verdict line reading `498 correct, 45 incomplete, 26 introduced a new problem`. If the counts differ because more reviews have run, that is expected — record the new numbers in the note below rather than forcing the old ones.

- [ ] Create `docs/analysis/2026-09-10-plan-review-loop-measurement.md` with this content:

```markdown
# Plan-Review Loop: Baseline Measurement

**Measured:** 2026-09-10
**Sample:** 111 `planning:plan-review` subagent transcripts across 44 distinct plans, drawn from private work repositories over roughly the preceding month. The two largest contributors account for most of the sample, so the figures lean toward Go/Kubernetes work with heavy table-driven test suites.
**Tool:** `docs/analysis/measure-review-rounds.py` (stdlib Python 3, no arguments needed).
**Plugin versions in force at measurement time:** `planning 1.18.2`. Every transcript in this sample predates the changes made in `planning 1.19.0`.

## How it was measured

The script globs `~/.claude/projects/*/*/subagents/*.jsonl` and keeps transcripts
whose first user message contains `Review round:` (or, going forward,
`Mode: mechanical`). For each it parses the round number and plan filename from
the dispatch prompt, and the findings from the last assistant message — counting
numbered items under `### Critical Issues`, `### Important Issues` and
`### Minor Issues`, and the `**correct**` / `**incomplete**` /
`introduced a new problem` lines under `### Fix verdicts`.

Context cost is `input_tokens + cache_creation_input_tokens +
cache_read_input_tokens` on each usage-bearing message: the value on the first
message is prompt + system, the value on the first message after a tool result
is prompt + plan, and the maximum over the transcript is the peak.

Critical findings are bucketed by root cause with the regexes in `classify()`:
a mention of `_test.go` or "existing test" first, then `vendor/`/`go.mod`, then
any `path.ext:NN` citation, and whatever matches none of those is treated as
plan-internal. The buckets are heuristic — they are stable enough to compare
across runs, but a single finding may be filed under the wrong one.

## Baseline numbers

| Metric | Value |
|---|---|
| Review transcripts / distinct plans | 111 / 44 |
| Rounds per plan | 18 plans at 3, 18 at 2, 4 at 1, 3 at 4, 1 at 5 |
| Round-1 criticals | median 2, mean 2.4, max 9; 10 of 51 found none; 6 approved outright |
| Round-1 critical+important | mean 6.0, max 18 |
| Context: prompt + system | ~10K |
| Context: prompt + plan read | 28K median (plan file ≈ 10K tokens, 42KB) |
| Context: peak | 108K median, ~12 file reads |
| Investigation share of peak | 79K — the plan itself is not what costs |
| Round-1 findings tagged MECHANICAL / REASONED | 116 / 180 |
| Review context per plan, whole loop | median 254K, p90 465K, max 567K |

### Round-1 critical findings by root cause (n=124)

| Root cause | Share |
|---|---|
| Existing source the plan never read (cites `file:line`) | 32% |
| Existing test helpers/fixtures/assertions in files the plan itself listed as Modify | 24% |
| Dependency / vendoring reality (`vendor/`, `go.mod`) | 13% |
| Plan-internal — logic gaps, scope, missing steps | 31% |

69% cite a concrete `file:line` in the repo — facts the planner did not have,
not blind spots a second reader fixes.

### Fix quality across later rounds

Of 569 fixes the reviewer issued verdicts on: **498 correct, 45 incomplete, 26
introduced a new problem** (12.5% bad). 24 of 60 round-2+ reviews caught at
least one bad fix — so round 2 is substantially finding what the fixer broke,
not what round 1 missed.

## What was changed in response

`planning 1.19.0` — see `CHANGELOG.md` for the full entry:

1. `plan` reads in full every file a task lists under Create/Modify, plus the
   sibling test files any new test code reuses, before writing that task.
2. `review-plan` runs a Haiku mechanical pre-pass before round 1.
3. `review-plan`'s fix step verifies its own REASONED fixes against source.

Deliberately not changed: the round limit (still 3), the reviewer's severity
language, and the size of the findings list. The reviewer was measured as
well-calibrated — a median of 2 criticals, with a fifth of round-1 reviews
finding none — so capping or softening it would lose real findings without
addressing the cause.

## Re-measuring

Re-run once there is enough new data:

    python3 docs/analysis/measure-review-rounds.py --since 2026-09-11

The `--since` filter keeps pre-change transcripts out of the comparison; drop it
to see the whole history.

**When there is enough.** Sample size matters more than elapsed time. The
baseline's headline figures rest on 51 round-1 reviews over roughly a month, and
the medians there move visibly on a single unusually messy plan. Wait for at
least **15 plans** to have gone through the loop post-change — the script's first
line reports the plan count, so re-run it whenever and read that number before
reading anything else. Under 15 plans, treat every figure below as directional
only. A week of normal use has historically produced about that many.

What to compare, in order of what would actually settle whether this worked:

1. **Rounds per plan** — the headline. Baseline is 18 plans at 3 rounds and 18
   at 2. A drop in the 3+ bucket is the win.
2. **Root-cause mix of round-1 criticals** — the "existing tests / helpers /
   fixtures" bucket should shrink toward zero. If it does not, the Modify-read
   rule is not being followed, which is a different problem from it not working.
3. **Bad-fix rate** — the 45 incomplete + 26 broke figures should fall.
4. **Peak context per round** — expected to stay near 108K. The reading moved
   upstream, it did not disappear, so this staying flat is the neutral result,
   not a failure.
5. **Whether the pre-pass still earns its place.** The Modify-read rule and the
   mechanical pre-pass overlap on purpose: a task written against a file that was
   actually read should not carry a stale identifier for the pre-pass to find. If
   the pre-pass starts reporting nothing on most plans, that is the Modify-read
   rule working, and the pre-pass becomes a Haiku spawn per plan buying nothing —
   drop it then. Judge this from the pre-pass's own finding counts (the script
   reports them on the `pre-pass` row), not from the round-1 totals.

Numbers alone will not settle it. Record the owner's own impression of whether
review rounds felt shorter alongside the figures — the sample is small enough
that one unusually messy plan moves every median.
```

### Task 7: Version bump and changelog

**Files:**
- Modify: `plugins/planning/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

- [ ] In `plugins/planning/.claude-plugin/plugin.json`, change `"version": "1.18.2"` to `"version": "1.19.0"` (minor — new behavior in two skills and one agent).
- [ ] In `CHANGELOG.md`, insert this section immediately above the existing `## planning 1.18.2 - 2026-09-09` heading:

```markdown
## planning 1.19.0 - 2026-09-10

`plan` now reads, in full, every existing file a task lists under Create or
Modify before writing that task — plus the sibling test files any new test code
will reuse. Step 0's 5-file discovery cap is explicitly scoped to discovery and
no longer caps this pass. Test helpers and fixtures are called out as
dependencies whose real signatures have to be right, and Step 2.5's
type-consistency check now compares names against those real files rather than
only against other tasks.

`review-plan` gains a Haiku mechanical pre-pass (Step 0.5) that clears
grep-provable findings before the first reasoned round. It is deliberately not
numbered as a round: it does not consume the 1–3 budget and its fixes are not
passed into round 1 as a fix list, because `plan-review.md`'s step 8 would then
narrow round 1 against a plan nothing had reasoned over. The agent gained a
matching `Mode: mechanical` that skips its four expensive verification steps and
emits no verdict.

`review-plan`'s fix step now verifies its own REASONED fixes against the source
they make claims about, instead of leaving that to the next round.

Measured from 111 review transcripts across 44 plans (see
`docs/analysis/2026-09-10-plan-review-loop-measurement.md`, and
`docs/analysis/measure-review-rounds.py` to re-run it): 69% of round-1 critical
findings cite a concrete `file:line` in the repo, and 24% are wrong helper
signatures, fixtures, or stale assertions in files the plan itself listed as
Modify. Peak review context is 108K median, of which only 28K is the prompt plus
the plan — the other 79K is codebase reading the planner could have done first.
116 of 296 round-1 findings were grep-provable. Of 569 fixes the reviewer later
judged, 45 were incomplete and 26 had introduced a new problem.

The round limit stays at 3 and the reviewer's severity language is untouched: at
a median of 2 criticals per round-1 review, with a fifth finding none, it was
measured as well-calibrated. Capping the findings list would have lost real
findings without touching the cause.
```

### Task 8: README

**Files:**
- Modify: `README.md`

- [ ] Append to the `plan` row (line 81), after the existing sentence ending `...deep-discovery mode for multi-plan/large-feature work.`:

```markdown
 Before writing a task, it reads in full every existing file that task lists under Create/Modify — plus the sibling test files any new test code reuses — so tasks are written against real helper signatures and existing assertions rather than guessed ones.
```

- [ ] In the `review-plan` row (line 82), insert the following immediately before the row's final sentence — the one beginning ` Invoke on any plan:` — so the invocation example stays last:

```markdown
A Haiku mechanical pre-pass runs once before the first round and clears the grep-provable findings, without consuming the 3-round budget. The fix step verifies its own reasoned fixes against the source they make claims about, rather than leaving that for the next round.
```

- [ ] In the `**`plan` — flow**` mermaid diagram, node `J` currently reads `create plan + dependency check + self-review`. Change it to:

```
    H --> J["create plan + read modify targets + dependency check + self-review"]
```

- [ ] In the `**`review-plan` — flow**` mermaid diagram, node `A` currently reads `find plan file` and flows to `B`. Change that first edge to route through the pre-pass:

```
    A["find plan file"] --> A2["Haiku mechanical pre-pass — fix + verify"]
    A2 --> B["ask review model → spawn review agent — Round N"]
```

  Verify the diagram still parses as valid mermaid by eye: `A2` is declared once with its label, referenced once bare, and `B` keeps its original label on its first appearance.

- [ ] Confirm the README mentions the new behavior:

  Run: `grep -c "mechanical pre-pass" README.md`
  Expected: 1

### Task 9: Verify acceptance criteria

**Files:**
- None (read-only verification)

- [ ] One assertion per edit, confirming each landed exactly once:

  Run: `grep -c "### Read what you will modify" plugins/planning/skills/plan/SKILL.md` — Expected: 1
  Run: `grep -c "This cap is on \*discovery\* only" plugins/planning/skills/plan/SKILL.md` — Expected: 1
  Run: `grep -c "Test-only helpers count as dependencies" plugins/planning/skills/plan/SKILL.md` — Expected: 1
  Run: `grep -c "no task may declare something that already exists in that package" plugins/planning/skills/plan/SKILL.md` — Expected: 1
  Run: `grep -c "Mode: mechanical" plugins/planning/agents/plan-review.md` — Expected: 2 (the mode heading, and the output-format note under it)
  Run: `grep -c "## Step 0.5: Mechanical pre-pass" plugins/planning/skills/review-plan/SKILL.md` — Expected: 1
  Run: `grep -c "the Step 0.5 pre-pass is not counted" plugins/planning/skills/review-plan/SKILL.md` — Expected: 1
  Run: `grep -c "For every REASONED finding, check your own fix" plugins/planning/skills/review-plan/SKILL.md` — Expected: 1
  Run: `grep -c '"version": "1.19.0"' plugins/planning/.claude-plugin/plugin.json` — Expected: 1
  Run: `grep -c "^## planning 1.19.0" CHANGELOG.md` — Expected: 1
  Run: `grep -c "mechanical pre-pass" README.md` — Expected: 1

- [ ] Confirm the fix-list renumbering is complete and has no duplicate or missing ordinal:

  Run: `grep -nE "^  [0-9]+\. " plugins/planning/skills/review-plan/SKILL.md`
  Expected: within Step 3's "Fix and re-review" block, exactly items `1.` through `5.` in order, each appearing once.

- [ ] Confirm `plugin.json` is still valid JSON:

  Run: `python3 -m json.tool plugins/planning/.claude-plugin/plugin.json > /dev/null && echo ok`
  Expected: `ok`

- [ ] Confirm the new script runs clean and its `--since` path works:

  Run: `python3 docs/analysis/measure-review-rounds.py | head -20`
  Expected: exits 0, prints the transcript/plan counts and the per-round table.

  Run: `python3 docs/analysis/measure-review-rounds.py --since 2026-09-11`
  Expected: exits 0. Today is 2026-09-10, so this prints `no plan-review transcripts found` — that is the correct output, and it proves the flag the re-measurement instructions depend on actually parses.

- [ ] Re-read all three edited instruction files top to bottom, in this order: `plugins/planning/skills/plan/SKILL.md`, `plugins/planning/agents/plan-review.md`, `plugins/planning/skills/review-plan/SKILL.md`. Check specifically that:
  - nothing in `plan/SKILL.md` still implies a flat 5-file ceiling on all reading
  - `plan-review.md`'s `Mode: mechanical` block does not contradict its own steps 4–7 or its output-format block
  - `review-plan/SKILL.md`'s Step 0.5, Step 1's round counter, and Step 3's renumbered items agree on what a "round" is
- [ ] Run the project's test suite: `bash tests/run.sh` — Expected: `Results: 44 passed, 0 failed`. Nothing in this plan touches shell scripts or hooks, so a change here means something unrelated broke.

### Task 10: Wrap up and commit

**Files:**
- None beyond what earlier tasks modified

- [ ] Check the branch is not behind its remote: `git fetch && git status -sb` — resync with `git pull --rebase` if behind.
- [ ] Move this plan to `docs/plans/completed/`: `mkdir -p docs/plans/completed && mv docs/plans/2026-09-10-planner-reads-what-it-modifies.md docs/plans/completed/`
- [ ] Single summary commit: the three instruction files, the two new `docs/analysis/` files, the version bump, the changelog, the README, and the plan move — one commit, no `Co-authored-by` line.
- [ ] Do **not** stage `HACKING.md`, `analytics.json`, or `docs/plans/2026-08-28-block-search-dump-hook.md` — all three are pre-existing untracked files unrelated to this change.
- [ ] Ask before opening a PR — this is a tooling change to a personal marketplace repo, not application code, and previous changes here landed as direct commits to `main`.

## Post-Completion
*Items requiring manual intervention or external systems*

- **The installed plugin copy is stale until reinstall.** `planning:plan-review` resolves from `~/.claude/plugins/cache/parmaster-claude-dlc/planning/<version>/`, currently `1.18.1` — older than this repo even before this change. Nothing in this plan can exercise the edited agent in-session. To check the live behavior, run `claude --plugin-dir plugins/planning` in a fresh session after the commit lands and spawn a review from there.
- **The real test is real use.** Re-run `python3 docs/analysis/measure-review-rounds.py --since 2026-09-11` once at least 15 plans have gone through the loop (the script's first line reports the plan count) and compare against the baseline table, following the five comparisons listed in the measurement note. Rounds per plan is the headline; peak context per round staying flat at ~108K is the expected neutral result, since the reading moved upstream rather than disappearing. One of the five is whether the mechanical pre-pass still finds anything — if the Modify-read rule absorbs its findings, the pre-pass should be dropped rather than kept out of habit.
- **If the "existing tests / helpers / fixtures" bucket does not shrink**, the conclusion is that the Modify-read rule is not being followed, not that it does not work — and per this repo's "Enforcement: Harness Before Prose" doctrine, the next step would be a mechanism rather than more prose. There is no obvious one for "read the file before writing about it", which is why this round is prose; a `PreToolUse` hook that blocks a `Write` to `docs/plans/` when the session has not read the files the plan names is the shape it would take, and is out of scope here.
