---
worth: later
added: 2026-11-07
---
# `git -C <abs path>` on every call breaks Bash allow rules

The model often writes `git -C <abs path> <cmd>` even when the session already sits in that repo.
Allow rules shaped like `Bash(git status:*)` don't match that form. A work Team account has auto mode
turned off by the org, so each of these calls asks for permission.

This may be tied to overusing the scratchpad. The model does work on the side there instead of in the
cwd, then points `-C` at the scratchpad path. That link is not confirmed.

Candidate fix: a PreToolUse hook in global-rules that denies `git -C <path>` when the path equals the
hook's `cwd`. Its message would be "drop -C, you're already in that repo". The hook would sit next to
`block-root-find.sh`, with cases in `tests/run.sh`. It does not cover `-C` pointed at the scratchpad.

Unknown that settles it: whether the prompts come from redundant `-C` into the cwd or from `-C` into
the scratchpad. Watch a few sessions on the Team account and note which form triggers the prompt.
