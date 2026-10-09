#!/usr/bin/env bash
# UserPromptSubmit hook: repeats the readability rules next to each prompt.
# Rules loaded once at session start lose weight as the context grows, and
# replies turn dense; a reminder at the end of the context holds them.

echo "Reply style: answer first. One idea per sentence, at most 25 words. No stacks of more than 3 nouns. Keep the small words: a, the, because, so, then. Put 3+ related points in a list. Draw a flow instead of describing it."
