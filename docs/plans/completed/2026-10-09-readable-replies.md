# Readable replies: STE rules and a per-prompt reminder

**Goal:** Replies stay short and easy to read for the whole session, not just its first 50k tokens.

**Kind of change:** feature

## Intent

Late in a session (roughly 80k–230k of context), replies turn into dense text. Sentences are long and pack several ideas, with noun stacks and dropped small words. The Response Brevity rules sit at the top of the context, loaded once, and lose weight as the context grows. The user then has to ask for a rewrite after the wall of text is already in the context.

This change does two things:

1. It adds readability rules borrowed from ASD-STE100 (Simplified Technical English) to Response Brevity. These rules target dense text directly.
2. It adds a `UserPromptSubmit` hook that repeats a short version of the rules with every prompt. That keeps the rules near the end of the context, where they carry the most weight.

```
before:  [CLAUDE.md rules] ... 150k of plans, reviews, tool output ... [prompt] → dense reply
after:   [CLAUDE.md rules] ... 150k of plans, reviews, tool output ... [prompt + reminder] → reply
```

## Decisions

- **Re-inject on every prompt, with no context-size check.** Past sessions run a median of 2–4 prompts, with a 90th percentile of 14–16. At about 60 tokens a reminder, a long session pays around 1k tokens. That costs less than one rewrite. A check on context size would need the hook to parse the transcript, and the savings would be tiny.
- **No compaction hook.** After a compaction, the next prompt brings the reminder back anyway.
- **The reminder is a short version, not the whole section.** It covers the rules that drift: answer first, one idea per sentence, the 25-word cap, no noun stacks, keep the small words, lists, and draw flows. "Answer first" mostly holds, but it costs only two words. The full rules stay in CLAUDE.md.
- **Plain stdout, like `strict-bash/scripts/session-start.sh`.** For `UserPromptSubmit`, stdout on exit 0 becomes context for that turn. No JSON is needed.
- **Fold the uncommitted 1.10.1 Response Brevity cleanup into this change.** The plugin goes to 1.11.0 (new hook, so a minor bump), with one CHANGELOG entry covering both. The 1.10.1 entry is replaced, not kept beside it, since 1.10.1 was never pushed.
- **Keep the section name "Response Brevity".** It now covers readability too, but renaming it is churn with no gain.
- **Left out of STE:** the controlled dictionary (too strict for technical chat), the ban on "-ing" forms (little gain), and imperative for procedures (already the natural way to write steps).

Reminder text (about 60 tokens). It is the one piece of content worth pinning here:

```
Reply style: answer first. One idea per sentence, at most 25 words. No stacks of more than 3 nouns. Keep the small words: a, the, because, so, then. Put 3+ related points in a list. Draw a flow instead of describing it.
```

Response Brevity after the change. Existing rules are kept, and new rules are marked with ➕:

```
- **Answer first.** ...                          (kept)
- **Size to the question.** ...                  (kept)
- **No opening about yourself.** ...             (kept)
- ➕ **One idea per sentence.** At most 25 words and one technical term. If a sentence needs "and", "which" or a dash to carry a second idea, split it.   (replaces "Short sentences")
- ➕ **No noun stacks.** At most 3 nouns in a row. Not "reconcile loop status update path"; write "the path that updates status in the reconcile loop".
- ➕ **Keep the small words.** Keep articles (a, the) and linking words (because, so, then). Don't drop words to make a sentence shorter.
- ➕ **Verbs for actions.** "Install it", not "do the installation".
- ➕ **Name who acts.** "The operator deletes the pod", not "the pod gets deleted".
- ➕ **Same word, same thing.** Once you name something, keep that name. Don't switch to a synonym.
- **Plain words.** ...                            (kept)
- ➕ **Lists and paragraphs.** Put 3+ related points in a vertical list. A paragraph has one topic and at most 6 sentences.
- **No recap.** / **Long content goes in the file.** / **Draw flows.**   (kept)
```

## Constraints / out of scope

- No check of replies after they are sent (no `Stop` hook) and no second model judging replies.
- The `style:writing-style` skill stays as it is. This change doesn't load or shorten it.
- The other global-rules hooks and `setup.sh` don't change.

## Traps

- The reminder text lives in two places: the hook script and CLAUDE.md. If someone renames a rule in one place, the other goes stale with no error. The DoD test below ties them together.
- `tests/run.sh` has no linter step, and CI runs only `bash tests/run.sh` (`.github/workflows/test.yml`). So the test suite is the only automated gate.

## Definition of Done

- [x] Response Brevity in `plugins/global-rules/CLAUDE.md` holds the rules shown above, and "Short sentences" is merged into "One idea per sentence" — proof: reading the section
- [x] A `UserPromptSubmit` hook in `plugins/global-rules/hooks/hooks.json` prints the reminder and exits 0 for any input, including `{}` — proof: new cases in `tests/run.sh`
- [x] The rules named in the reminder exist in CLAUDE.md — proof: a test case asserts that CLAUDE.md contains "One idea per sentence", "No noun stacks" and "Keep the small words"
- [x] The reminder reaches Claude in a real session — proof: `claude --plugin-dir plugins/global-rules`, send a prompt, and see the reminder as hook context in the transcript (ctrl+o)
- [x] README's global-rules hook table lists the new hook, and the rules summary mentions readability
- [x] global-rules is at 1.11.0, with one CHANGELOG entry covering the cleanup and the hook; the 1.10.1 entry is gone

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] README.md updated
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-10-09-readable-replies.md docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update` and `/reload-plugins` on each machine.
- Watch the next few long sessions. If dense replies still show up after 150k, the next step is a check of replies after they are sent.
