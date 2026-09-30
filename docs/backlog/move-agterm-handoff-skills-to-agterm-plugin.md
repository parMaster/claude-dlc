---
worth: yes
added: 2026-09-30
---
# move handoff and spawn-session from planning to the agterm plugin

`handoff` and `spawn-session` live in `planning` but only work inside agterm: every script they call exits
with "not available" unless `AGTERM_ENABLED=1` and `agtermctl` is on PATH. The `agterm` plugin now exists,
so they belong there, next to `overlay`.

What moves:

- `planning/skills/handoff/` and `planning/skills/spawn-session/` to `agterm/skills/`. The explicit command
  becomes `/agterm:handoff`.
- Their scripts to `agterm/scripts/`: `agterm-handoff.sh`, `agterm-spawn.sh`, `agterm-session-new.sh`,
  `codex-handoff.sh`, `codex-spawn.sh`, `handoff-prompt.sh`.

The catch is `review-plan`: its "Spawn Codex session" option runs `codex-review-handoff.sh`, which reuses
`codex-spawn.sh`, `agterm-session-new.sh` and `handoff-prompt.sh`. A skill can't reach another plugin's
scripts through `${CLAUDE_PLUGIN_ROOT}`. Proposed fix: delete `codex-review-handoff.sh` and have
`review-plan` invoke `agterm:spawn-session` with the review prompt inline, the same way `oversight` already
kicks off iterations. That also lets the review run on Claude, not only Codex. It loses the fixed
`--sandbox workspace-write --ask-for-approval never` flags, so a Codex review session may prompt for
approvals.

Also touches:

- `plan` and `review-plan` text that points at `/planning:handoff`, and `oversight`'s
  `planning:spawn-session` references.
- `tests/run.sh` script paths and section labels; the `codex-review-handoff.sh` cases go away.
- README sections for both plugins, the `agterm` descriptions in `plugin.json` and `marketplace.json`.
- Versions: `planning` major bump (skills removed), `agterm` minor bump (skills added), with CHANGELOG
  entries.
