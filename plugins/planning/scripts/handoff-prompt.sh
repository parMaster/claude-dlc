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

Read it fully, then implement it until every Definition of Done item holds,
proven the way the item says. Follow its Decisions and Traps; pick the code
and tests yourself. Tick boxes as they're done, then work through Wrap-up.
EOF
}

build_review_prompt() {
  local plan_file="$1"
  cat <<EOF
You have a new implementation plan to review: $plan_file

Review it in one pass — does its Definition of Done prove the intent, do
its decisions hold up against the code, is a trap missing, is scope right.
Finding nothing is a fine result. Apply the fixes the user agrees to, then
stop.
EOF
}
