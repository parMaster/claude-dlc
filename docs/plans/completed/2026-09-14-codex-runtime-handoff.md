# Add Codex CLI as an Alternative Runtime for spawn-session and handoff

**Goal:** Let `spawn-session` and `handoff` hand a task or plan off to a fresh agterm session running `codex` (Codex CLI) instead of always assuming `claude`, with the model/approval-mode questions mapped to whatever Codex actually exposes rather than forced into Claude's Inherit/Opus/Sonnet/Haiku shape.

**Architecture:** Factor the agent-agnostic half of `agterm-spawn.sh` (create + flag an agterm session) into a new `agterm-session-new.sh`, reused by both the existing Claude-launching `agterm-spawn.sh` and a new Codex-launching `codex-spawn.sh`. Add a `codex-handoff.sh` mirroring `agterm-handoff.sh` (sharing the canned plan prompt via a small sourced helper), and give `spawn-session`/`handoff` a new runtime-choice `AskUserQuestion` step that branches which script and which flags get used. `plan`/`review-plan` are untouched — they keep calling `agterm-handoff.sh` exactly as today.

**Tech Stack:** Bash (`set -euo pipefail`), `agtermctl`/`jq` (agterm control CLI), `claude` and `codex` CLIs, `tests/run.sh` bash test harness with a faked `agtermctl` on `PATH`.

---

## Context (from discovery)

- `plugins/planning/scripts/agterm-spawn.sh` — creates+flags an agterm session, types `claude [flags] "$(cat prompt-file)"`. Signature: `<cwd> <session-name> <prompt-file> [workspace-name] [claude-flags]`.
- `plugins/planning/scripts/agterm-handoff.sh` — thin wrapper: builds a canned "read the plan, implement it" prompt into a temp file, calls `agterm-spawn.sh` with `CLAUDE_FLAGS="--permission-mode acceptEdits"` (+ `--model` if given). Signature: `<plan-file> [model]`. Also called by `plugins/planning/skills/plan/SKILL.md` and `plugins/planning/skills/review-plan/SKILL.md` — both out of scope for this change and must keep working unmodified.
- `plugins/planning/skills/spawn-session/SKILL.md` — arbitrary-task hand-off. Step 3 asks Inherit/Opus/Sonnet/Haiku via `AskUserQuestion`, Step 4 calls `agterm-spawn.sh` directly.
- `plugins/planning/skills/handoff/SKILL.md` — plan-file hand-off, explicit-invocation only. Step 2 asks the same model question, Step 3 calls `agterm-handoff.sh`.
- `tests/run.sh` — fakes `agtermctl` on `PATH` (writes each invocation to `AGTERMCTL_LOG`, captures typed text to `AGTERMCTL_TYPED`, returns a canned `session new` JSON id). Existing sections test `agterm-spawn.sh` and `agterm-handoff.sh` against this fake.
- `README.md` — a Skill table + one paragraph document the model/permission-mode behavior shared by `plan`, `review-plan`, `handoff`, `spawn-session`.
- `plugins/planning/.claude-plugin/plugin.json` — version `1.19.1`, needs a minor bump (new capability, not a fix).
- `CHANGELOG.md` — newest-first, one `## <plugin> X.Y.Z - YYYY-MM-DD` section per bump.

**Codex CLI surface (verified locally, codex-cli 0.154.0, `/usr/local/bin/codex`):**
- `codex [OPTIONS] [PROMPT]` (top-level, not `codex exec`) launches Codex's interactive TUI seeded with a prompt — this is the direct equivalent of `claude "$(cat file)"`, matching what agterm-spawn.sh already does for Claude (a visible, drivable session, not a one-shot batch run).
- `-m, --model <MODEL>` — arbitrary model string. No tier concept (no Opus/Sonnet/Haiku equivalent).
- `-s, --sandbox <read-only|workspace-write|danger-full-access>` and `-a, --ask-for-approval <on-request|never>` are both present on the top-level `codex` command (confirmed in `codex --help` output, not just `codex exec --help`). `--sandbox workspace-write --ask-for-approval never` is the closest mapping to Claude's `--permission-mode acceptEdits`: auto-approve within the workspace sandbox, without escalating to `--dangerously-bypass-approvals-and-sandbox` (which is closer to Claude's full bypass mode and explicitly flagged "EXTREMELY DANGEROUS" in Codex's own help text).
- No general "list available models" surface was found in `codex --help`, `codex features list`, or `codex app-server --help`; this machine's own `~/.codex/config.toml` has a `model = "..."` value but that's personal/account config, not something to hardcode into the plugin (see this repo's CLAUDE.md "no personal configuration, no machine-specific settings" rule).

**Established repo convention for free-text answers in `AskUserQuestion`** (from `plugins/planning/skills/pr/SKILL.md`, Question 2/3): define a real first option plus a second, hint-labeled option (e.g. `"Enter ID"`, `"Enter title"`); the actual custom value comes from the tool's automatic "Other" free-text choice, not from clicking the hint option literally. Reused here for the Codex model question instead of guessing a preset model-name list.

## Verified Dependency Behaviors

- `agtermctl session new --cwd <dir> --workspace[-name] ... --json` (`plugins/planning/scripts/agterm-spawn.sh:51-54`, current file): returns `{"result":{"id": "..."}}`; `.result.id` may be absent/`null` on failure — existing code already treats that as a hard failure. Preserved verbatim in the extracted `agterm-session-new.sh`.
- `agtermctl session flag on --target <id>` (`agterm-spawn.sh:64`): best-effort — failures are swallowed (`|| true`) because a flag failure must not abort an otherwise-successful hand-off. Preserved verbatim.
- `agtermctl session type --stdin --target <id>` fed via `printf '...' | agtermctl session type --stdin ...`: the prompt text itself is never placed on the typed command line — only the prompt-file path is typed, and the new session's own shell does `$(cat ...)` at run time. This property must hold for the Codex path too (same mechanism, just `codex` instead of `claude` as the invoked binary).
- Test fake `agtermctl` (`tests/run.sh`, "Shared fake agtermctl" section): logs every invocation to `AGTERMCTL_LOG`, drains and optionally records `--stdin` input to `AGTERMCTL_TYPED`, returns `AGTERMCTL_SESSION_NEW_JSON` (default `{"result":{"id":"fake-session-id"}}`) for `session new`. Env vars set as a prefix on the outer `bash "$SCRIPT" ...` test invocation (`AGTERMCTL_LOG`, `AGTERMCTL_TYPED`, `PATH`) are inherited by any nested `bash <other-script>` call the script under test makes — this is already relied on today (`agterm-handoff.sh` internally shells out to `agterm-spawn.sh` and the existing tests observe the nested `agtermctl` calls in the same `LOG`/`TYPED` files), so the same pattern works unchanged when `agterm-spawn.sh`/`codex-spawn.sh` shell out to the new `agterm-session-new.sh`.

## Development Approach
- **testing approach**: Regular (code first, then tests) — matches how the existing `agterm-spawn.sh`/`agterm-handoff.sh` tests were written.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all implementation + plan move when complete
- run `bash tests/run.sh` after each script change
- `plan/SKILL.md` and `review-plan/SKILL.md` are explicitly out of scope — do not touch them, and do not change `agterm-handoff.sh`'s external signature or Claude-only behavior, since both skills call it as-is

## Technical Details

- **Script layering** (new):
  ```
  agterm-session-new.sh   <- agent-agnostic: create + flag an agterm session, print SID
       ^                        ^
       |                        |
  agterm-spawn.sh          codex-spawn.sh      <- runtime-specific: type the launch command
       ^                        ^
       |                        |
  agterm-handoff.sh         codex-handoff.sh   <- plan-file wrapper: canned prompt + accept-edits-equivalent flags
  ```
  `handoff-prompt.sh` (new, sourced not executed) supplies the one canned prompt both `agterm-handoff.sh` and `codex-handoff.sh` use, so the wording can only be defined once.
- **External signatures preserved:** `agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name] [claude-flags]` and `agterm-handoff.sh <plan-file> [model]` keep their exact current parameter lists and behavior — `plan/SKILL.md` and `review-plan/SKILL.md` call the latter and must not need any changes.
- **New scripts' signatures mirror the Claude ones exactly**, swapping only the binary/flags: `codex-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name] [codex-flags]`, `codex-handoff.sh <plan-file> [model]`.
- **Flag mapping:**
  | Claude | Codex | Used by |
  |---|---|---|
  | `--permission-mode acceptEdits` | `--sandbox workspace-write --ask-for-approval never` | `*-handoff.sh` (implementation hand-off — start working immediately) |
  | `--model <tier>` (Inherit/Opus/Sonnet/Haiku) | `--model <exact typed name>` (Inherit/free text) | both `*-spawn.sh` and `*-handoff.sh` |
  | (none — spawn-session's Claude path passes no permission-mode flag) | (none — spawn-session's Codex path passes no sandbox/approval flag) | `*-spawn.sh` via `spawn-session/SKILL.md` |

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Extract `agterm-session-new.sh`, rewrite `agterm-spawn.sh` to use it

**Files:**
- Create: `plugins/planning/scripts/agterm-session-new.sh`
- Modify: `plugins/planning/scripts/agterm-spawn.sh`
- Modify: `tests/run.sh`

- [ ] **Create `agterm-session-new.sh`** — the agent-agnostic half of the current `agterm-spawn.sh` (workspace resolution, `session new`, capture SID, `session flag on`), unchanged in behavior:

```bash
#!/usr/bin/env bash
# Generic primitive: create a fresh agterm session (optionally grouped under
# a named workspace) and flag it. Agent-agnostic — this is the part of a
# hand-off that's identical no matter which CLI process ends up typed into
# the session. Shared by agterm-spawn.sh (claude) and codex-spawn.sh (codex).
#
# Usage: agterm-session-new.sh <cwd> <session-name> [workspace-name]
#   <cwd>            working directory for the new session's shell
#   <session-name>   sidebar label for the new session
#   [workspace-name] if given, group the session under this named workspace
#                    (created if it doesn't exist yet). If omitted, the
#                    session opens in the caller's own current workspace, or
#                    the active session's workspace if that isn't set (e.g.
#                    when called from agterm's quick terminal).
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's id to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

CWD="${1:?usage: agterm-session-new.sh <cwd> <session-name> [workspace-name]}"
SESSION_NAME="${2:?usage: agterm-session-new.sh <cwd> <session-name> [workspace-name]}"
WORKSPACE_NAME="${3:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-session-new: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

if [ -n "$WORKSPACE_NAME" ]; then
  SID=$(agtermctl session new --cwd "$CWD" --workspace-name "$WORKSPACE_NAME" --create-workspace --name "$SESSION_NAME" --json | jq -r '.result.id')
else
  SID=$(agtermctl session new --cwd "$CWD" --workspace "${AGTERM_WORKSPACE_ID:-active}" --name "$SESSION_NAME" --json | jq -r '.result.id')
fi

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
  echo "agterm-session-new: session new failed to return a session id" >&2
  exit 1
fi

# Flag the hand-off so it shows up in agterm's flagged sidebar / flagged
# dashboard alongside any other in-flight sessions. Best-effort: a flag
# failure must not abort a hand-off that otherwise succeeded.
agtermctl session flag on --target "$SID" >/dev/null 2>&1 || true

echo "$SID"
```

- [ ] **Rewrite `agterm-spawn.sh`** to call it for the SID, keeping its own external signature, checks, and typed-command behavior identical to today:

```bash
#!/usr/bin/env bash
# Spawn a fresh agterm session and type a `claude` launch command into it,
# reading the task prompt from a file. This avoids passing arbitrary prompt
# text through the terminal-typing mechanism at all — only the file path is
# typed (as a short, known-safe command line); the new session's own shell
# does the `$(cat ...)` expansion when it runs the command.
#
# Shared by agterm-handoff.sh (plan-file hand-off) and spawn-session/SKILL.md
# (arbitrary task hand-off). Session creation itself (workspace resolution,
# `agtermctl session new`, flagging) is agent-agnostic and lives in
# agterm-session-new.sh, reused by codex-spawn.sh for the Codex runtime.
#
# Usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name] [claude-flags]
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
#                    (e.g. when called from agterm's quick terminal). Pass ""
#                    to skip grouping while still supplying claude-flags.
#   [claude-flags]   extra flags inserted into the `claude` launch command,
#                    e.g. "--permission-mode acceptEdits". Caller-controlled,
#                    fixed literal — never built from untrusted input.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

CWD="${1:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
SESSION_NAME="${2:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
PROMPT_FILE="${3:?usage: agterm-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
WORKSPACE_NAME="${4:-}"
CLAUDE_FLAGS="${5:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-spawn: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "agterm-spawn: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SID=$(bash "$SCRIPT_DIR/agterm-session-new.sh" "$CWD" "$SESSION_NAME" "$WORKSPACE_NAME")

# %q shell-escapes the path if it needs it (spaces, etc). The prompt text
# itself never appears on this command line — it's read by the new
# session's own shell, from the file, at run time.
if [ -n "$CLAUDE_FLAGS" ]; then
  printf 'claude %s "$(cat %q)"' "$CLAUDE_FLAGS" "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
else
  printf 'claude "$(cat %q)"' "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
fi
agtermctl session type $'\n' --target "$SID"

echo "$SESSION_NAME"
```

- [ ] **Run existing tests to confirm the refactor is behavior-preserving:**

  Run: `bash tests/run.sh 2>&1 | sed -n '/planning\/agterm-spawn.sh/,/planning\/agterm-handoff.sh/p'`
  Expected: every `agterm-spawn.sh` PASS line still passes unmodified — the refactor changes only where the `agtermctl session new`/`flag` calls happen (now inside a nested `agterm-session-new.sh` process), not what gets logged to `AGTERMCTL_LOG`/`AGTERMCTL_TYPED` or the error message substrings the tests grep for.

- [ ] **Add `agterm-session-new.sh` test section to `tests/run.sh`**, placed right after the "Shared fake agtermctl" block and before the existing "planning/agterm-spawn.sh" section (so the shared `AGTERM_FAKE_BIN` fake is already built):

```bash
# ---------------------------------------------------------------------------
# planning/agterm-session-new.sh
# ---------------------------------------------------------------------------

SESSION_NEW_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/agterm-session-new.sh"

echo "planning/agterm-session-new.sh"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SESSION_NEW_SCRIPT" "/tmp/some/dir" "My Session"
)
assert_eq "prints the session id on success" "fake-session-id" "$result"
assert_contains "creates the session in the current workspace when no workspace-name given" " --workspace ws-1" "$(cat "$LOG")"
assert_not_contains "does not pass --workspace-name when not grouping" " --workspace-name" "$(cat "$LOG")"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
rm -f "$LOG"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SESSION_NEW_SCRIPT" "/tmp/some/dir" "My Session" "my-workspace"
)
assert_contains "groups under a named workspace when given" " --workspace-name my-workspace --create-workspace" "$(cat "$LOG")"
rm -f "$LOG"

result=$(AGTERM_ENABLED="" bash "$SESSION_NEW_SCRIPT" "/tmp" "name" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset (exit code)" "exit:1" "$result"
assert_contains "refuses to run when AGTERM_ENABLED is unset (message)" "not available" "$result"

LOG="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" AGTERMCTL_SESSION_NEW_JSON='{"result":{}}' \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$SESSION_NEW_SCRIPT" "/tmp/some/dir" "My Session" 2>&1; echo "exit:$?"
)
assert_contains "refuses to run when session new returns no id (exit code)" "exit:1" "$result"
assert_contains "refuses to run when session new returns no id (message)" "session new failed to return a session id" "$result"
rm -f "$LOG"

```

- [ ] **Run tests to verify all pass**

  Run: `bash tests/run.sh`
  Expected: PASS — all `planning/agterm-session-new.sh` and `planning/agterm-spawn.sh` assertions pass, nothing else regresses.

### Task 2: Add `codex-spawn.sh`

**Files:**
- Create: `plugins/planning/scripts/codex-spawn.sh`
- Modify: `tests/run.sh`

- [ ] **Create `codex-spawn.sh`** — the Codex counterpart to `agterm-spawn.sh`, reusing `agterm-session-new.sh`:

```bash
#!/usr/bin/env bash
# Spawn a fresh agterm session and type a `codex` launch command into it,
# reading the task prompt from a file — the Codex CLI counterpart to
# agterm-spawn.sh. Same file-based prompt hand-off and the same
# session-creation primitive (agterm-session-new.sh); only the launched
# binary and its flags differ.
#
# Shared by codex-handoff.sh (plan-file hand-off) and spawn-session/SKILL.md
# (arbitrary task hand-off, Codex runtime).
#
# Usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name] [codex-flags]
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
#                    (e.g. when called from agterm's quick terminal). Pass ""
#                    to skip grouping while still supplying codex-flags.
#   [codex-flags]    extra flags inserted into the `codex` launch command,
#                    e.g. "--sandbox workspace-write --ask-for-approval
#                    never". Caller-controlled, fixed literal — never built
#                    from untrusted input.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

CWD="${1:?usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
SESSION_NAME="${2:?usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
PROMPT_FILE="${3:?usage: codex-spawn.sh <cwd> <session-name> <prompt-file> [workspace-name]}"
WORKSPACE_NAME="${4:-}"
CODEX_FLAGS="${5:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "codex-spawn: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "codex-spawn: prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SID=$(bash "$SCRIPT_DIR/agterm-session-new.sh" "$CWD" "$SESSION_NAME" "$WORKSPACE_NAME")

# %q shell-escapes the path if it needs it (spaces, etc). The prompt text
# itself never appears on this command line — it's read by the new
# session's own shell, from the file, at run time.
if [ -n "$CODEX_FLAGS" ]; then
  printf 'codex %s "$(cat %q)"' "$CODEX_FLAGS" "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
else
  printf 'codex "$(cat %q)"' "$PROMPT_FILE" | agtermctl session type --stdin --target "$SID"
fi
agtermctl session type $'\n' --target "$SID"

echo "$SESSION_NAME"
```

- [ ] **Add `codex-spawn.sh` test section to `tests/run.sh`**, right after the `planning/agterm-spawn.sh` section:

```bash
# ---------------------------------------------------------------------------
# planning/codex-spawn.sh
# ---------------------------------------------------------------------------

CODEX_SPAWN_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/codex-spawn.sh"

echo "planning/codex-spawn.sh"

CODEX_SPAWN_PROMPT_FILE="$(mktemp)"
echo "do the thing" > "$CODEX_SPAWN_PROMPT_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$CODEX_SPAWN_PROMPT_FILE"
)
assert_eq "prints the session name on success" "My Session" "$result"
assert_contains "creates the session in the current workspace when no workspace-name given" " --workspace ws-1" "$(cat "$LOG")"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a codex launch command reading the prompt file" "codex \"\$(cat ${CODEX_SPAWN_PROMPT_FILE}" "$TYPED_CMD"
assert_not_contains "does not type the prompt text itself" "do the thing" "$TYPED_CMD"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$CODEX_SPAWN_PROMPT_FILE" "my-workspace"
)
assert_contains "groups under a named workspace when given" " --workspace-name my-workspace --create-workspace" "$(cat "$LOG")"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp/some/dir" "My Session" "$CODEX_SPAWN_PROMPT_FILE" "" "--sandbox workspace-write --ask-for-approval never"
)
assert_contains "inserts codex-flags into the launch command when given" 'codex --sandbox workspace-write --ask-for-approval never "$(cat ' "$(cat "$TYPED")"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$CODEX_SPAWN_SCRIPT" "/tmp" "name" "$CODEX_SPAWN_PROMPT_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset (exit code)" "exit:1" "$result"
assert_contains "refuses to run when AGTERM_ENABLED is unset (message)" "not available" "$result"

result=$(AGTERM_ENABLED="1" PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_SPAWN_SCRIPT" "/tmp" "name" "/nonexistent/prompt-file" 2>&1; echo "exit:$?")
assert_contains "refuses to run when the prompt file doesn't exist (exit code)" "exit:1" "$result"
assert_contains "refuses to run when the prompt file doesn't exist (message)" "prompt file not found" "$result"

rm -f "$CODEX_SPAWN_PROMPT_FILE"

```

- [ ] **Run tests to verify all pass**

  Run: `bash tests/run.sh`
  Expected: PASS — new `planning/codex-spawn.sh` assertions pass, nothing else regresses.

### Task 3: Share the canned plan prompt, rewrite `agterm-handoff.sh`, add `codex-handoff.sh`

**Files:**
- Create: `plugins/planning/scripts/handoff-prompt.sh`
- Create: `plugins/planning/scripts/codex-handoff.sh`
- Modify: `plugins/planning/scripts/agterm-handoff.sh`
- Modify: `tests/run.sh`

- [ ] **Create `handoff-prompt.sh`** (sourced, not executed — no shebang execution path, but keep one for editor/shellcheck clarity):

```bash
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
```

- [ ] **Rewrite `agterm-handoff.sh`** to source it — output must be byte-identical to today's inline heredoc:

```bash
#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session running `claude`,
# in the caller's own workspace. Shared by plan/SKILL.md, review-plan/SKILL.md,
# and handoff/SKILL.md so the agtermctl sequence lives in one place instead of
# three copies. Thin wrapper around the generic agterm-spawn.sh: builds the
# canned plan-hand-off prompt into a temp file and hands off in the current
# workspace (no workspace grouping — matches this script's prior behavior).
#
# Usage: agterm-handoff.sh <plan-file> [model]
#   [model]                model alias (e.g. "opus", "sonnet", "haiku") to run
#                          the new session on, passed through as `--model`.
#                          Omit (or pass "") to inherit whatever `claude`
#                          launches with by default.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Implement: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: agterm-handoff.sh <plan-file> [model]}"
MODEL="${2:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "agterm-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Implement: $SLUG"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/handoff-prompt.sh"

# Portable mktemp (no -t <prefix>, which is BSD-only and fails GNU coreutils
# on the Linux CI runner). Left in place after this script returns — see
# agterm-spawn.sh's comment on why the prompt file is never cleaned up.
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/agterm-handoff.XXXXXX")
build_handoff_prompt "$PLAN_FILE" > "$PROMPT_FILE"

CLAUDE_FLAGS="--permission-mode acceptEdits"
if [ -n "$MODEL" ]; then
  CLAUDE_FLAGS="$CLAUDE_FLAGS --model $MODEL"
fi

# Implementation hand-offs start in accept-edits mode: the whole point is to
# implement the plan, not to re-ask permission for every edit along the way.
bash "$SCRIPT_DIR/agterm-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE" "" "$CLAUDE_FLAGS"
```

- [ ] **Run existing tests to confirm this refactor is behavior-preserving:**

  Run: `bash tests/run.sh 2>&1 | sed -n '/planning\/agterm-handoff.sh/,$p'`
  Expected: every `agterm-handoff.sh` PASS line still passes unmodified, including the prompt-content assertions (`build_handoff_prompt` produces the exact same text as the old inline heredoc).

- [ ] **Create `codex-handoff.sh`**, mirroring the rewritten `agterm-handoff.sh` but launching `codex` with the sandbox/approval mapping instead of `--permission-mode acceptEdits`:

```bash
#!/usr/bin/env bash
# Hand off an implementation plan to a fresh agterm session running `codex`,
# in the caller's own workspace — the Codex CLI counterpart to
# agterm-handoff.sh. Shares the same canned plan-hand-off prompt (built by
# handoff-prompt.sh) so the wording can't drift between the two runtimes;
# only the launched binary and its flags differ.
#
# Usage: codex-handoff.sh <plan-file> [model]
#   [model]                exact Codex model name (e.g. "gpt-5.1-codex") to
#                          run the new session on, passed through as
#                          `--model`. Omit (or pass "") to use whatever model
#                          Codex is configured to use by default.
# Requires: AGTERM_ENABLED=1, agtermctl and jq on PATH.
# On success: prints the new session's display name (e.g. "Implement: foo")
# to stdout, exits 0.
# On failure: prints a one-line reason to stderr, exits 1.

set -euo pipefail

PLAN_FILE="${1:?usage: codex-handoff.sh <plan-file> [model]}"
MODEL="${2:-}"

if [ "${AGTERM_ENABLED:-}" != "1" ] || ! command -v agtermctl >/dev/null 2>&1; then
  echo "codex-handoff: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
SLUG=$(basename "$PLAN_FILE" .md | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
SESSION_NAME="Implement: $SLUG"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/handoff-prompt.sh"

PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex-handoff.XXXXXX")
build_handoff_prompt "$PLAN_FILE" > "$PROMPT_FILE"

CODEX_FLAGS="--sandbox workspace-write --ask-for-approval never"
if [ -n "$MODEL" ]; then
  CODEX_FLAGS="$CODEX_FLAGS --model $MODEL"
fi

# Implementation hand-offs start in accept-edits mode. Codex's nearest
# equivalent to Claude's --permission-mode acceptEdits is a workspace-write
# sandbox with approval turned off, rather than escalating all the way to
# --dangerously-bypass-approvals-and-sandbox.
bash "$SCRIPT_DIR/codex-spawn.sh" "$PROJECT_ROOT" "$SESSION_NAME" "$PROMPT_FILE" "" "$CODEX_FLAGS"
```

- [ ] **Add `codex-handoff.sh` test section to `tests/run.sh`**, right after the `planning/agterm-handoff.sh` section:

```bash
# ---------------------------------------------------------------------------
# planning/codex-handoff.sh
# ---------------------------------------------------------------------------

CODEX_HANDOFF_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/codex-handoff.sh"

echo "planning/codex-handoff.sh"

CODEX_TEST_REPO="$(mktemp -d)"
(cd "$CODEX_TEST_REPO" && git init -q)
CODEX_PLAN_FILE="${CODEX_TEST_REPO}/docs/plans/2026-01-01-example.md"
mkdir -p "$(dirname "$CODEX_PLAN_FILE")"
echo "# Example plan" > "$CODEX_PLAN_FILE"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$CODEX_TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE"
)
assert_eq "prints the new session's display name on success" "Implement: example" "$result"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
assert_contains "creates the session before flagging" "session new" "$(cat "$LOG")"
TYPED_CMD="$(cat "$TYPED")"
assert_contains "types a codex launch command with the accept-edits-equivalent flags" 'codex --sandbox workspace-write --ask-for-approval never "$(cat ' "$TYPED_CMD"
PROMPT_PATH="${TYPED_CMD#*cat }"
PROMPT_PATH="${PROMPT_PATH%)\"}"
assert_eq "the prompt file the typed command reads actually exists" "yes" "$([ -f "$PROMPT_PATH" ] && echo yes || echo no)"
PROMPT_CONTENT="$(cat "$PROMPT_PATH" 2>/dev/null || echo "")"
assert_contains "prompt file references the plan path" "$CODEX_PLAN_FILE" "$PROMPT_CONTENT"
assert_contains "prompt file tells the session to read the plan fully" "Read it fully" "$PROMPT_CONTENT"
rm -f "$LOG" "$TYPED"

LOG="$(mktemp)"
TYPED="$(mktemp)"
result=$(
  cd "$CODEX_TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERMCTL_TYPED="$TYPED" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${AGTERM_FAKE_BIN}:${PATH}" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE" "gpt-5.1-codex"
)
assert_contains "appends --model when a model is given" 'codex --sandbox workspace-write --ask-for-approval never --model gpt-5.1-codex "$(cat ' "$(cat "$TYPED")"
rm -f "$LOG" "$TYPED"

result=$(AGTERM_ENABLED="" bash "$CODEX_HANDOFF_SCRIPT" "$CODEX_PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"

rm -rf "$CODEX_TEST_REPO"

```

- [ ] **Run tests to verify all pass**

  Run: `bash tests/run.sh`
  Expected: PASS — new `planning/codex-handoff.sh` assertions pass, `planning/agterm-handoff.sh` assertions still pass unmodified, nothing else regresses.

### Task 4: `spawn-session/SKILL.md` — runtime choice

**Files:**
- Modify: `plugins/planning/skills/spawn-session/SKILL.md`

- [ ] **Insert a new Step 3 ("Choose a runtime") before the existing model-choice step, renumber and branch the rest.** Replace the file's Step 3 through Step 5 (current lines 31-79) with:

```markdown
## Step 3: Choose a runtime

Ask with `AskUserQuestion` — question "Which CLI should the new session run?",
header "Runtime", single-select, options:

- **Claude** (Recommended) — a `claude` process, matching this session
- **Codex** — a `codex` process (Codex CLI)

## Step 4: Choose a model

**If Claude was chosen**, ask with `AskUserQuestion` — question "Which model
should the new session use?", header "Model", single-select, options:

- **Inherit** — whatever `claude` launches with by default
- **Opus** — most capable; complex or subtle work
- **Sonnet** — faster and cheaper; straightforward tasks
- **Haiku** — fastest and cheapest; simple mechanical changes

`MODEL_FLAGS` is `--model <lower-cased label>`, or empty for **Inherit**.

**If Codex was chosen**, ask with `AskUserQuestion` — question "Which model
should the new Codex session use?", header "Model", single-select, options:

- **Inherit** (Recommended) — no `-m` flag; Codex uses whatever model it's
  configured to use by default
- **Enter a model name** — type the exact Codex model name (e.g. as shown in
  `codex --help` or your `~/.codex/config.toml`) via the "Other" free-text
  choice; Codex has no built-in model tiers to pick from instead

`MODEL_FLAGS` is `--model <exact text the user provided>`, or empty for
**Inherit**. Never guess or substitute a model name of your own — use exactly
what the user typed.

## Step 5: Write the prompt and spawn — in one command

One chained Bash call: a step gets a fresh shell, so `$PROMPT_FILE` is gone by
the next call (and one call means one approval prompt, one focus steal). The
heredoc must be **quoted** (`<<'PROMPT_EOF'`) so the prompt text isn't shell-
expanded. Don't delete the temp file — agtermctl is fire-and-forget, so the
new session may not have read it yet. Don't pre-check agterm availability; the
script does that and exits non-zero with a reason.

```bash
PROMPT_FILE=$(mktemp "${TMPDIR:-/tmp}/agterm-spawn.XXXXXX")
cat > "$PROMPT_FILE" <<'PROMPT_EOF'
<task prompt from Step 1>
PROMPT_EOF
bash "${CLAUDE_PLUGIN_ROOT}/scripts/SPAWN_SCRIPT" "$PWD" "SESSION_NAME" "$PROMPT_FILE" [WORKSPACE_NAME] [MODEL_FLAGS]
```

`SPAWN_SCRIPT` is `agterm-spawn.sh` for the Claude runtime, `codex-spawn.sh`
for the Codex runtime. Arguments are positional, so a skipped workspace still
needs its slot:

```bash
# Claude, grouped, model chosen
... "$PWD" "Spawn: parser" "$PROMPT_FILE" "Refactor" "--model opus"
# Codex, ungrouped, model chosen
... "$PWD" "Spawn: parser" "$PROMPT_FILE" "" "--model gpt-5.1-codex"
# Claude, ungrouped, Inherit
... "$PWD" "Spawn: parser" "$PROMPT_FILE"
```

## Step 6: Report the outcome

Exit 0: the last stdout line is the new session's display name. Report the
hand-off with that name, the runtime (Claude/Codex), the workspace if
grouped, the model unless Inherit, and that the user can switch to it.
Non-zero: report the failure, quoting stderr; if it's the "not available"
message, ask whether they want a background subagent instead of silently
falling back to one.

Either way, stop — do not implement the task in this session.
```

- [ ] **Sanity-check the frontmatter still matches** — `allowed-tools: Bash, AskUserQuestion` (unchanged; no new tool needed, still just Bash + AskUserQuestion).

### Task 5: `handoff/SKILL.md` — runtime choice

**Files:**
- Modify: `plugins/planning/skills/handoff/SKILL.md`

- [ ] **Insert the same runtime-choice step before the model-choice step, and branch Step 3's script call.** Replace the file's "Step 2" through "Step 3" (current lines 30-56) with:

```markdown
## Step 2: Choose a runtime

Ask with `AskUserQuestion` — question "Which CLI should the new session run?",
header "Runtime", single-select, options:

- **Claude** (Recommended) — a `claude` process, matching this session
- **Codex** — a `codex` process (Codex CLI)

## Step 3: Choose a model

**If Claude was chosen**, ask with `AskUserQuestion` — question "Which model
should the new session use?", header "Model", single-select, options:

- **Inherit** — whatever `claude` launches with by default
- **Opus** — most capable; complex or subtle implementations
- **Sonnet** — faster and cheaper; straightforward plans
- **Haiku** — fastest and cheapest; simple mechanical changes

`MODEL` is the lower-cased label, or an empty string for **Inherit**.

**If Codex was chosen**, ask with `AskUserQuestion` — question "Which model
should the new Codex session use?", header "Model", single-select, options:

- **Inherit** (Recommended) — no `-m` flag; Codex uses whatever model it's
  configured to use by default
- **Enter a model name** — type the exact Codex model name (e.g. as shown in
  `codex --help` or your `~/.codex/config.toml`) via the "Other" free-text
  choice; Codex has no built-in model tiers to pick from instead

`MODEL` is exactly what the user typed, or an empty string for **Inherit**.
Never guess or substitute a model name of your own.

## Step 4: Hand off

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/HANDOFF_SCRIPT" "PLAN_FILE" "MODEL"
```

`HANDOFF_SCRIPT` is `agterm-handoff.sh` for the Claude runtime,
`codex-handoff.sh` for the Codex runtime.

```bash
# Claude, model chosen
... agterm-handoff.sh "docs/plans/2026-09-09-foo.md" "opus"
# Codex, model chosen
... codex-handoff.sh "docs/plans/2026-09-09-foo.md" "gpt-5.1-codex"
# Codex, Inherit
... codex-handoff.sh "docs/plans/2026-09-09-foo.md" ""
```

The script checks agterm availability itself; don't pre-check. On non-zero
exit, report its stderr and stop.
```

- [ ] **Renumber the old "Step 4: Report the outcome" to "Step 5"** and update its first sentence to mention the runtime:

```markdown
## Step 5: Report the outcome

On success, the script's last stdout line is the new session's display name
(e.g. `Implement: foo`) — tell the user: implementation has been handed off
to a new agterm session with that name, running the chosen runtime (Claude or
Codex), in this same workspace (noting the chosen model, unless Inherit), and
they can switch to it to watch or drive it directly. Stop completely.
```

- [ ] **Sanity-check the frontmatter still matches** — today's `handoff/SKILL.md` frontmatter is `allowed-tools: Bash` even though its existing model-choice step already calls `AskUserQuestion` (a pre-existing gap, not introduced by this change). This plan adds a second `AskUserQuestion` call (runtime choice), so fix the gap now: check the current frontmatter and add `AskUserQuestion` if it's missing.

  Run: `grep -n "allowed-tools" plugins/planning/skills/handoff/SKILL.md`
  If the line doesn't already include `AskUserQuestion`, add it.

### Task 6: Update `README.md`, `CHANGELOG.md`, `plugin.json`

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `plugins/planning/.claude-plugin/plugin.json`

- [ ] **Update the `handoff` row** in `README.md`'s planning skill table (currently the line starting `| \`handoff\` |`):

```markdown
| `handoff` | Explicit-only hand-off of a plan straight to a fresh agterm session, skipping `plan`/`review-plan`'s menus entirely — `/planning:handoff [plan-file]` (defaults to the most recent plan under `docs/plans/` if omitted). Asks which CLI to run the hand-off on — Claude or Codex — before the model question. Never triggers from natural language (`disable-model-invocation: true`). |
```

- [ ] **Update the `spawn-session` row:**

```markdown
| `spawn-session` | Hand off an arbitrary task (not tied to a plan file) to a fresh, independent agterm session — triggers from natural language ("spawn a new session for this", "hand this off to a separate session", etc.) as well as `/planning:spawn-session [task]`. Asks which CLI to run it on — Claude or Codex — before the model question. Distinct from a background subagent: a real, visible terminal session the user can watch or drive directly. Can group related slices of one job under a shared named workspace. |
```

- [ ] **Replace the paragraph directly below the table** (currently starting "Every agterm hand-off (`plan`, `review-plan`, `handoff`, `spawn-session`) asks which model...") with:

```markdown
Every agterm hand-off (`plan`, `review-plan`, `handoff`, `spawn-session`) flags the new session (`agtermctl session flag on`), so all in-flight implementations show up in agterm's flagged sidebar view / flagged-dashboard grid instead of having to be found and flagged by hand. `plan` and `review-plan` always launch a `claude` process; `handoff` and `spawn-session` first ask which CLI to run — Claude or Codex. On the Claude path, the model question is the existing Inherit/Opus/Sonnet/Haiku choice, passed through as `claude --model`; on the Codex path it's Inherit or a free-typed model name (via the `AskUserQuestion` "Other" input), passed through as `codex --model` — Codex has no built-in model tiers to choose from. The two that hand off plan implementation (`handoff`, and `plan`/`review-plan`'s "Implement in a Separate Session") launch the new session in accept-edits mode so it starts implementing right away instead of asking permission for every edit — `claude --permission-mode acceptEdits` on the Claude path, `codex --sandbox workspace-write --ask-for-approval never` on the Codex path (Codex has no direct equivalent of `acceptEdits`, so this is the closest mapping: auto-approve within the workspace sandbox without escalating further); `spawn-session` hands off arbitrary tasks and starts with each CLI's own default permission/approval mode.
```

- [ ] **Bump `plugins/planning/.claude-plugin/plugin.json`** version from `1.19.1` to `1.20.0` (minor — new capability, not a fix):

```json
  "version": "1.20.0",
```

- [ ] **Add a `CHANGELOG.md` entry**, inserted above the existing `## planning 1.19.1 - 2026-09-14` section (newest first):

```markdown
## planning 1.20.0 - 2026-09-14

Adds Codex CLI as an alternative runtime for `spawn-session` and `handoff`,
so a task or plan can be handed to a fresh `codex` session instead of always
assuming `claude`. Both skills ask which CLI to run before the model
question. `agterm-spawn.sh`'s session-creation logic (workspace resolution,
`agtermctl session new`, flagging) is factored into a new agent-agnostic
`agterm-session-new.sh`, reused by a new `codex-spawn.sh`; the canned
plan-hand-off prompt is factored into a sourced `handoff-prompt.sh`, reused
by a new `codex-handoff.sh` alongside the existing `agterm-handoff.sh`.
Codex has no Opus/Sonnet/Haiku-style model tiers, so its model question is
Inherit-or-free-text instead of a fixed list; its nearest equivalent to
`--permission-mode acceptEdits` is `--sandbox workspace-write
--ask-for-approval never`, confirmed against `codex --help` output rather
than guessed. `plan` and `review-plan` are unchanged — both still hand off
to `claude` only, via the untouched `agterm-handoff.sh` signature.
```

- [ ] **Run tests to verify nothing regresses from the doc/version-only changes**

  Run: `bash tests/run.sh`
  Expected: PASS (no test touches README/CHANGELOG/plugin.json, this just confirms the run is still clean before the final task)

### Task 7: Verify acceptance criteria, wrap up, commit

- [ ] Verify all requirements from the Goal are implemented:
  - `spawn-session` and `handoff` both ask Claude-vs-Codex before the model question
  - `codex-spawn.sh` and `codex-handoff.sh` exist, mirror the Claude scripts' external shape
  - `agterm-session-new.sh` is the single place session creation/flagging happens, reused by both `*-spawn.sh` scripts
  - `handoff-prompt.sh` is the single place the canned plan prompt is defined, reused by both `*-handoff.sh` scripts
  - `agterm-handoff.sh`'s external signature and Claude-only behavior are unchanged; `plan/SKILL.md` and `review-plan/SKILL.md` were not touched
  - README.md, CHANGELOG.md, plugin.json all updated
- [ ] Run full test suite: `bash tests/run.sh`
  - if failures look like shared-state flakiness — an assertion fails against a resource another test seems to have touched, or results aren't reproducible when a test is run alone — investigate the shared `AGTERM_FAKE_BIN`/temp-file setup for a leaked or reused path before treating it as a genuine regression
- [ ] `git status` / `git diff` review: confirm no stray files (e.g. leftover `/tmp` test artifacts committed by accident) are staged
- [ ] Before the final commit, check whether `main` is behind its remote tracking branch (`git fetch` then `git status`) and resync if needed (`git pull --rebase`)
- [ ] Update README.md further if anything discovered during implementation diverged from Task 6 (e.g. exact wording); update CLAUDE.md only if a new *pattern* was introduced (unlikely here — this follows existing conventions)
- [ ] Move this plan to `docs/plans/completed/`: `mkdir -p docs/plans/completed && mv docs/plans/2026-09-14-codex-runtime-handoff.md docs/plans/completed/`
- [ ] Single summary commit: all implementation changes + plan move in one commit. Do **not** push — leave the commit local for review.

## Post-Completion
*Items requiring manual intervention or external systems*

- The Codex-path flag mapping (`--sandbox workspace-write --ask-for-approval never` for accept-edits, `--model` for model selection) was verified against `codex --help` on one machine (codex-cli 0.154.0). If a future Codex CLI release renames or removes these flags, `codex-spawn.sh`/`codex-handoff.sh` will need a follow-up update — nothing in this plan pins or checks the installed Codex version.
- No attempt was made to enumerate valid Codex model names for the user — the "Enter a model name" step relies entirely on the user typing something Codex will accept; a typo surfaces only when the spawned `codex` process itself rejects it.
