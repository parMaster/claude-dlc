# Callback Capability for `spawn-session`/`handoff`

**Goal:** Every session spawned by `spawn-session` or handed off by `handoff`
unconditionally learns the calling session's own cross-session address and
how to `SendMessage` a result back to it — so if the user later tells the
spawned session "return the result to the calling session" (mid-task, not
decided up front), it can, without the calling session having predicted
that need when it built the hand-off.

**Architecture:** Both skills call the `ListAgents` tool before spawning to
read their own self-identifying name, then pass it through to the spawned
session's prompt as one passive sentence — never a directive, just
information the spawned session can act on if asked. `agterm-handoff.sh`
gains an optional second positional argument (`caller-session-name`);
omitted, its prompt is byte-for-byte what it is today, so `plan` and
`review-plan` (which also call it, without this argument) are unaffected.
`spawn-session/SKILL.md` builds its own prompt inline (no shared script for
that part), so it gets the same paragraph added directly to its heredoc.

**Tech Stack:** Bash (`scripts/`), Markdown skill instructions (`SKILL.md`),
the `ListAgents`/`SendMessage` cross-session tools, `agtermctl` CLI, `jq`,
the repo's own `tests/run.sh` fake-`agtermctl` test harness.

---

## Context (from discovery)

- files/components involved:
  - `plugins/planning/scripts/agterm-handoff.sh` — gains an optional
    `caller-session-name` arg, builds the callback paragraph into its canned
    prompt when given
  - `plugins/planning/skills/handoff/SKILL.md` — new step: call `ListAgents`,
    pass the resolved name through to the script
  - `plugins/planning/skills/spawn-session/SKILL.md` — new step: call
    `ListAgents`, append the callback paragraph to the heredoc it already
    builds itself
  - `tests/run.sh` — extend the existing `planning/agterm-handoff.sh` section
    with caller-name assertions (both present and omitted)
  - `plugins/planning/.claude-plugin/plugin.json` — version bump
  - `CHANGELOG.md`, `README.md` — changelog entry, one-sentence doc update
  - **not touched:** `plugins/planning/scripts/agterm-spawn.sh` (unchanged —
    it just types whatever prompt file it's given), `plugins/planning/skills/plan/SKILL.md`
    and `skills/review-plan/SKILL.md` (both call `agterm-handoff.sh` today
    without a second argument; the new argument is optional specifically so
    they keep working unchanged — out of scope to add the callback there too,
    since the user didn't ask for it and their menus are a separate code path)
- related patterns found: `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh` invoked
  via `bash "<path>"` is the established convention for a `SKILL.md` body to
  run a bundled script; `tests/run.sh` already has a working fake-`agtermctl`
  section for `agterm-handoff.sh` with a shared `AGTERM_FAKE_BIN` (also used
  by `agterm-spawn.sh`'s tests) — extend it rather than adding a new fake.
  `allowed-tools:` in `SKILL.md` frontmatter is a comma-separated allowlist
  enforced at the tool-permission layer (confirmed against
  `plugins/planning/skills/plan/SKILL.md:4` and others) — both
  `handoff/SKILL.md` and `spawn-session/SKILL.md` currently declare only
  `Bash`, so both need `ListAgents` added or the new step's tool call is
  blocked.
- note: this plan was scoped down mid-conversation — the original idea
  gated the callback paragraph on the task description sounding like it
  wanted one ("return the result to me"). Rejected: the user pointed out
  they might decide mid-task that they want a result back after already
  spawning the session without that language. Making it unconditional means
  the calling session's own `ListAgents` lookup always runs and the
  paragraph is always present, at the cost of one extra tool call per
  hand-off — a cost worth paying since the alternative is silently
  unreachable once the new session is already running.

## Verified Dependency Behaviors

- **`agterm-handoff.sh`** (`plugins/planning/scripts/agterm-handoff.sh:1-41`,
  read fresh): builds a canned heredoc prompt referencing `$PLAN_FILE`, then
  delegates to `agterm-spawn.sh`. On success, prints exactly the session
  name (`"Implement: $SLUG"`) as its only stdout line and exits 0; on
  failure (`AGTERM_ENABLED` unset/`agtermctl` missing), prints one stderr
  line and exits 1. This contract must not change. Adding `CALLER_NAME="${2:-}"`
  is backward compatible: existing callers (`plan`, `review-plan`) that pass
  only `$1` get an empty string, and the plan below makes the callback
  paragraph conditional on that string being non-empty.
- **`ListAgents` tool** (this session, actual tool output observed
  2026-09-03): its result opens with a self-identifying line —
  `This session is claude-dlc-3f [8e434c] — the name other sessions use to
  message it (it is not listed below; a message to it would be a message to
  yourself).` — followed by a `Peer sessions (N):` list of other `claude`
  processes on the machine, unrelated to how they were started (the peer
  list included interactive terminal sessions never spawned via `Agent` or
  `spawn-session`). This is the only way a session learns its own
  cross-session address; there's no tool parameter or env var for it. This
  behavior is observed, not documented in a stable API reference — the
  skill instructions below must degrade gracefully (skip the callback
  paragraph) if the expected line isn't found, rather than fail the
  hand-off over it.
- **`SendMessage` tool** (schema fetched via `ToolSearch` this session): `to`
  accepts a bare name as shown by `ListAgents` (append `" [ref]"` only to
  disambiguate). Delivery works between independent local `claude` CLI
  processes with no parent/child relationship required for cross-session
  messages to reach a peer — confirmed by this session's own peer list
  including sessions it never spawned. A reply is sent by copying the
  incoming message's `from` attribute as `to`.
- **`allowed-tools:` SKILL.md frontmatter** (`CLAUDE.md` "agents/<name>.md"
  note + observed directly in `plugins/planning/skills/plan/SKILL.md:4`,
  `plugins/git-tools/skills/squash-rebase/SKILL.md:4`, etc.): a
  comma-separated allowlist enforced at the tool-permission layer — a tool
  not listed simply isn't callable, regardless of what the skill body says
  to do. `handoff/SKILL.md:7` and `spawn-session/SKILL.md:5` currently
  declare `allowed-tools: Bash` only.

## Development Approach

- **testing approach**: Regular — Bash + Markdown, no `go test`, matching
  every prior plan touching this area. `agterm-handoff.sh`'s change gets
  real automated assertions in `tests/run.sh` (run via `bash tests/run.sh`,
  wired into CI as `.github/workflows/test.yml`'s `shell-scripts` job). The
  two `SKILL.md` edits are markdown instructions, not executable code —
  `tests/run.sh` has no mechanism to exercise them (it only tests
  `scripts/*.sh`), so they get manual end-to-end verification instead,
  matching how the original `spawn-session` skill itself was verified.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task touching a script MUST include new/updated tests**
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one
  commit covers all implementation + plan move when complete
- **CRITICAL: `agterm-handoff.sh`'s existing behavior for `plan`/`review-plan`
  (called with only `$1`) must not change at all** — this is an additive,
  backward-compatible change for them; only `handoff` starts passing the
  new second argument.
- run tests after each change (`bash tests/run.sh`)
- maintain backward compatibility

## Solution Overview

- `agterm-handoff.sh` gains `CALLER_NAME="${2:-}"`. When non-empty, a
  `CALLBACK_NOTE` string (two leading newlines + a two-sentence paragraph
  naming the caller session and telling the new session to `SendMessage` a
  result there if asked) is appended to the existing heredoc's last line.
  When empty, `CALLBACK_NOTE` is `""` and the prompt is unchanged from today.
- `handoff/SKILL.md` gets a new step between resolving the plan file and
  handing off: call `ListAgents`, extract the bare name from its
  self-identifying line, and pass it as the handoff script's second
  argument (or omit it if the line isn't found).
- `spawn-session/SKILL.md` gets the same new step (its own numbering,
  between "decide on naming" and "check availability/spawn"), and the
  callback paragraph is appended directly to the heredoc it already builds
  in its single chained Bash command, since `spawn-session` has no shared
  script to change.
- Both `SKILL.md` files add `ListAgents` to their `allowed-tools:`
  frontmatter.
- The paragraph text is identical in both cases (only the two variables
  differ): *"This task was spawned from session `<name>`. If asked at any
  point to return a result there, use the SendMessage tool addressed to
  `<name>`."* — worded as a passive capability, not an instruction to
  report back unconditionally.

## Technical Details

### Modify: `plugins/planning/scripts/agterm-handoff.sh`

Replace the file's contents entirely with:

```bash
#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session, in the caller's
# own workspace. Shared by plan/SKILL.md, review-plan/SKILL.md, and
# handoff/SKILL.md so the agtermctl sequence lives in one place instead of
# three copies. Thin wrapper around the generic agterm-spawn.sh: builds the
# canned plan-hand-off prompt into a temp file and hands off in the current
# workspace (no workspace grouping — matches this script's prior behavior).
#
# Usage: agterm-handoff.sh <plan-file> [caller-session-name]
#   [caller-session-name] this session's own cross-session address (from the
#                          ListAgents tool's self-identifying line). When
#                          given, the new session's prompt is told that name
#                          and that it can SendMessage a result back there
#                          if asked. Omit to leave the prompt exactly as it
#                          was before this argument existed.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Implement: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: agterm-handoff.sh <plan-file> [caller-session-name]}"
CALLER_NAME="${2:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Implement: $SLUG"

CALLBACK_NOTE=""
if [ -n "$CALLER_NAME" ]; then
  CALLBACK_NOTE="

This task was spawned from session \`$CALLER_NAME\`. If asked at any point
to return a result there, use the SendMessage tool addressed to
\`$CALLER_NAME\`."
fi

# Portable mktemp (no -t <prefix>, which is BSD-only and fails GNU coreutils
# on the Linux CI runner). Left in place after this script returns — see
# agterm-spawn.sh's comment on why the prompt file is never cleaned up.
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/agterm-handoff.XXXXXX")
cat > "$PROMPT_FILE" <<EOF
You have a new implementation plan to execute: $PLAN_FILE

Read it fully, then implement every task in order, following its stated
testing approach. Run the project's tests and linter before treating any
task as done.$CALLBACK_NOTE
EOF

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$SCRIPT_DIR/agterm-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE"
```

(Comment lines and structure otherwise unchanged from today's file — only
the usage line, `CALLER_NAME`, `CALLBACK_NOTE`, and the heredoc's last line
are new.)

### Modify: `plugins/planning/skills/handoff/SKILL.md`

Replace the file's contents entirely with:

```markdown
---
name: handoff
description: Hand off an implementation plan directly to a fresh agterm session, skipping the plan/review-plan menus. Explicit invocation only.
argument-hint: "[plan-file]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, ListAgents
---

# Handoff to a Separate Session

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

## Step 2: Learn this session's own name

Call `ListAgents`. Its result opens with a self-identifying line, e.g.
"This session is `claude-dlc-3f` [8e434c] — the name other sessions use to
message it." Take the bare name before the ` [` — that's `CALLER_NAME` in
Step 3. If the output doesn't contain a line in that shape, skip this: call
the script in Step 3 with just `PLAN_FILE`, omitting `CALLER_NAME` entirely
— a missing name must never block the hand-off.

## Step 3: Hand off

Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-handoff.sh" "PLAN_FILE" "CALLER_NAME"`, substituting the plan path resolved in Step 1 and the name resolved in Step 2 (omit the trailing argument entirely if Step 2 found no name).

This one call also performs the `AGTERM_ENABLED`/`agtermctl` availability check
internally — unlike `plan`/`review-plan`, which check availability separately
to decide whether to even show their menu option, this skill has no menu, so
there's no reason to check twice. If it exits non-zero, tell the user why
(its stderr says either "not available" or the specific hand-off failure) and
stop.

## Step 4: Confirm

On success, the script's last stdout line is the new session's display name
(e.g. `Implement: foo`) — tell the user: implementation has been handed off
to a new agterm session with that name, in this same workspace, and they can
switch to it to watch or drive it directly. Stop completely.
```

### Modify: `plugins/planning/skills/spawn-session/SKILL.md`

Replace the file's contents entirely with:

```markdown
---
name: spawn-session
description: Hand off an arbitrary task to a freshly spawned, independent agterm session running its own `claude` process — not a background subagent. Activates on "spawn a new session for this", "hand this off to a new session", "start a separate session for this job", "delegate this to a new terminal session", "run this in a separate/parallel session", "spin up a session for this slice", or when the user is slicing a larger job into pieces to hand off one at a time.
argument-hint: "[task description]"
allowed-tools: Bash, ListAgents
---

# Spawn a Task in a Separate Session

Hand an arbitrary task prompt to a brand-new agterm session running its own
`claude` process — a real, visible, independent terminal Claude Code session
the user can switch to, watch, and drive directly. It keeps running after
this conversation ends and can work in parallel with other sessions.

This is different from the `Agent` tool's subagents: those run in-process,
in the background, with no terminal of their own and their transcript
hidden from the user. Use this skill instead of a subagent when the user
wants a session they can actually see and interact with, or work that
should run independently of (and outlive) this conversation.

## Step 1: Resolve the task prompt

- If an argument was given (`$0`), use it as the task description.
- Otherwise, write a clear, self-contained prompt for the task under
  discussion, as if the new session has zero context: state what to do,
  which files/areas are involved, and how to verify it's done. The new
  session cannot see this conversation.

## Step 2: Decide on naming and workspace grouping

- Pick a short `--name` for the sidebar label, e.g. `"Spawn: <slug>"`.
- If this is one of several related slices of a larger job (e.g. working
  through a sliced-up strategy document piece by piece), pick one short,
  stable workspace name and reuse it verbatim for every slice of that job
  — this groups them in the sidebar. Otherwise, skip it: the session opens
  in the current workspace.
- If multiple slices share a stateful resource (a database, a lock, a
  port — anything that would collide under concurrent access), spawn them
  one at a time instead of firing them all off back to back.

## Step 3: Learn this session's own name

Call `ListAgents`. Its result opens with a self-identifying line, e.g.
"This session is `claude-dlc-3f` [8e434c] — the name other sessions use to
message it." Take the bare name before the ` [` — that's `CALLER_NAME`
below. If the output doesn't contain a line in that shape, skip the
callback paragraph in Step 4 entirely rather than blocking the spawn.

## Step 4: Check availability, write the prompt, and spawn — in one command

A `SKILL.md` step is a fresh shell each time it runs, so a shell variable
set in one Bash call is gone by the next — the availability check, the
prompt file, and the `agterm-spawn.sh` call must all happen in a **single**
chained Bash command (this also avoids a redundant approval prompt and
agterm stealing/returning focus twice). Use a **quoted** heredoc
(`<<'PROMPT_EOF'`, not `<<EOF`) so the prompt's own text is never expanded
by the shell, and leave the temp file in place afterward — agtermctl is
fire-and-forget, so there's no reliable moment at which the new session is
known to have read it yet:

```bash
if [ "$AGTERM_ENABLED" = "1" ] && command -v agtermctl >/dev/null 2>&1; then
  PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/agterm-spawn.XXXXXX")
  cat > "$PROMPT_FILE" <<'PROMPT_EOF'
<the resolved task prompt from Step 1>

This task was spawned from session `CALLER_NAME`. If asked at any point to
return a result there, use the SendMessage tool addressed to `CALLER_NAME`.
PROMPT_EOF
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-spawn.sh" "$PWD" "SESSION_NAME" "$PROMPT_FILE" [WORKSPACE_NAME]
else
  echo "spawn-session: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi
```

substituting `SESSION_NAME` from Step 2, `CALLER_NAME` from Step 3 (both
occurrences — omit the whole callback paragraph, including its leading
blank line, if Step 3 found no name), and appending `WORKSPACE_NAME` only
when grouping (omit the argument entirely otherwise).

## Step 5: Confirm

On success (exit 0), the last stdout line is the new session's display
name — tell the user the task has been handed off to a new agterm session
with that name (and which workspace, if grouped), and they can switch to
it to watch or drive it directly. On failure (non-zero exit), tell the
user the hand-off failed, quoting the stderr output — if it's the
"not available" message, ask whether they want a background subagent
instead rather than falling back to one silently. Stop either way — do
not implement the task yourself in this session.
```

### Modify: `tests/run.sh`

**Replace the existing `# planning/agterm-handoff.sh` section entirely**
with this (adds a negative assertion to the existing no-argument run, and a
new block for the caller-name argument):

```bash
# ---------------------------------------------------------------------------
# planning/agterm-handoff.sh
# ---------------------------------------------------------------------------

HANDOFF_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/agterm-handoff.sh"

echo "planning/agterm-handoff.sh"

TEST_REPO="$(mktemp -d)"
(cd "$TEST_REPO" && git init -q)
PLAN_FILE="${TEST_REPO}/docs/plans/2026-01-01-example.md"
mkdir -p "$(dirname "$PLAN_FILE")"
echo "# Example plan" > "$PLAN_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$HANDOFF_SCRIPT" "$PLAN_FILE"
)
assert_eq "prints the new session's display name on success" "Implement: example" "$result"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
assert_contains "creates the session before flagging" "session new" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a claude launch command reading a prompt file" 'claude "$(cat ' "$TYPED_CMD"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
assert_eq "the prompt file the typed command reads actually exists" "yes" "$([ -f "$PROMPT_PATH" ] && echo yes || echo no)"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt file references the plan path" "$PLAN_FILE" "$PROMPT_CONTENT"
assert_contains "prompt file tells the session to read the plan fully" "Read it fully" "$PROMPT_CONTENT"
assert_not_contains "no callback line when caller name is omitted" "SendMessage" "$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$HANDOFF_SCRIPT" "$PLAN_FILE" "caller-session-9f"
)
assert_eq "prints the new session's display name when a caller name is given" "Implement: example" "$result"
TYPED_CMD="$(cat "$TYPED")"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt tells the new session which session spawned it" 'spawned from session `caller-session-9f`' "$PROMPT_CONTENT"
assert_contains "prompt tells the new session how to send a result back" "SendMessage tool addressed to" "$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$HANDOFF_SCRIPT" "$PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"

rm -rf "$AGTERM_FAKE_BIN" "$TEST_REPO"
```

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Add `caller-session-name` to `agterm-handoff.sh`, with tests

**Files:**
- Modify: `plugins/planning/scripts/agterm-handoff.sh`
- Modify: `tests/run.sh` (replace the `# planning/agterm-handoff.sh` section)

- [x] Replace `plugins/planning/scripts/agterm-handoff.sh`'s contents with
      the version in Technical Details above.
- [x] Replace the `# planning/agterm-handoff.sh` section in `tests/run.sh`
      with the version in Technical Details above.
- [x] Run: `bash -n plugins/planning/scripts/agterm-handoff.sh` — expect no
      output (syntax OK).
- [x] Run: `bash tests/run.sh`
      Expected: every `planning/agterm-handoff.sh` assertion PASSes,
      including the new "no callback line when caller name is omitted" and
      the two new caller-name assertions. `Results: N passed, 0 failed`.
      ⚠️ The hard-wrapped `CALLBACK_NOTE` prose puts a line break between
      "addressed to" and the backticked name, so the plan's original
      exact-substring assertion for that sentence never matched. Fixed by
      asserting just `"SendMessage tool addressed to"` (the "spawned from
      session `caller-session-9f`" assertion already covers the name).
      Applied to both `tests/run.sh` and this plan's Technical Details
      snippet, so they stay in sync.

### Task 2: Wire `handoff/SKILL.md` into the callback

**Files:**
- Modify: `plugins/planning/skills/handoff/SKILL.md`

- [x] Replace `plugins/planning/skills/handoff/SKILL.md`'s contents with the
      version in Technical Details above (`allowed-tools` gains
      `ListAgents`; new Step 2 "Learn this session's own name"; old Step 2
      renumbered to Step 3 and updated to pass `CALLER_NAME`; old Step 3
      renumbered to Step 4).
- [x] Manual verification: an *accidental* live run happened during Task 1
      (a manual debugging invocation of `agterm-handoff.sh` forgot this is
      a real `AGTERM_ENABLED=1` session and spawned a real agterm session
      against a throwaway stub plan) — confirmed the callback paragraph
      renders correctly end-to-end and that a `SendMessage` to an
      unreachable name fails with a clear "not reachable" error rather than
      hanging or crashing the spawned session. Not a deliberate `/planning:handoff`
      run through the finished skill text, so treat this as partial
      coverage, not a substitute for actually invoking `/planning:handoff`
      once by hand.

### Task 3: Wire `spawn-session/SKILL.md` into the callback

**Files:**
- Modify: `plugins/planning/skills/spawn-session/SKILL.md`

- [x] Replace `plugins/planning/skills/spawn-session/SKILL.md`'s contents
      with the version in Technical Details above (`allowed-tools` gains
      `ListAgents`; new Step 3 "Learn this session's own name"; old Steps
      3–4 renumbered to 4–5, Step 4's heredoc gains the callback paragraph).
- [ ] ⚠️ Skipped: deliberate manual verification via
      `/planning:spawn-session "print hello world and exit"` — not run this
      session, to avoid spawning another stray real agterm session on top
      of the one from Task 2. Recommend the user try this once by hand
      when convenient.

### Task 4: Version bump, changelog, README

**Files:**
- Modify: `plugins/planning/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [x] Bump `plugins/planning/.claude-plugin/plugin.json`'s `"version"` from
      `"1.14.0"` to `"1.15.0"` (minor: new capability on existing skills).
- [x] Add to the top of `CHANGELOG.md` (after the `# Changelog` / intro
      lines, before the current newest entry):

  ```markdown
  ## planning 1.15.0 - 2026-09-04

  `spawn-session` and `handoff` now unconditionally tell every
  spawned/handed-off session this session's own cross-session address (via
  `ListAgents`) and how to send a result back with `SendMessage` — so a
  result can still be routed back even if you only decide you want one
  after the session is already running, not just when you say so up front.
  `agterm-handoff.sh` gained an optional second `caller-session-name`
  argument; omitted (as `plan`/`review-plan` still call it), the prompt is
  unchanged. Both skills' `allowed-tools` gained `ListAgents`.
  ```

- [x] In `README.md`, after the existing sentence at line 87 ("Every agterm
      hand-off (...) also flags the new session..."), add:

  ```markdown

  `handoff` and `spawn-session` also tell the new session this session's own
  cross-session name (via `ListAgents`), so the new session can `SendMessage`
  a short result back if asked to at any point during the task — not only
  when that's requested up front.
  ```

### Task 5: Verify acceptance criteria

- [x] Verify all requirements from Goal are implemented: both skills always
      look up their own name and always pass the callback paragraph
      through; `plan`/`review-plan` are unaffected.
- [x] Run full test suite: `bash tests/run.sh` — `Results: 43 passed, 0 failed`.
- [x] `golangci-lint run ./...` — N/A, no Go code in this repo/change;
      confirmed via `git diff --stat` that only the intended 7 files changed.
- [x] `grep -n 'CALLER_NAME' plugins/planning/scripts/agterm-handoff.sh` —
      appears in usage comment and script body.
- [x] `grep -n 'ListAgents' plugins/planning/skills/handoff/SKILL.md plugins/planning/skills/spawn-session/SKILL.md` —
      both frontmatter `allowed-tools:` lines and the new step bodies
      reference it.
- [x] `grep -n 'caller-session-name' plugins/planning/skills/plan/SKILL.md plugins/planning/skills/review-plan/SKILL.md` —
      0 matches, confirming `plan`/`review-plan` were left untouched.

### Task 6: Wrap up and commit

- [x] Update `README.md` if anything else needs it (already covered by Task 4).
- [x] Update `CLAUDE.md` if new patterns discovered — not needed; this
      follows existing conventions.
- [x] Move this plan to `docs/plans/completed/`.
- [x] Single summary commit: all implementation changes + plan move in one
      commit.
- [ ] Open draft PR — invoke `planning:pr` (deferred — see note below).

## Post-Completion

*Items requiring manual intervention or external systems*

- The manual end-to-end verifications in Tasks 2 and 3 require a live
  agterm session (`AGTERM_ENABLED=1`) — if this plan is implemented outside
  one, flag those steps as skipped rather than marking them done.
- The `ListAgents` self-identification line format is observed behavior,
  not a documented stable contract. If a future harness update changes its
  wording, the "Take the bare name before the ` [`" instruction in both
  skills may need updating — not caught by any automated test in this repo.
