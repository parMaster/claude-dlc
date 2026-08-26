# Dedup the agterm Hand-off Into a Shared Script

**Goal:** Replace the three near-identical copies of the agterm hand-off sequence (in `plan/SKILL.md`, `review-plan/SKILL.md`, and `implement-in-session/SKILL.md`) with one bundled script all three call.

**Architecture:** A new script, `plugins/planning/scripts/agterm-handoff.sh`, takes a plan file path as its one argument and does everything the current inline `agtermctl` sequence does — including its own `AGTERM_ENABLED`/`agtermctl` availability check — printing the new session's display name on success and a clear error to stderr on failure. Each of the three `SKILL.md` files replaces its embedded bash block with one `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "<plan-file>"` call.

**Tech Stack:** Bash script (`scripts/`), Markdown skill instructions (`SKILL.md`), `agtermctl` CLI, `git`, `jq`.

---

## Context (from discovery)

- files/components involved:
  - `plugins/planning/scripts/agterm-handoff.sh` — new file, the actual dedup target
  - `plugins/planning/skills/plan/SKILL.md` — Step 3, "Implement in a Separate Session" bullet (lines ~321–340 as of this writing)
  - `plugins/planning/skills/review-plan/SKILL.md` — Step 5, same bullet (lines ~141–160)
  - `plugins/planning/skills/implement-in-session/SKILL.md` — Steps 2–3 collapse into one Step 2
  - `plugins/planning/.claude-plugin/plugin.json` — version bump
  - `CHANGELOG.md` — new entry
- related patterns found: this repo already has a `${CLAUDE_PLUGIN_ROOT}`-relative script convention, but only from `hooks.json` command entries so far (`plugins/statusline/hooks/hooks.json:9` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh`, `plugins/global-rules/scripts/block-root-find.sh` invoked the same way). This plan is the first place a `SKILL.md`'s own prose instructions invoke a bundled script this way — confirmed viable below (see Verified Dependency Behaviors).
- dependencies identified: `agtermctl`, `jq`, `git rev-parse --show-toplevel`, the `${CLAUDE_PLUGIN_ROOT}` substitution mechanism

## Verified Dependency Behaviors

*Behaviors this plan's design depends on — verified this session, not assumed.*

- **`disable-model-invocation: true` blocks ALL Claude-initiated `Skill` tool calls, not just natural-language auto-triggering** — verified live against `code.claude.com/docs/en/skills` via a research agent this session (not training-data memory). Quoted from the docs: *"disable-model-invocation — Set to true to prevent Claude from automatically loading this skill... If Claude tries anyway, Claude Code blocks the call."* The gate is drawn as "you (the user) invoke" vs. "Claude invokes" — an explicit `Skill(skill="planning:implement-in-session", ...)` call issued because `plan/SKILL.md`'s own prose told Claude to make it is still "Claude invokes," and is blocked exactly like natural-language auto-triggering would be. **This is why the original idea — have `plan`/`review-plan` call `implement-in-session` via the `Skill` tool — does not work**, since `implement-in-session` has `disable-model-invocation: true` (by design, so it never fires from natural language on its own). Only a literal user-typed `/planning:implement-in-session` bypasses the block. This plan routes around the restriction entirely by not using the `Skill` tool at all for the shared logic — a bundled shell script has no such gate.
- **`${CLAUDE_PLUGIN_ROOT}` substitutes correctly inside a `SKILL.md` body, not just in `hooks.json` commands or `allowed-tools` Bash rules** — verified this session via a research agent reading `code.claude.com/docs/en/skills.md` and `plugins-reference.md`: *"`${CLAUDE_PLUGIN_ROOT}` (plugin install dir), `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}` are all available and substituted in both the body and in `allowed-tools` Bash rules."* So a plain `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" ...` line inside a `SKILL.md`'s Markdown body resolves correctly when the agent runs it via the `Bash` tool.
- The agterm hand-off sequence itself (`plugins/planning/skills/review-plan/SKILL.md:145-156`, read fresh this session, not from memory of the earlier plan): resolves `$PROJECT_ROOT` via `git rev-parse --show-toplevel`, derives `SLUG` by stripping the `yyyy-mm-dd-` prefix from the plan's basename, creates a session via `agtermctl session new --cwd "$PROJECT_ROOT" --workspace "$AGTERM_WORKSPACE_ID" --name "Implement: $SLUG" --json`, captures `SID` with `jq -r '.result.id'`, guards on non-empty/non-`null`, types the adapted prompt, submits with a separate `session type $'\n'`. This plan's script reuses this logic verbatim, in a real script instead of prose-embedded bash.
- `implement-in-session/SKILL.md`'s own separate availability check (Step 2, `plugins/planning/skills/implement-in-session/SKILL.md:30-39`, read fresh this session): currently a standalone check before the hand-off. Since the new script performs this same check internally (see Technical Details), this step collapses into the single script call — `implement-in-session` has no menu to gate, so there is no reason to check twice.

## Development Approach

- **testing approach**: Regular — Bash script + Markdown, no `go test`/lint target. "Testing" means: (1) a lint pass with `bash -n` (syntax check) and manually tracing the script logic, (2) a real end-to-end invocation against a real plan file in the live agterm session, exactly like the manual verification done for the two prior plans in this session, (3) an isolated failure-path check (`AGTERM_ENABLED=0`) that doesn't touch agterm at all.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: the shared script must be byte-for-byte behaviorally identical to the current inline sequence** for the success path — same session naming, same prompt wording, same submit mechanism — this is a pure refactor, not a behavior change
- **CRITICAL: single summary commit at the end** — no per-task commits
- **CRITICAL: run `golangci-lint run ./...` before committing** — N/A, no Go code touched, but confirm with `git diff --stat` that only the listed files changed
- maintain backward compatibility — `/planning:implement-in-session <plan-file>` and both menu options must behave identically to a user after this change, just implemented via one shared script instead of three inline copies

## Solution Overview

- New file `plugins/planning/scripts/agterm-handoff.sh`: takes `$1` = plan file path, checks `AGTERM_ENABLED`/`agtermctl` availability itself (exits 1 with a clear stderr message if unavailable — this subsumes `implement-in-session`'s separate check), runs the hand-off, prints the session's display name (`Implement: SLUG`) to stdout on success, exits non-zero with a stderr error on any failure.
- `plan/SKILL.md` and `review-plan/SKILL.md` keep their own separate `AGTERM_ENABLED`/`agtermctl` check before building their menu (unavoidable — it decides whether the option even appears, which happens before any script could run) — this is the one piece of duplication that stays, by design (2 copies of a 1-line check, not 2 copies of the 15-line sequence). Their "Implement in a Separate Session" bullets shrink to one `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "PLAN_FILE"` call plus a success/failure reporting instruction.
- `implement-in-session/SKILL.md` drops its separate Step 2 (availability check) entirely, since the script now does that itself — its 4 steps become 3 (resolve plan file → hand off via script → confirm).

## Technical Details

### New file: `plugins/planning/scripts/agterm-handoff.sh`

```bash
#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session, in the caller's
# own workspace. Shared by plan/SKILL.md, review-plan/SKILL.md, and
# implement-in-session/SKILL.md so the agtermctl sequence lives in one place
# instead of three copies.
#
# Usage: agterm-handoff.sh <plan-file>
# Requires: AGTERM_ENABLED=1, AGTERM_WORKSPACE_ID set (both set automatically
# by agterm itself), agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Implement: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: agterm-handoff.sh <plan-file>}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Implement: $SLUG"

SID=$(agtermctl session new --cwd "$PROJECT_ROOT" --workspace "$AGTERM_WORKSPACE_ID" --name "$SESSION_NAME" --json | jq -r '.result.id')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
  echo "agterm-handoff: session new failed to return a session id" >&2
  exit 1
fi

agtermctl session type "claude 'You have a new implementation plan to execute: $PLAN_FILE

Read it fully, then implement every task in order, following its stated
testing approach. Run the project'\''s tests and linter before treating any
task as done.'" --target "$SID"

agtermctl session type $'\n' --target "$SID"

echo "$SESSION_NAME"
```

Two notes on why this differs slightly from the inline version it replaces:
1. **`set -euo pipefail` replaces the manual `&&`-chaining** the inline version used (`PROJECT_ROOT=... && SLUG=... && SID=... && [ -n "$SID" ] && ... && ...`). A real script gets short-circuit-on-failure for free via `errexit`; the inline version needed explicit `&&` chains because it was one long compound Bash-tool command, not a script file. `pipefail` matters specifically for the `agtermctl session new ... | jq -r ...` pipeline — without it, a failing `agtermctl` with a still-succeeding `jq` (e.g. `jq` prints `null` for missing input) would not trip `errexit`, and execution would reach the explicit `[ -z "$SID" ]` check below instead — which still catches it, just with a less specific error message than a custom one would give. Either way the script exits non-zero; this is a documented, acceptable trade-off, not a gap.
2. The one Bash tool call needed to *invoke* this script (`bash ".../agterm-handoff.sh" "PLAN_FILE"`) is inherently a single call already — the "run this as one chained Bash call to avoid multiple approval prompts and agterm's focus-steal-then-switch-back" concern from the original design is now satisfied automatically, with no special chaining instructions needed in any `SKILL.md`.

### `plan/SKILL.md` — replace the "Implement in a Separate Session" bullet body

Current (to be replaced, `plugins/planning/skills/plan/SKILL.md:321-340`):

```markdown
- **Implement in a Separate Session**: hand off to a fresh agterm session in this same workspace — no model-tier question.

  Run the whole handoff as **one Bash tool call** — `session new` always steals UI focus (no flag suppresses it), so splitting this into several calls forces the user to approve one, get yanked to the new session, switch back to approve the rest, then switch again to actually watch it. One chained call means one approval, and the UI lands on the new session — already running — when it's done:

  ```bash
  PROJECT_ROOT=$(git rev-parse --show-toplevel) && \
  SLUG=$(basename "PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//') && \
  SID=$(agtermctl session new --cwd "$PROJECT_ROOT" --workspace "$AGTERM_WORKSPACE_ID" --name "Implement: $SLUG" --json | jq -r '.result.id') && \
  [ -n "$SID" ] && [ "$SID" != "null" ] && \
  agtermctl session type "claude 'You have a new implementation plan to execute: PLAN_FILE

  Read it fully, then implement every task in order, following its stated
  testing approach. Run the project'\''s tests and linter before treating any
  task as done.'" --target "$SID" && \
  agtermctl session type $'\n' --target "$SID"
  ```

  Substitute the real plan path for both occurrences of `PLAN_FILE`. If the command's exit status is non-zero, the `&&` chain short-circuits before typing anything into a nonexistent target; tell the user the handoff failed with the captured error output, and stop. Do not fall back to a subagent silently.

  Then tell the user: implementation has been handed off to a new agterm session (named `Implement: SLUG`) in this same workspace — they can switch to it to watch or drive it directly. Stop completely.
```

New:

```markdown
- **Implement in a Separate Session**: hand off to a fresh agterm session in this same workspace — no model-tier question.

  Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "PLAN_FILE"` (substitute the real plan path for `PLAN_FILE`).

  On success (exit 0), the script's last stdout line is the new session's display name (e.g. `Implement: foo`) — tell the user implementation has been handed off to a new agterm session with that name, in this same workspace, and they can switch to it to watch or drive it directly. On failure (non-zero exit), tell the user the handoff failed, quoting the script's stderr output. Do not fall back to a subagent silently. Either way, stop completely.
```

### `review-plan/SKILL.md` — replace the same bullet body

Current (`plugins/planning/skills/review-plan/SKILL.md:141-160`) is identical in shape to `plan/SKILL.md`'s, except its closing sentence says "Stop completely — do NOT continue the review loop." instead of just "Stop completely." Apply the same replacement, keeping that skill's own closing sentence:

```markdown
- **Implement in a Separate Session**: hand off to a fresh agterm session in this same workspace — no model-tier question (agterm has no model picker; the new session runs whatever `claude` launches with by default).

  Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "PLAN_FILE"` (substitute the real plan path for `PLAN_FILE`).

  On success (exit 0), the script's last stdout line is the new session's display name (e.g. `Implement: foo`) — tell the user implementation has been handed off to a new agterm session with that name, in this same workspace, and they can switch to it to watch or drive it directly. On failure (non-zero exit), tell the user the handoff failed, quoting the script's stderr output. Do not fall back to a subagent silently. Either way, stop completely — do NOT continue the review loop.
```

### `implement-in-session/SKILL.md` — collapse Steps 2–3 into one Step 2

Current file has 4 steps (Resolve plan file / Check agterm availability / Hand off / Confirm), `plugins/planning/skills/implement-in-session/SKILL.md:15-70`. Replace Steps 2–3 (`## Step 2: Check agterm availability` through the end of `## Step 3: Hand off`, i.e. lines 30–64) with a single new Step 2, and renumber the old Step 4 (`Confirm`) to Step 3:

```markdown
## Step 2: Hand off

Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "PLAN_FILE"`, substituting the plan path resolved in Step 1.

This one call also performs the `AGTERM_ENABLED`/`agtermctl` availability check
internally — unlike `plan`/`review-plan`, which check availability separately
to decide whether to even show their menu option, this skill has no menu, so
there's no reason to check twice. If it exits non-zero, tell the user why
(its stderr says either "not available" or the specific hand-off failure) and
stop.

## Step 3: Confirm

On success, the script's last stdout line is the new session's display name
(e.g. `Implement: foo`) — tell the user: implementation has been handed off
to a new agterm session with that name, in this same workspace, and they can
switch to it to watch or drive it directly. Stop completely.
```

Leave Step 1 ("Resolve the plan file") exactly as it is.

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Create the shared script

**Files:**
- Create: `plugins/planning/scripts/agterm-handoff.sh`

- [ ] Create the file with the exact content shown in Technical Details above.
- [ ] Make it executable: `chmod +x plugins/planning/scripts/agterm-handoff.sh` (matches the convention of the existing `plugins/global-rules/scripts/block-root-find.sh` and `plugins/statusline/scripts/setup.sh`, even though every call site here invokes it explicitly via `bash ...` rather than relying on the executable bit).
- [ ] Syntax-check it: `bash -n plugins/planning/scripts/agterm-handoff.sh` — expect no output (clean parse).
- [ ] Trace the failure path without touching agterm: `AGTERM_ENABLED=0 bash plugins/planning/scripts/agterm-handoff.sh docs/plans/2026-08-26-dedup-agterm-handoff-script.md; echo "exit=$?"` — expect the "not available" message on stderr and `exit=1`.

### Task 2: Update `plan/SKILL.md`

**Files:**
- Modify: `plugins/planning/skills/plan/SKILL.md`

- [ ] Replace the "Implement in a Separate Session" bullet body with the new version shown in Technical Details.
- [ ] Read the file back and confirm: the bullet is now much shorter, the availability-check line above the menu JSON (`Before building this menu, check availability: ...`) is untouched, and no other bullet in Step 3 changed.

### Task 3: Update `review-plan/SKILL.md`

**Files:**
- Modify: `plugins/planning/skills/review-plan/SKILL.md`

- [ ] Replace the "Implement in a Separate Session" bullet body with the new version shown in Technical Details (note its distinct closing sentence).
- [ ] Read the file back and confirm the same things as Task 2, for this file.

### Task 4: Update `implement-in-session/SKILL.md`

**Files:**
- Modify: `plugins/planning/skills/implement-in-session/SKILL.md`

- [ ] Replace old Steps 2–3 with the new single Step 2, and renumber old Step 4 to Step 3, as shown in Technical Details.
- [ ] Read the file back and confirm: Step 1 is untouched, the file now has exactly 3 numbered steps, and `allowed-tools: Bash` is still accurate (still only `Bash` is used).

### Task 5: End-to-end manual verification

**Files:** none (verification only)

- [ ] Invoke the script directly against this plan's own file, in the live agterm session: `bash plugins/planning/scripts/agterm-handoff.sh docs/plans/2026-08-26-dedup-agterm-handoff-script.md`. Confirm: exit 0, stdout's last line is `Implement: dedup-agterm-handoff-script`, and `agtermctl tree --json` shows a new session with that name in the current workspace (`$AGTERM_WORKSPACE_ID`) with `claude` already running the hand-off prompt.
- [ ] Confirm the updated `plan/SKILL.md` bullet actually works end-to-end: from a state where a plan exists and its post-review menu is showing, pick "Implement in a Separate Session" and confirm the same result as above (a new session, correct name, prompt submitted).
- [ ] Confirm the updated `review-plan/SKILL.md` bullet the same way, from its own post-review menu.
- [ ] Confirm the updated `implement-in-session/SKILL.md` still works via direct invocation: `/planning:implement-in-session docs/plans/2026-08-26-dedup-agterm-handoff-script.md` (or the current live plan file at verification time) and confirm the same result.
- [ ] Close every demo/verification session created above (`agtermctl session close --target <id>`) so they don't linger.

### Task N-1: Verify acceptance criteria
- [ ] verify all three `SKILL.md` files reference the script via `"${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh"`, not a hardcoded or relative path
- [ ] verify `git diff --stat` shows exactly: the new script, the three `SKILL.md` files, `plugin.json`, `CHANGELOG.md`, plus this plan's move to `completed/`
- [ ] verify the script's success-path behavior is unchanged from the pre-dedup inline version: same session naming (`Implement: SLUG`), same prompt wording, same workspace targeting (`$AGTERM_WORKSPACE_ID`)

### Task N: [Final] Wrap up and commit
- [ ] bump `plugins/planning/.claude-plugin/plugin.json` — read the live version first (`cat plugins/planning/.claude-plugin/plugin.json`; was `1.11.0` when this plan was written, but re-check). This is a **patch** bump, not minor: it's a pure internal refactor (no new skill, no new user-facing option, no behavior change) — matches this repo's own semver convention ("patch for fixes" — a dedup with no behavior change is closer to a fix/cleanup than a new component).
- [ ] add a `CHANGELOG.md` entry, heading `## planning vX.Y.Z - 2026-08-26` (the actual bumped patch version), under a `### Fixes` (not `### Features`) subheading — one bullet describing the dedup and why (three copies of the same `agtermctl` sequence → one shared script), and noting the `disable-model-invocation` finding as the reason a `Skill`-tool-based dedup wasn't possible.
- [ ] move this plan to `docs/plans/completed/` — `mkdir -p docs/plans/completed && mv docs/plans/2026-08-26-dedup-agterm-handoff-script.md docs/plans/completed/`
- [ ] single summary commit: all implementation changes + plan move in one commit, message style matching existing history (e.g. `fix(planning): dedup agterm hand-off into a shared script`)
- [ ] open draft PR — invoke `planning:pr` (optional; recent history on this repo shows commits landing directly on `main` without PRs — ask the user before invoking `pr` if unsure)

## Post-Completion

*Items requiring manual intervention or external systems*

- None — this is a self-contained internal refactor with no external dependencies beyond what already existed.
