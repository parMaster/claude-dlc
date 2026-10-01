# Move handoff and spawn-session to the agterm plugin

**Goal:** `handoff` and `spawn-session`, with their scripts, live in the `agterm` plugin; `planning` keeps no agterm session-spawning code.

**Kind of change:** refactor

## Intent

`handoff` and `spawn-session` sit in `planning` but only work inside agterm: every script they call exits
"not available" unless `AGTERM_ENABLED=1` and `agtermctl` is on PATH. The `agterm` plugin now exists, so
they move there, next to `overlay`. `planning` skills that need a new session ask `agterm` for one through
the Skill tool, never by calling a script.

```
before                                   after
planning/                                planning/
  skills/handoff                           skills/review-plan ──Skill──┐
  skills/spawn-session                     skills/oversight   ──Skill──┤
  skills/review-plan ─► codex-review-    agterm/                       ▼
  skills/oversight      handoff.sh         skills/spawn-session ─► agterm-spawn.sh / codex-spawn.sh
  scripts/ (7 hand-off scripts)            skills/handoff       ─► agterm-handoff.sh / codex-handoff.sh
agterm/                                    skills/overlay
  skills/overlay                           scripts/ (6 hand-off scripts + overlay scripts)
```

## Decisions

- **What moves** — skills `handoff` and `spawn-session`; scripts `agterm-handoff.sh`, `agterm-spawn.sh`,
  `agterm-session-new.sh`, `codex-handoff.sh`, `codex-spawn.sh`, `handoff-prompt.sh`. Moved with `git mv`
  so history follows. The commands become `/agterm:handoff` and `/agterm:spawn-session`.
- **`codex-review-handoff.sh` is deleted, not moved** — a skill can't reach another plugin's scripts through
  `${CLAUDE_PLUGIN_ROOT}`, and a review hand-off script doesn't belong in `agterm`. `review-plan` instead
  invokes `agterm:spawn-session` (Skill tool) with the review prompt as the argument, the way `oversight`
  already kicks off iterations. Dropped alternative: keep a copy of the spawn scripts in `planning` — two
  copies that drift.
- **The review hand-off is no longer Codex-only** — `spawn-session` asks runtime and model itself, so
  `review-plan`'s option becomes "Spawn a separate session" and it stops asking anything about runtime.
- **Accepted loss** — the fixed `--sandbox workspace-write --ask-for-approval never` flags go away for a
  Codex review session, so it may prompt for approvals. `spawn-session` gets no new flag parameter for this.
- **`build_review_prompt` leaves `handoff-prompt.sh`** — its only caller is the deleted script. The review
  prompt text moves into `review-plan/SKILL.md`, where it is now used.
- **`planning` degrades without `agterm`** — no hard dependency is declared. Only the spawn paths need the
  plugin; everything else in both skills is untouched.

  | Skill | Situation | What happens |
  |---|---|---|
  | `review-plan` | not inside agterm | spawn option isn't offered (its own `AGTERM_ENABLED`/`agtermctl` check stays); the `plan-review` subagent runs here |
  | `review-plan` | inside agterm, plugin installed | choice of "This session" or "Spawn a separate session" |
  | `review-plan` | inside agterm, plugin missing | one line naming the plugin to install, then the subagent review runs here |
  | `oversight` | "Kick off an iteration", plugin missing | one line naming the plugin to install, print the iteration prompt it built so the user can paste it into a session they open, write no "kicked off" Progress Log entry, back to the hub |

  `oversight` never plans the iteration in its own session: that would pull one iteration's detail into
  the long-lived epic session. With the plugin installed but outside agterm, `spawn-session` keeps its
  own behavior (reports "not available", asks about a background subagent).
- **`handoff` keeps finding plans in `docs/plans/`** — that path is a `planning` convention now read from
  `agterm`, same as `overlay` already does for "open the latest plan". No change.
- **Versions** — `planning` 3.0.0 (skills removed, breaking), `agterm` 1.2.0 (skills added).

## Constraints / out of scope

- No behavior change in the six moved scripts or the two moved skills beyond paths, names and wording that
  says "planning".
- `agterm`'s PreToolUse hook (`approve-overlay.sh`) stays as is — it does not start approving spawn scripts.
- Old `CHANGELOG.md` entries and plans under `docs/plans/completed/` are history; leave their
  `/planning:handoff` mentions alone.
- The dashboard "start an item" work stays on the backlog.

## Traps

- `spawn-session` Step 5 rejects a prompt whose first line matches
  `^(spawn|start|kick off|delegate|hand (this|it) off) … (session|agent)`. The review prompt `review-plan`
  passes must open as a direct imperative ("Review the plan …"), or the spawn fails its own guard
  (`skills/spawn-session/SKILL.md`, Step 5).
- `spawn-session` ends with "stop — do not implement the task in this session". `review-plan` relies on
  that: after the spawn reports, it must not go on to run the `plan-review` agent here.
- Both moved skills say "the familiar one from other planning skills" in their model step, and `handoff`
  opens with "`plan` and `review-plan` no longer offer implementation hand-off inline". That wording reads
  wrong from inside `agterm` and needs a touch.
- Script header comments name their callers (`handoff-prompt.sh` lists `codex-review-handoff.sh`;
  `agterm-handoff.sh` mentions `plan`/`review-plan` SKILL.md). Stale after the move.
- `tests/run.sh` has seven `planning/…` hand-off sections (comment, path variable and `echo` label each),
  plus a comment near line 358 inside another section. The `codex-review-handoff.sh` section is the only
  place `build_review_prompt`'s wording is asserted; it goes with the script.
- `README.md`'s agterm section and both `agterm` descriptions (`plugin.json`, `marketplace.json`) describe
  the plugin as overlay-only. The planning section's "Claude hand-off sessions start in auto mode… flagged"
  paragraph describes the moved scripts and belongs with them.
- `docs/backlog/dashboard-cannot-start-an-item.md` says `spawn-session` "is due to move to the `agterm`
  plugin" — false once this lands.

## Definition of Done

- [x] The moved scripts' behavior is pinned before and after — proof: `bash tests/run.sh` passes on `main`
      before any change, and after the move the same assertions for the six moved scripts pass with only
      paths and section labels edited.
- [x] `planning` holds no hand-off code — proof: `ls plugins/planning/scripts` shows only the backlog
      dashboard files; `ls plugins/planning/skills` has no `handoff` or `spawn-session`.
- [x] `agterm` holds both skills and the six scripts — proof: `ls plugins/agterm/skills plugins/agterm/scripts`;
      `claude --plugin-dir plugins/agterm` lists `/agterm:handoff` and `/agterm:spawn-session`.
      `ls` checked; `agterm:spawn-session` loaded and ran from the installed plugin. `/agterm:handoff`
      was not run.
- [x] Nothing live points at the old names — proof:
      `grep -rnE 'planning:(handoff|spawn-session)|codex-review-handoff|build_review_prompt' plugins README.md tests docs/backlog .claude-plugin`
      returns nothing.
- [x] `review-plan` hands a review to a new session through `agterm:spawn-session`, on Claude or Codex —
      proof: inside agterm, run `/planning:review-plan` on a plan, pick the spawn option, and see a new
      session open with the review prompt; this session stops without running the review.
      Run live on Claude (Sonnet); the Codex runtime was not tried.
- [ ] `review-plan` and `oversight` still work without the `agterm` plugin — proof: with only
      `claude --plugin-dir plugins/planning` inside agterm, `/planning:review-plan` with the spawn option
      names the missing plugin and runs the subagent review; `oversight`'s "Kick off an iteration" names
      the plugin, prints the iteration prompt, logs nothing and returns to the hub.
      ⚠️ `review-plan` outside agterm passed live. The `oversight` fallback ran but read as an error
      loop, so it was changed afterwards.
- [ ] ➕ Where a session can't be spawned, both skills know it up front (no failed skill call);
      `oversight` prints the kick-off prompt to copy and logs "prompt handed over for manual kick-off" —
      proof: on a machine without agterm, "Kick off an iteration" shows no error, prints the prompt and
      adds that Progress Log line.
- [x] `plan`, `review-plan` and `oversight` point at `/agterm:handoff` and `agterm:spawn-session`.
- [x] README: `handoff` and `spawn-session` rows and the auto-mode/flagged paragraph are under `agterm`;
      the planning intro no longer promises hand-offs; `agterm`'s descriptions in `plugin.json` and
      `marketplace.json` cover session hand-off as well as overlays.
- [x] `planning` is 3.0.0 and `agterm` is 1.2.0, each with a `CHANGELOG.md` entry; the planning entry names
      the removed commands and their new names.
- [x] `docs/backlog/move-agterm-handoff-skills-to-agterm-plugin.md` is removed with `git rm`, and
      `dashboard-cannot-start-an-item.md` names `agterm:spawn-session` as where spawning lives.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter: none configured for this repo; `bash -n` on each moved script
- [x] README.md updated (covered by the DoD); CLAUDE.md needs no change
- [x] branch is not behind `origin/main` (`git fetch && git status`)
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [x] single commit: all changes + plan move + backlog item removal

## Post-Completion

- Machines with `planning` installed need `/plugin install agterm@parmaster-claude-dlc` to keep hand-offs.
