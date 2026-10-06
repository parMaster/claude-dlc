#!/usr/bin/env bash
# Shared canned prompt text for a plan-file hand-off. Sourced (not executed)
# by agterm-handoff.sh and codex-handoff.sh, so the wording is defined once
# and can't drift between the two runtimes.

build_handoff_prompt() {
  local plan_file="$1"
  local parent_name="${2:-}"
  cat <<EOF
You have a new implementation plan to execute: $plan_file

Read it fully, then implement it until every Definition of Done item holds,
proven the way the item says. Follow its Decisions and Traps; pick the code
and tests yourself. Tick boxes as they're done, then work through Wrap-up.
EOF
  # Only the Claude hand-off passes a parent name; Codex has no SendMessage.
  # Same wording as spawn-session/SKILL.md's footer.
  if [ -n "$parent_name" ]; then
    cat <<EOF

---
Spawned from Claude session $parent_name. When the task or the user asks you
to report back, send the result there with SendMessage (to: "$parent_name").
EOF
  fi
}
