"""Compare reply readability before and after the style-reminder hook.

Reads local Claude Code session history and prints, per context size, sentence
length, the share of long sentences, the share of small words (a, the, so...),
and complaints about walls of text per 100 prompts.

Usage: python3 tools/readability.py [cutoff ISO time]   (default: the commit that added the hook)
"""
import glob, json, os, re, sys
from collections import defaultdict
from datetime import datetime

ROOT = os.path.expanduser("~/.claude/projects")
CUTOFF = datetime.fromisoformat(sys.argv[1] if len(sys.argv) > 1 else "2026-10-09T12:00:36+03:00")
BUCKETS = [(0, 50_000, "<50k"), (50_000, 150_000, "50-150k"), (150_000, 10**9, "150k+")]
SMALL = {"a", "an", "the", "because", "so", "then", "but", "if", "when", "which", "that"}
COMPLAINT = re.compile(
    r"walls? of text|word salad|plain english|human[- ]readable|hard to read|"
    r"can'?t (read|follow|keep up)|confus|too long|jargon|incomprehensible",
    re.I,
)
WORD = re.compile(r"[A-Za-z][A-Za-z'-]*")


def bucket(ctx):
    return next(name for lo, hi, name in BUCKETS if lo <= ctx < hi)


def prose_sentences(text):
    # Code, tables and diagrams aren't prose; counting them would skew sentence length.
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    lines = [l for l in text.splitlines() if l.strip() and not l.lstrip().startswith(("|", ">", "    "))]
    out = []
    for line in lines:
        line = re.sub(r"^\s*([-*]|\d+\.)\s+", "", line)
        out += [s for s in re.split(r"(?<=[.!?])\s+", line) if s.strip()]
    return out


def user_text(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list) and not any(isinstance(p, dict) and p.get("type") == "tool_result" for p in c):
        return " ".join(p.get("text", "") for p in c if isinstance(p, dict) and p.get("type") == "text")
    return None


# stats[period][bucket] = [replies, sentences, words, long_sentences, small_words]
stats = defaultdict(lambda: defaultdict(lambda: [0, 0, 0, 0, 0]))
prompts, complaints = defaultdict(int), defaultdict(int)

for path in glob.glob(f"{ROOT}/*/*.jsonl"):
    ctx = 0
    for line in open(path, errors="ignore"):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        ts = e.get("timestamp")
        if e.get("isSidechain") or e.get("isCompactSummary") or not ts:
            continue
        period = "after" if datetime.fromisoformat(ts.replace("Z", "+00:00")) >= CUTOFF else "before"
        msg, kind = e.get("message") or {}, e.get("type")
        if kind == "assistant":
            u = msg.get("usage") or {}
            ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
            text = " ".join(p.get("text", "") for p in msg.get("content") or [] if isinstance(p, dict) and p.get("type") == "text")
            sents = prose_sentences(text)
            if not sents:
                continue
            s = stats[period][bucket(ctx)]
            s[0] += 1
            for sent in sents:
                words = [w.lower() for w in WORD.findall(sent)]
                s[1] += 1
                s[2] += len(words)
                s[3] += len(words) > 25
                s[4] += sum(w in SMALL for w in words)
        elif kind == "user" and not e.get("isMeta"):
            txt = user_text(msg)
            if not txt or txt.lstrip().startswith(("<", "[Request interrupted")):
                continue
            prompts[period] += 1
            complaints[period] += bool(COMPLAINT.search(txt))

print(f"cutoff: {CUTOFF.isoformat()}\n")
print(f"{'period':8} {'context':8} {'replies':>7} {'avg words/sent':>15} {'% sent >25w':>12} {'% small words':>14}")
for period in ("before", "after"):
    for _, _, name in BUCKETS:
        r, n, w, lng, sm = stats[period][name]
        if not n:
            print(f"{period:8} {name:8} {r:7} {'-':>15} {'-':>12} {'-':>14}")
            continue
        print(f"{period:8} {name:8} {r:7} {w / n:15.1f} {100 * lng / n:11.1f}% {100 * sm / max(w, 1):13.1f}%")
print()
for period in ("before", "after"):
    p = prompts[period]
    rate = f"{100 * complaints[period] / p:.1f}" if p else "-"
    print(f"{period:8} prompts {p:5}  complaints {complaints[period]:3}  per 100 prompts {rate}")
