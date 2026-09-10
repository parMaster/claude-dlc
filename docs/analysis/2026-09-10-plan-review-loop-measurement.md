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
