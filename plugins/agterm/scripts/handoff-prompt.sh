#!/usr/bin/env bash
# Shared canned prompt text for a plan-file hand-off. Sourced (not executed)
# by agterm-handoff.sh and codex-handoff.sh, so the wording is defined once
# and can't drift between the two runtimes.

build_handoff_prompt() {
  local plan_file="$1"
  cat <<EOF
You have a new implementation plan to execute: $plan_file

Read it fully, then implement it until every Definition of Done item holds,
proven the way the item says. Follow its Decisions and Traps; pick the code
and tests yourself. Tick boxes as they're done, then work through Wrap-up.
EOF
}
