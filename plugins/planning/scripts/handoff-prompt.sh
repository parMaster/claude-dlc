#!/usr/bin/env bash
# Shared canned prompt text for a plan-file hand-off. Sourced (not executed)
# by agterm-handoff.sh and codex-handoff.sh (implementation hand-off, via
# build_handoff_prompt) and by codex-review-handoff.sh (review hand-off, via
# build_review_prompt), so the wording for each can only be defined once and
# can't drift between call sites.

build_handoff_prompt() {
  local plan_file="$1"
  cat <<EOF
You have a new implementation plan to execute: $plan_file

Read it fully, then implement every task in order, following its stated
testing approach. Run the project's tests and linter before treating any
task as done.
EOF
}

build_review_prompt() {
  local plan_file="$1"
  cat <<EOF
You have a new implementation plan to review: $plan_file

Review it thoroughly — check correctness, over-engineering, and test
coverage, apply fixes, and iterate review rounds as needed until it's ready
for implementation or a round limit is reached.
EOF
}
