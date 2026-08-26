# Implement in Session — Dedicated Skill

**Goal:** Add a dedicated, explicit-only entry point — `/planning:implement-in-session [plan-file]` — that skips straight to handing a plan off to a fresh agterm session, bypassing `plan`'s and `review-plan`'s menus entirely.

**Architecture:** A new skill, `plugins/planning/skills/implement-in-session/SKILL.md`, with `disable-model-invocation: true` so it never fires from natural-language intent matching (unlike `plan`/`review-plan`) — it only runs when explicitly invoked by name. It resolves a plan file (from an argument or by finding the most recent one in `docs/plans/`), then runs the exact same agterm hand-off sequence already implemented and shipped in `plan/SKILL.md` and `review-plan/SKILL.md` (landed in commit `24ce03c`, plugin version `1.10.1`), parameterized by that plan file.

**Tech Stack:** Markdown skill instructions (`SKILL.md`), `agtermctl` CLI, `git`, `jq`.

---

## Context (from discovery)

- files/components involved:
  - `plugins/planning/skills/implement-in-session/SKILL.md` — new file, this plan's main deliverable
  - `plugins/planning/.claude-plugin/plugin.json` — version bump (currently `1.10.1` — verify live at implementation time, do not trust this number, see Task 3)
  - `CHANGELOG.md` — new entry
  - `CLAUDE.md` — two stale "skills don't appear in `/` autocomplete" claims to correct (lines 57 and 61 as of this writing — re-grep at implementation time, line numbers shift)
  - `README.md` — one more stale claim (line 237 as of this writing) plus a new skill-table row and a `implement-in-session` node in the `plan`/`review-plan` flow diagrams
- related patterns found: `review-plan/SKILL.md` Step 0 ("Find the plan file") is the template for argument/default resolution — `$ARGUMENTS` path if given, else most-recently-modified `.md` under `docs/plans/` excluding `completed/`. The agterm hand-off sequence itself (availability check, single `&&`-chained `agtermctl` call, adapted 3-sentence prompt) already exists verbatim in both `plan/SKILL.md` and `review-plan/SKILL.md` — reuse it unchanged, do not redesign.
- dependencies identified: `agtermctl` (external CLI), `jq`, `git rev-parse --show-toplevel`, the already-shipped hand-off sequence in `review-plan/SKILL.md`

## Verified Dependency Behaviors

*Behaviors this plan relies on — verified by reading the actual current files, not inferred from memory of the earlier plan.*

- The agterm hand-off sequence (`plugins/planning/skills/review-plan/SKILL.md:141-166`, identical copy in `plan/SKILL.md`): confirmed by reading the file as it exists on disk right now (post-merge, commit `24ce03c` + follow-up fix `8de434a`) — a single `&&`-chained Bash call that resolves `$PROJECT_ROOT`, derives `SLUG` from the plan filename (strips the `yyyy-mm-dd-` prefix), creates a session via `agtermctl session new --cwd "$PROJECT_ROOT" --workspace "$AGTERM_WORKSPACE_ID" --name "Implement: $SLUG" --json`, captures `SID` with `jq -r '.result.id'`, guards on `[ -n "$SID" ] && [ "$SID" != "null" ]`, types `claude '<prompt>'` into it, then submits with a separate `session type $'\n'`. This plan's new skill reuses this block character-for-character, substituting only `PLAN_FILE`.
- Skill frontmatter / argument substitution (docs.claude.com/en/skills.md, fetched live by a research agent this session, not from training-data memory): `commands/<name>.md` and `skills/<name>/SKILL.md` share one frontmatter schema and substitution engine; `commands/` is legacy-only now, `skills/` is current guidance. Relevant fields: `description` (recommended), `argument-hint` (shown to the user as usage hint), `disable-model-invocation` (bool — stops the skill from being auto-triggered by natural-language intent matching; explicit `/name` invocation still works), `user-invocable` (bool — whether it can be run at all via slash/typed invocation; must be `true`, not just default-assumed, since this skill's entire purpose is explicit invocation), `allowed-tools`. Argument substitution: `$ARGUMENTS` is the whole trailing string, `$0`/`$1`/... are 0-based positional args, both work identically in `skills/` and `commands/` files. `name`/`paths` frontmatter keys are ignored — the invocable name always comes from the directory name (`implement-in-session`), which is why the new directory must be named exactly that.
- `AGTERM_ENABLED` / `AGTERM_WORKSPACE_ID` env vars (`~/.claude/skills/agterm/SKILL.md`): both set only in shells agterm spawned, `AGTERM_WORKSPACE_ID` guaranteed present whenever `AGTERM_ENABLED=1` is. Same detection this plan's predecessor already verified live.

## Development Approach

- **testing approach**: Regular — markdown skill-instruction content again, no `go test`/lint target. "Testing" means a real invocation of the finished skill against a real plan file (this plan's own file, once it exists) and a manual check that natural-language phrasing alone does NOT trigger it.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: do not touch `plan/SKILL.md` or `review-plan/SKILL.md`** — this plan adds a new file only; deduplicating their inline hand-off copies against this new skill is explicitly out of scope (see Post-Completion)
- **CRITICAL: re-read the live `plugins/planning/.claude-plugin/plugin.json` version at implementation time** before bumping — do not assume it is still `1.10.1`
- **CRITICAL: single summary commit at the end** — no per-task commits
- **CRITICAL: run `golangci-lint run ./...` before committing** — N/A, no Go code touched, but confirm with `git diff --stat` that only the listed files changed
- maintain backward compatibility — `plan`/`review-plan`'s existing inline options are untouched and keep working exactly as before

## Solution Overview

- One new skill directory, `plugins/planning/skills/implement-in-session/`, containing `SKILL.md`.
- Frontmatter marks it `disable-model-invocation: true` and `user-invocable: true` so it is reachable only by explicit invocation (`/planning:implement-in-session <plan-file>` or bare `/implement-in-session` if that name is unclaimed), never by Claude's own intent-matching the way `plan`/`review-plan` are.
- Body: (1) resolve the plan file from `$0` or fall back to the most-recently-modified plan under `docs/plans/`; (2) check `AGTERM_ENABLED`/`agtermctl` availability and fail loudly (no silent fallback, no menu to hide behind) if unavailable; (3) run the exact shipped hand-off sequence, parameterized by the resolved plan; (4) confirm to the user and stop.
- Three small doc fixes ride along in the same commit: `plugin.json` version bump, `CHANGELOG.md` entry, and correcting the three now-stale "skills don't appear in `/` autocomplete" claims (`CLAUDE.md` ×2, `README.md` ×1) discovered while researching this feature — plus adding the new skill to `README.md`'s planning section.

## Technical Details

### New file: `plugins/planning/skills/implement-in-session/SKILL.md`

```markdown
---
name: implement-in-session
description: Hand off an implementation plan directly to a fresh agterm session, skipping the plan/review-plan menus. Explicit invocation only.
argument-hint: "[plan-file]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash
---

# Implement in a Separate Session

Hand a plan straight to a fresh agterm session — the same mechanism `plan` and
`review-plan` offer inline, without going through either skill's menus.

## Step 1: Resolve the plan file

1. If an argument was given (`$0`), use it as the plan file path.
2. Otherwise, find the most recently modified plan:

   Run: `ls -t docs/plans/*.md 2>/dev/null | head -1`

   (this already excludes `docs/plans/completed/`, since `*.md` only globs
   files directly under `docs/plans/`, not its subdirectories)

3. If step 2 produced no output (no `.md` files directly under `docs/plans/`),
   tell the user there's no active plan to hand off and stop.
4. Verify the resolved path exists: `test -f "<path>"`. If it doesn't, tell
   the user the file wasn't found and stop.

## Step 2: Check agterm availability

Run: `[ "$AGTERM_ENABLED" = "1" ] && command -v agtermctl >/dev/null 2>&1 && echo AVAILABLE`

Unlike `plan`/`review-plan`, which simply omit their inline option when this
check fails, this skill has no menu to hide behind. If the check doesn't
print `AVAILABLE`, tell the user plainly: "This only works inside an agterm
session with `agtermctl` on PATH — `AGTERM_ENABLED` is unset or `agtermctl`
wasn't found." Then stop. Do not fall back to a subagent or any other
mechanism.

## Step 3: Hand off

Run the following as a single Bash tool call (one shell invocation, `&&`-chained)
— this is the exact sequence `plan`'s and `review-plan`'s "Implement in a
Separate Session" option already use, parameterized by the plan file resolved
in Step 1 (`PLAN_FILE` below):

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

Substitute the real resolved plan path for both occurrences of `PLAN_FILE`.
If the command's exit status is non-zero, the `&&` chain short-circuited
before typing anything into a nonexistent target — tell the user the handoff
failed with the captured error output, and stop.

## Step 4: Confirm

Tell the user: implementation has been handed off to a new agterm session
(named `Implement: SLUG`) in this same workspace — they can switch to it to
watch or drive it directly. Stop completely.
```

Note the frontmatter includes `name: implement-in-session` even though the directory name already determines it — this documents intent inline and matches every other `SKILL.md` in this repo (`review-plan/SKILL.md`, `plan/SKILL.md` both do the same, despite `name`/`paths` being ignored per the verified dependency behavior above).

### `plugin.json` version bump

Read the live `version` field first (`cat plugins/planning/.claude-plugin/plugin.json`) — do not assume `1.10.1`. This is a **feature** addition (new skill) → bump the minor component: e.g. if the live version is `1.10.1`, the new version is `1.11.0`.

### `CHANGELOG.md` entry

New heading `## planning vX.Y.0 - 2026-08-26` (X.Y.0 = the actual bumped version from above), `### Features` subheading, one bullet describing the new `implement-in-session` skill and why it exists (direct hand-off without going through `plan`/`review-plan` menus).

### `CLAUDE.md` corrections

Two stale lines (grep for `autocomplete` to find current line numbers — they were 57 and 61 as of this plan's writing):

```
- Skills are invokable by full name (e.g., `/planning:exec`) — they don't appear in `/` autocomplete dropdown (only `commands/*.md` files do)
```
→
```
- Skills appear in `/` autocomplete the same as `commands/*.md` files — `commands/` is legacy-only now; use `skills/<name>/SKILL.md` for anything new. Both share one frontmatter schema (`description`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, ...) and the same `$ARGUMENTS`/`$0`/`$name` argument substitution.
```

and, under "Known Claude Code Limitations":
```
- Plugin skills don't appear in `/` autocomplete. Invoke by typing the full name or via natural language.
```
→ delete this line entirely (it's now false, and the corrected fact already lives in the "Structure" section above per the replacement just made — no need to state it twice).

### `README.md` corrections and additions

Stale line (grep for `autocomplete`, was line 237):
```
Skills are invokable by full name (e.g. `/planning:plan`) but won't appear in the `/` autocomplete dropdown — only `commands/*.md` files do. Invoke them by typing the full name or via natural language.
```
→
```
Skills are invokable by full name (e.g. `/planning:plan`) and appear in the `/` autocomplete dropdown the same as `commands/*.md` files — `commands/` is legacy-only now.
```

New skill-table row (add to the `planning` section's table, after the `pr` row):

```
| `implement-in-session` | Explicit-only hand-off of a plan straight to a fresh agterm session, skipping `plan`/`review-plan`'s menus entirely — `/planning:implement-in-session [plan-file]` (defaults to the most recent plan under `docs/plans/` if omitted). Never triggers from natural language (`disable-model-invocation: true`). |
```

Add one node to both existing flow diagrams (`plan` — flow and `review-plan` — flow) showing this skill as an alternate, direct entry point into the same `SESS` hand-off node — e.g. for `plan` — flow, add right after the existing diagram's node declarations:

```mermaid
    EXT(["/planning:implement-in-session"]) -.->|direct, bypasses menu| SESS
```

(and the equivalent addition to the `review-plan` — flow diagram, same `-.->|direct, bypasses menu| SESS` edge into its own `SESS` node).

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Create the `implement-in-session` skill

**Files:**
- Create: `plugins/planning/skills/implement-in-session/SKILL.md`

- [ ] Create the file with the exact content shown in the "New file" section under Technical Details above.
- [ ] Read it back and confirm: frontmatter is valid YAML, `allowed-tools: Bash` matches what Steps 1–4 actually use (every action in this skill is a shell command — no `AskUserQuestion` or other tool is called anywhere in the body), and the `agtermctl` block is byte-for-byte identical to the one in `plugins/planning/skills/review-plan/SKILL.md` (`diff` the two blocks manually) except for the `PLAN_FILE`-is-a-variable-here framing.

### Task 2: Manually verify the skill works

**Files:** none (verification only)

- [ ] Confirm explicit invocation resolves an argument correctly: with this plan's own file already on disk (`docs/plans/2026-08-26-implement-in-session-command.md`), invoke `/planning:implement-in-session docs/plans/2026-08-26-implement-in-session-command.md` and confirm a new agterm session appears in the current workspace, named `Implement: implement-in-session-command`, with the plan hand-off prompt already submitted to a running `claude` process in it.
- [ ] Confirm the no-argument default: invoke `/planning:implement-in-session` with no argument in a state where at least one plan exists directly under `docs/plans/` (not `completed/`), and confirm it resolves to the most recently modified one.
- [ ] Confirm the "no plans" edge case: temporarily rename `docs/plans/` (or work from a scratch directory) — actually, simpler and non-destructive: run just the resolution command in isolation — `ls -t docs/plans/*.md 2>/dev/null | head -1` in a directory with no `.md` files directly under `docs/plans/` (e.g. `/tmp` after `mkdir -p /tmp/docs/plans/completed && cd /tmp`) — confirm it prints nothing, which Step 1.3 handles by stopping with a message instead of crashing on an empty path.
- [ ] Confirm `disable-model-invocation` actually suppresses natural-language triggering: in a fresh conversation turn (not an explicit `/planning:implement-in-session` invocation), phrase a request close to the skill's own description — e.g. "hand this plan off to a fresh agterm session directly" — without the slash command, and confirm Claude does NOT silently invoke this skill (it should either do the hand-off inline via ordinary tool calls, ask for clarification, or invoke `plan`/`review-plan` instead — anything except silently matching this skill by intent).
- [ ] Close/clean up any demo agterm sessions created during this verification (`agtermctl session close --target <id>`) so they don't linger as clutter.

### Task N-1: Verify acceptance criteria
- [ ] verify the new `SKILL.md`'s hand-off block is character-identical to the shipped one in `review-plan/SKILL.md` (aside from the `PLAN_FILE`-is-a-variable framing)
- [ ] verify all three stale "autocomplete" claims are corrected (`CLAUDE.md` ×2, `README.md` ×1) — re-grep `autocomplete` across both files and confirm zero remaining references to the old "skills don't appear in autocomplete" claim
- [ ] verify README's two flow diagrams both got the new `EXT` node and its edge into their respective `SESS` node
- [ ] verify `git diff --stat` shows only: the new `SKILL.md`, `plugin.json`, `CHANGELOG.md`, `CLAUDE.md`, `README.md`, plus this plan's own move to `completed/`

### Task N: [Final] Wrap up and commit
- [ ] bump `plugins/planning/.claude-plugin/plugin.json` — re-read the live version first, bump the minor component (see Technical Details)
- [ ] add the `CHANGELOG.md` entry (see Technical Details) using the actual bumped version number
- [ ] apply the `CLAUDE.md` and `README.md` corrections and additions from Technical Details
- [ ] move this plan to `docs/plans/completed/` — `mkdir -p docs/plans/completed && mv docs/plans/2026-08-26-implement-in-session-command.md docs/plans/completed/`
- [ ] single summary commit: all implementation changes + plan move in one commit, message style matching existing history (e.g. `feat(planning): add dedicated implement-in-session skill`)
- [ ] open draft PR — invoke `planning:pr` (optional; recent history on this repo shows commits landing directly on `main` without PRs — ask the user before invoking `pr` if unsure)

## Post-Completion

*Items requiring manual intervention or external systems*

- **Dedup opportunity (not in scope here)**: `plan/SKILL.md`, `review-plan/SKILL.md`, and this new `implement-in-session/SKILL.md` now each carry their own literal copy of the agterm hand-off sequence — three copies of the same ~15-line block. A future plan could have `plan`/`review-plan`'s inline options invoke `implement-in-session` (passing the resolved plan file as its argument) instead of embedding the sequence themselves, cutting this to one copy. Deliberately deferred: this plan's predecessor had just landed when this one started, and touching those two files again immediately after risked stepping on unreviewed follow-up fixes to that same code (a fix commit, `8de434a`, landed right after the feature commit). Revisit once the current shape has had time to settle.
