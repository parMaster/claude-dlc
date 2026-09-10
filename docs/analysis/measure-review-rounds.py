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
