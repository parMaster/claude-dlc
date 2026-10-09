# Readability report

`readability.py` checks whether the global-rules `style-reminder` hook keeps replies readable as a session grows.

## Why

Late in a session, replies used to turn dense. Sentences got long and packed several ideas. They had stacked nouns and dropped small words like "the" and "so". The rules in CLAUDE.md load once at session start, and they lose weight as the context fills up.

The `style-reminder` hook (global-rules 1.11.0, 2026-10-09) repeats the core rules with every prompt. This report shows whether that helps.

## What it measures

The script reads local session history in `~/.claude/projects`. It splits it at a cutoff time, by default the commit that added the hook. It then groups replies by the context size at the time they were written.

| Number | What it shows | Good direction |
|---|---|---|
| Words per sentence | Average sentence length | Lower, and flat across context sizes |
| Sentences over 25 words | Share of sentences that break the rule | Lower |
| Small words | Share of a, an, the, because, so, then, but, if, when, which, that | Higher, and flat across context sizes |
| Complaints per 100 prompts | Your messages about walls of text, word salad, jargon or confusion | Lower |

The main signal is the shape across context sizes. Before the hook, sentences got longer and small words got rarer as the context grew. Success means those lines stay flat.

## Caveats

- The report skips code blocks, tables, quotes and indented diagrams. It counts each list item as a sentence.
- Complaints come from a keyword search, so a few hits are false. Compare the trend, not single counts.
- Subagent transcripts are excluded. Only replies in the main conversation count.
- A small "after" sample means little. Wait for a few hundred replies in each context group.

## Run

```
python3 tools/readability.py                  # cutoff = the hook's commit
python3 tools/readability.py 2026-10-16T00:00  # any other cutoff
```

## History

Add a row after each run. "After" rows count only replies since the cutoff.

| Date | Period | Context | Replies | Words/sentence | Over 25 words | Small words | Complaints per 100 prompts | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-10-09 | before | <50k | 122 | 13.3 | 5.9% | 12.8% | 2.8 (31 / 1107) | Baseline, Aug–Oct 9 |
| 2026-10-09 | before | 50–150k | 2605 | 14.0 | 11.8% | 12.1% | | |
| 2026-10-09 | before | 150k+ | 2284 | 15.0 | 14.7% | 11.1% | | |
| 2026-10-09 | after | 50–150k | 13 | 12.8 | 1.1% | 14.3% | 0.0 (0 / 11) | First hours, one session; too small to judge |
