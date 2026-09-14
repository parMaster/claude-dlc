#!/usr/bin/env bash
# Shared canned prompt text for a plan-file hand-off. Sourced (not executed)
# by agterm-handoff.sh and codex-handoff.sh so the wording can only be
# defined once and can't drift between the two runtimes.

build_handoff_prompt() {
  local plan_file="$1"
  cat <<EOF
You have a new implementation plan to execute: $plan_file

Read it fully, then implement every task in order, following its stated
testing approach. Run the project's tests and linter before treating any
task as done.
EOF
}
