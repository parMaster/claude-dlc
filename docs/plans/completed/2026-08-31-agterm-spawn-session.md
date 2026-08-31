# Generalize agterm Hand-off to Arbitrary Tasks (`spawn-session`)

**Goal:** Add a `planning:spawn-session` skill that hands an arbitrary, free-form task prompt (not just a `docs/plans/` file) to a freshly spawned, independent agterm session — triggered by natural language as well as `/planning:spawn-session [task]` — without touching the existing plan-only `handoff` skill's behavior or its callers.

**Architecture:** Split the existing `plugins/planning/scripts/agterm-handoff.sh` into a generic primitive, `agterm-spawn.sh` (cwd + session name + prompt file + optional workspace name → spawn + type + flag), and keep `agterm-handoff.sh` as a thin wrapper that builds the canned plan-hand-off prompt into a temp file and calls the primitive. `plan`, `review-plan`, and `handoff` keep calling `agterm-handoff.sh` exactly as before — zero interface change for them. The new `spawn-session` skill calls `agterm-spawn.sh` directly with a task prompt it writes itself.

**Tech Stack:** Bash (`scripts/`), Markdown skill instructions (`SKILL.md`), `agtermctl` CLI, `jq`, the repo's own `tests/run.sh` fake-`agtermctl` test harness.

---

## Context (from discovery)

- files/components involved:
  - `plugins/planning/scripts/agterm-handoff.sh` — existing plan-only hand-off script, becomes a thin wrapper
  - `plugins/planning/scripts/agterm-spawn.sh` — new file, the generalized primitive
  - `plugins/planning/skills/spawn-session/SKILL.md` — new skill, natural-language-triggerable (no `disable-model-invocation`)
  - `plugins/planning/skills/handoff/SKILL.md` — unchanged; stays explicit-only, plan-file-only
  - `tests/run.sh` — existing fake-`agtermctl` tests for `agterm-handoff.sh`; add a parallel section for `agterm-spawn.sh` and extend the shared fake to both
  - `plugins/planning/.claude-plugin/plugin.json` — version bump (new component → minor)
  - `CHANGELOG.md`, `README.md` — new entry / new skill row
- related patterns found: `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh` is the established convention for a `SKILL.md` body to invoke a bundled script (already used by `plan`, `review-plan`, `handoff`); `tests/run.sh` already has a working fake-`agtermctl`-on-`PATH` pattern for testing these scripts without a real agterm session. Every existing script invocation in this repo (`hooks.json`, `SKILL.md` bodies) calls scripts via `bash "<path>"` rather than relying on the executable bit surviving the plugin-cache copy (`docs/plans/completed/2026-08-26-dedup-agterm-handoff-script.md:190`); two of the five repo scripts are committed mode `100644`. Every existing `mktemp` call in this repo (`plugins/statusline/scripts/setup.sh:30`, `plugins/global-rules/scripts/setup.sh:39`) uses the portable bare form — `mktemp -t <prefix>` is BSD-only and fails on the `ubuntu-latest` CI runner (GNU coreutils `mktemp` requires a template with ≥3 trailing `X`s).
- note: the uncommitted `docs/plans/2026-08-28-block-search-dump-hook.md` plan also targets an insertion point "before the `# planning/agterm-handoff.sh` section header" in `tests/run.sh`. Whichever plan lands second should re-check the exact insertion point against the file as it stands at that time, since this plan renames/relocates that section's neighbor.

## Verified Dependency Behaviors

- **`session type --stdin`** (agterm skill `reference.md`, read this session): "`--stdin` reads the text from stdin instead of the argument." Used instead of an argument so arbitrary prompt content never has to survive shell-argument quoting.
- **`session new --command`** execs the given program directly — "argv-split (quotes respected), no shell, no echo" (agterm skill `SKILL.md`, read this session). This is why the hand-off types `claude "$(cat <file>)"` into a real login shell via `session type` instead of using `--command claude ...` — `--command` never runs a shell, so `$(cat ...)` would never expand.
- **`agtermctl` commands are fire-and-forget — "there is no terminal-output streaming and no event subscription"** (agterm skill `SKILL.md`, read this session). The calling script gets no signal for when the target session's shell has actually executed the typed command. **Design consequence: the prompt temp file must never be deleted by the spawning script** — there's no reliable moment at which it's safe to do so.
- **`AGTERM_WORKSPACE_ID` is not always set** (agterm skill `SKILL.md:46`, read this session): the quick terminal only gets `AGTERM_ENABLED`, `AGTERM_WINDOW_ID`, `AGTERM_SOCKET` — no session/workspace ids. `agterm-spawn.sh` must not assume it's set when no `workspace-name` is given; with `set -u` an unset reference aborts with bash's own `unbound variable` message instead of the script's own one-line stderr contract. `reference.md:68` documents `active` (the currently selected session's workspace) as `--workspace`'s own accepted default value, so `--workspace "${AGTERM_WORKSPACE_ID:-active}"` degrades safely instead of crashing.
- **Piping into a fake `agtermctl` that never reads stdin risks SIGPIPE, not blocking** (established this round): a fake that exits immediately without draining stdin can win a race against `printf`'s write and kill it with SIGPIPE, which `pipefail`+`set -e` then propagates as a script failure — a flaky test, not a deterministic pass. `tests/run.sh`'s fake must actively drain (or capture) stdin whenever `--stdin` is one of its arguments.
- **Existing `agterm-handoff.sh` success/failure contract**, read fresh from `plugins/planning/scripts/agterm-handoff.sh`: on success, prints exactly the session display name (`"Implement: $SLUG"`) as its last (only) stdout line, exit 0. On failure (`AGTERM_ENABLED` unset / `agtermctl` missing, or `session new` returns no/`null` id), prints one line to stderr, exit 1. `tests/run.sh` asserts both. The refactor must preserve this contract exactly for existing callers.
- **`handoff/SKILL.md`'s own stated reasoning for skipping a separate availability check** (`plugins/planning/skills/handoff/SKILL.md:34-36`, read fresh): "unlike `plan`/`review-plan`, which check availability separately to decide whether to even show their menu option, this skill has no menu, so there's no reason to check twice." `spawn-session` has no menu either, so the same reasoning argues for *not* adding a second, separately-invoked check — the check belongs folded into the same shell invocation that does the actual work, both to avoid a redundant tool call/approval prompt and because a `SKILL.md` body's separate fenced code blocks each run as an independent shell (`$PROMPT_FILE` set in one block does not survive into the next), so the availability check, prompt-file write, and the `agterm-spawn.sh` call must be one chained command, not three.

## Development Approach

- **testing approach**: Regular — Bash + Markdown, no `go test`. Real automated tests already exist for this area (`tests/run.sh`, run via `bash tests/run.sh`, wired into CI as `.github/workflows/test.yml`'s `shell-scripts` job) — extend that pattern rather than relying on manual verification alone. Manual end-to-end verification (a real hand-off inside a live agterm session) as a final sanity check.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all implementation + plan move when complete
- **CRITICAL: `agterm-handoff.sh`'s existing behavior and stdout/stderr/exit-code contract must not change** for `plan`, `review-plan`, `handoff` — this is a pure refactor for them, a new capability only for `spawn-session`. Two acceptable, deliberate exceptions: (1) an error message's `agterm-handoff:` prefix becomes `agterm-spawn:` for the two failure modes that now happen inside the shared primitive (missing prompt file — new, wasn't previously reachable; `session new` returning no id) — callers only display the message verbatim, they don't match on its prefix; (2) when `AGTERM_WORKSPACE_ID` is unset (e.g. invoked from agterm's quick terminal), the old script aborted with bash's own `unbound variable` message under `set -u` — the new `--workspace "${AGTERM_WORKSPACE_ID:-active}"` degrades gracefully to the active session's workspace instead. Both are improvements, not regressions.
- run tests after each change (`bash tests/run.sh`)
- maintain backward compatibility
- keep housing this in the `planning` plugin rather than widening its `plugin.json` description: `spawn-session` reuses `planning`'s existing agterm hand-off infrastructure directly, and the current description ("context gathering, approach exploration, and revdiff review") is loose enough not to misrepresent an added, related capability. Revisit only if a second unrelated agterm-adjacent skill lands here later.

## Solution Overview

- `agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]`: does the availability check, validates the prompt file exists, creates the session (grouped under a named/created workspace if `workspace-name` given, else the caller's current workspace via `${AGTERM_WORKSPACE_ID:-active}`), best-effort flags it, types `claude "$(cat <prompt-file>)"` via `session type --stdin` (so only the file path — never the prompt content — passes through the typing mechanism), then `session type $'\n'` to submit. Prints the session name on success. Invoked via `bash <path>` everywhere, never relying on the executable bit.
- `agterm-handoff.sh <plan-file>`: unchanged public interface and behavior. Internally: keeps its own availability check (unchanged stderr text on that path), computes `PROJECT_ROOT`/`SLUG`/`SESSION_NAME` exactly as before, writes the same canned prompt text to a portable `mktemp` file (now via a heredoc — no more manual `'\''`-escaping, since the prompt no longer has to survive being embedded in a single-quoted shell argument), and delegates everything else to `agterm-spawn.sh` (via `bash`) in the current workspace (no `workspace-name` arg, matching prior behavior of never creating a new workspace). Left in place afterward, same as any prompt file this plan introduces — see the fire-and-forget note above.
- `spawn-session/SKILL.md`: new skill. Resolves a task prompt from either an explicit argument or the current conversation, decides on session naming and optional workspace grouping (only when the user is clearly working through multiple slices of one job), then in **one chained Bash command**: checks availability, writes the prompt to a temp file via a **quoted** heredoc (prompt text must never be shell-expanded), and calls `agterm-spawn.sh`. Explicitly documents the difference from the `Agent` tool (real independent terminal session vs. in-process background subagent) so natural-language requests like "spawn a new session for this" route here instead of to a subagent.
- The new session's terminal will visibly run `claude "$(cat /tmp/....)"` rather than showing the prompt text directly — the spawned Claude session receives and echoes the actual prompt once it starts, so this is a cosmetic difference only, worth a one-line changelog mention.

## Technical Details

### New file: `plugins/planning/scripts/agterm-spawn.sh`

```bash
#!/usr/bin/env bash
# Generic primitive: spawn a fresh agterm session and type a `claude` launch
# command into it, reading the task prompt from a file. This avoids passing
# arbitrary prompt text through the terminal-typing mechanism at all — only
# the file path is typed (as a short, known-safe command line); the new
# session's own shell does the `$(cat ...)` expansion when it runs the
# command.
#
# Shared by agterm-handoff.sh (plan-file hand-off) and spawn-session/SKILL.md
# (arbitrary task hand-off).
#
# Usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]
#   <cwd>            working directory for the new session's shell
#   <session-name>   sidebar label for the new session
#   <prompt-file>    path to a file containing the full task prompt. Left in
#                    place after this script returns — agtermctl is
#                    fire-and-forget, so there is no reliable moment at
#                    which the new session is known to have read it yet.
#   [workspace-name] if given, group the session under this named workspace
#                    (created if it doesn't exist yet). If omitted, the
#                    session opens in the caller's own current workspace,
#                    or the active session's workspace if that isn't set
#                    (e.g. when called from agterm's quick terminal).
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

CWD="${1:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
SESSION_NAME="${2:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
PROMPT_FILE="${3:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
WORKSPACE_NAME="${4:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-spawn: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "agterm-spawn: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

if [ -n "$WORKSPACE_NAME" ]; then
  SID=$(agtermctl session new --cwd "$CWD" --workspace-name "$WORKSPACE_NAME" --create-workspace --name "$SESSION_NAME" --json | jq -r '.result.id')
else
  SID=$(agtermctl session new --cwd "$CWD" --workspace "${AGTERM_WORKSPACE_ID:-active}" --name "$SESSION_NAME" --json | jq -r '.result.id')
fi

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
  echo "agterm-spawn: session new failed to return a session id" >&2
  exit 1
fi

# Flag the hand-off so it shows up in agterm's flagged sidebar / flagged
# dashboard alongside any other in-flight sessions. Best-effort: a flag
# failure must not abort a hand-off that otherwise succeeded.
agtermctl session flag on --target "$SID" >/dev/null 2>&1 || true

# %q shell-escapes the path if it needs it (spaces, etc). The prompt text
# itself never appears on this command line — it's read by the new
# session's own shell, from the file, at run time.
printf 'claude "$(cat %q)"' "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
agtermctl session type $'\n' --target "$SID"

echo "$SESSION_NAME"
```

`chmod +x plugins/planning/scripts/agterm-spawn.sh` after creating it (kept executable for local/manual runs, even though every scripted call site below invokes it via `bash`, not relying on the bit).

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
# Usage: agterm-handoff.sh <plan-file>
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
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

# Portable mktemp (no -t <prefix>, which is BSD-only and fails GNU coreutils
# on the Linux CI runner). Left in place after this script returns — see
# agterm-spawn.sh's comment on why the prompt file is never cleaned up.
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/agterm-handoff.XXXXXX")
cat > "$PROMPT_FILE" <<EOF
You have a new implementation plan to execute: $PLAN_FILE

Read it fully, then implement every task in order, following its stated
testing approach. Run the project's tests and linter before treating any
task as done.
EOF

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$SCRIPT_DIR/agterm-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE"
```

### New file: `plugins/planning/skills/spawn-session/SKILL.md`

```markdown
---
name: spawn-session
description: Hand off an arbitrary task to a freshly spawned, independent agterm session running its own `claude` process — not a background subagent. Activates on "spawn a new session for this", "hand this off to a new session", "start a separate session for this job", "delegate this to a new terminal session", "run this in a separate/parallel session", "spin up a session for this slice", or when the user is slicing a larger job into pieces to hand off one at a time.
argument-hint: "[task description]"
allowed-tools: Bash
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

## Step 3: Check availability, write the prompt, and spawn — in one command

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
PROMPT_EOF
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-spawn.sh" "$PWD" "SESSION_NAME" "$PROMPT_FILE" [WORKSPACE_NAME]
else
  echo "spawn-session: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi
```

substituting `SESSION_NAME` from Step 2, and appending `WORKSPACE_NAME`
only when grouping (omit the argument entirely otherwise).

## Step 4: Confirm

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

**Insert this shared fake once**, right before the existing
`# planning/agterm-handoff.sh` section comment. It replaces (in the next
diff below) that section's own local `FAKE_BIN` creation, and is also used
by the new `planning/agterm-spawn.sh` section:

```bash
# ---------------------------------------------------------------------------
# Shared fake agtermctl for planning/agterm-spawn.sh and
# planning/agterm-handoff.sh (agterm-handoff.sh delegates to agterm-spawn.sh
# internally, so both sections exercise the same agtermctl surface).
# ---------------------------------------------------------------------------

AGTERM_FAKE_BIN="$(mktemp -d)"
cat > "${AGTERM_FAKE_BIN}/agtermctl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${AGTERMCTL_LOG}"
if [ "$1" = "session" ] && [ "$2" = "new" ]; then
  if [ -n "${AGTERMCTL_SESSION_NEW_JSON:-}" ]; then
    echo "$AGTERMCTL_SESSION_NEW_JSON"
  else
    echo '{"result":{"id":"fake-session-id"}}'
  fi
fi
for a in "$@"; do
  if [ "$a" = "--stdin" ]; then
    # Always drain stdin so `printf | agtermctl session type --stdin ...`
    # never dies of SIGPIPE, whether or not the caller wants the content
    # captured (AGTERMCTL_TYPED unset).
    if [ -n "${AGTERMCTL_TYPED:-}" ]; then
      cat >> "${AGTERMCTL_TYPED}"
      printf '\n' >> "${AGTERMCTL_TYPED}"
    else
      cat >/dev/null
    fi
  fi
done
EOF
chmod +x "${AGTERM_FAKE_BIN}/agtermctl"
```

**New section**, right after the shared fake and before the existing
`# planning/agterm-handoff.sh` section:

```bash
# ---------------------------------------------------------------------------
# planning/agterm-spawn.sh
# ---------------------------------------------------------------------------

SPAWN_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/agterm-spawn.sh"

echo "planning/agterm-spawn.sh"

SPAWN_PROMPT_FILE="$(mktemp)"
echo "do the thing" > "$SPAWN_PROMPT_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$SPAWN_PROMPT_FILE"
)
assert_eq "prints the session name on success" "My Session" "$result"
assert_contains "creates the session in the current workspace when no workspace-name given" " --workspace ws-1" "$(cat "$LOG")"
assert_not_contains "does not pass --workspace-name when not grouping" " --workspace-name" "$(cat "$LOG")"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a claude launch command reading the prompt file" "claude \"\$(cat ${SPAWN_PROMPT_FILE}" "$TYPED_CMD"
assert_not_contains "does not type the prompt text itself" "do the thing" "$TYPED_CMD"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$SPAWN_PROMPT_FILE" "my-workspace"
)
assert_contains "groups under a named workspace when given" " --workspace-name my-workspace --create-workspace" "$(cat "$LOG")"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$SPAWN_SCRIPT" "/tmp" "name" "$SPAWN_PROMPT_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset (exit code)" "exit:1" "$result"
assert_contains "refuses to run when AGTERM_ENABLED is unset (message)" "not available" "$result"

result=$(AGTERM_ENABLED="1" PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp" "name" "/nonexistent/prompt-file" 2>&1; echo "exit:$?")
assert_contains "refuses to run when the prompt file doesn't exist (exit code)" "exit:1" "$result"
assert_contains "refuses to run when the prompt file doesn't exist (message)" "prompt file not found" "$result"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" AGTERMCTL_SESSION_NEW_JSON='{"result":{}}' \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$SPAWN_PROMPT_FILE" 2>&1; echo "exit:$?"
)
assert_contains "refuses to run when session new returns no id (exit code)" "exit:1" "$result"
assert_contains "refuses to run when session new returns no id (message)" "session new failed to return a session id" "$result"
rm -f "$LOG"

rm -f "$SPAWN_PROMPT_FILE"
```

**Replace the existing `# planning/agterm-handoff.sh` section entirely**
with this (drops its own local `FAKE_BIN`, reuses `${AGTERM_FAKE_BIN}`, adds
assertions on the typed command and the prompt file it points at):

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

### Task 1: Add the generic `agterm-spawn.sh` primitive

**Files:**
- Create: `plugins/planning/scripts/agterm-spawn.sh`
- Modify: `tests/run.sh` (insert the shared fake + `planning/agterm-spawn.sh` section from Technical Details above, before the existing `# planning/agterm-handoff.sh` section)

- [ ] Create `plugins/planning/scripts/agterm-spawn.sh` with the exact content from Technical Details above; `chmod +x` it.
- [ ] Insert the "Shared fake agtermctl" block and the new `planning/agterm-spawn.sh` test section into `tests/run.sh`, exactly as shown above, immediately before the existing `# planning/agterm-handoff.sh` section comment. Do not touch the existing handoff section yet — that's Task 2.
- [ ] Run: `bash -n plugins/planning/scripts/agterm-spawn.sh` — expect no output (syntax OK).
- [ ] Run: `bash tests/run.sh`
  Expected: all `planning/agterm-spawn.sh` assertions PASS; the pre-existing `planning/agterm-handoff.sh` assertions (still using their own old local `FAKE_BIN` at this point) also still PASS; `Results: N passed, 0 failed`.

### Task 2: Refactor `agterm-handoff.sh` into a thin wrapper

**Files:**
- Modify: `plugins/planning/scripts/agterm-handoff.sh`
- Modify: `tests/run.sh` (replace the `# planning/agterm-handoff.sh` section from Technical Details above)

- [ ] Replace `plugins/planning/scripts/agterm-handoff.sh`'s contents with the version in Technical Details above.
- [ ] Replace the `# planning/agterm-handoff.sh` section in `tests/run.sh` with the version in Technical Details above (drops the section's own local `FAKE_BIN`, reuses the shared `AGTERM_FAKE_BIN` from Task 1, adds the typed-command and prompt-file-content assertions).
- [ ] Run: `bash -n plugins/planning/scripts/agterm-handoff.sh` — expect no output.
- [ ] Run: `bash tests/run.sh`
  Expected: every `planning/agterm-handoff.sh` assertion PASSes — including the new ones verifying the typed command actually reads a real file containing the plan path and "Read it fully" — confirming the refactor didn't regress `plan`/`review-plan`/`handoff`'s behavior. `Results: N passed, 0 failed`.

### Task 3: Add the `spawn-session` skill

**Files:**
- Create: `plugins/planning/skills/spawn-session/SKILL.md`

- [ ] Create `plugins/planning/skills/spawn-session/SKILL.md` with the exact content from Technical Details above.
- [ ] Manual verification (only meaningful inside a live agterm session — skip if not currently in one, and say so): run `/planning:spawn-session "print hello world and exit"` (or trigger it via natural language, e.g. "spawn a new session that just prints hello world"). Confirm: a new agterm session appears, named `Spawn: ...`, flagged in the sidebar, and its shell runs `claude "$(cat <tmpfile>)"` producing a Claude session that receives the task prompt.

### Task 4: Version bump, changelog, README

**Files:**
- Modify: `plugins/planning/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] Bump `plugins/planning/.claude-plugin/plugin.json`'s `"version"` from `"1.13.3"` to `"1.14.0"` (minor: new component).
- [ ] Add to the top of `CHANGELOG.md` (after the `# Changelog` / intro lines, before the current `## planning 1.13.3 - 2026-08-31` entry):

  ```markdown
  ## planning 1.14.0 - 2026-08-31

  Added `spawn-session` — hand off an arbitrary task (not just a plan file)
  to a fresh, independent agterm session. Triggers from natural language
  ("spawn a new session for this", "hand this off to a separate session",
  etc.) as well as `/planning:spawn-session [task]`. Can group related
  slices of one job under a shared named workspace. The new session's
  terminal shows the launch command (`claude "$(cat <tmpfile>)"`) rather
  than the prompt text itself — cosmetic, the spawned Claude session
  receives and echoes the real prompt once it starts. Split the agterm
  hand-off script into a generic primitive (`agterm-spawn.sh`) and a thin
  plan-specific wrapper (`agterm-handoff.sh`) — no behavior change for
  `plan`/`review-plan`/`handoff`.
  ```

- [ ] In `README.md`, add a row to the `planning` skills table (after the existing `handoff` row, `README.md:84`):

  ```markdown
  | `spawn-session` | Hand off an arbitrary task (not tied to a plan file) to a fresh, independent agterm session — triggers from natural language ("spawn a new session for this", "hand this off to a separate session", etc.) as well as `/planning:spawn-session [task]`. Distinct from a background subagent: a real, visible terminal session the user can watch or drive directly. Can group related slices of one job under a shared named workspace. |
  ```

- [ ] Update the sentence right after that table (`README.md:86`, "Every agterm hand-off (`plan`, `review-plan`, `handoff`) also flags...") to read:

  ```markdown
  Every agterm hand-off (`plan`, `review-plan`, `handoff`, `spawn-session`) also flags the new session (`agtermctl session flag on`), so all in-flight implementations show up in agterm's flagged sidebar view / flagged-dashboard grid instead of having to be found and flagged by hand.
  ```

### Task 5: Verify acceptance criteria

- [ ] Verify all requirements from Goal are implemented: `spawn-session` exists, takes an arbitrary prompt, triggers from natural language, groups related slices on request, and `handoff`/`plan`/`review-plan` are unaffected.
- [ ] Run full test suite: `bash tests/run.sh` — expect `Results: N passed, 0 failed`.
- [ ] `golangci-lint run ./...` — N/A, no Go code in this repo/change; confirm via `git diff --stat` that only the files listed above changed.
- [ ] `grep -n 'agterm-spawn.sh' plugins/planning/scripts/agterm-handoff.sh` — confirm the invocation line begins with `bash "`.
- [ ] `grep -rn 'mktemp -t' plugins/` — expect 0 matches (the plan file itself still mentions the string `mktemp -t` in prose explaining the fix, so don't include it in this check).
- [ ] `grep -rn "agterm-handoff.sh" plugins/` — confirm `plan`, `review-plan`, `handoff` still reference it unchanged (no stale references to old behavior).

### Task 6: Wrap up and commit

- [ ] Update `README.md` if anything else needs it (should already be covered by Task 4).
- [ ] Update `CLAUDE.md` if new patterns discovered — likely not needed; this follows existing conventions.
- [ ] Move this plan to `docs/plans/completed/`: `mkdir -p docs/plans/completed && mv docs/plans/2026-08-31-agterm-spawn-session.md docs/plans/completed/`
- [ ] Single summary commit: all implementation changes + plan move in one commit.
- [ ] Open draft PR — invoke `planning:pr`.

## Post-Completion

*Items requiring manual intervention or external systems*

- The manual end-to-end verification in Task 3 requires a live agterm session (`AGTERM_ENABLED=1`) — if this plan is implemented outside one, flag that step as skipped rather than marking it done.
