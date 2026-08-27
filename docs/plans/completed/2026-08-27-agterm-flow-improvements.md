# Agterm Flow Improvements

**Goal:** Improve the plan → implement agterm hand-off flow with two additions: auto-flag every hand-off session so it's visible in agterm's flagged sidebar/dashboard, and a new `agterm-hooks` plugin that flags any agterm-hosted Claude Code session `completed`/`blocked` in the sidebar (with sound) when it stops responding or needs attention.

**Architecture:** (1) One extra `agtermctl session flag on` call in the existing shared `agterm-handoff.sh` script. (2) A new, small, planning-independent plugin with two shell-script hooks (`Stop`, `Notification`) that call `agtermctl session status` — guarded by `AGTERM_ENABLED` so they no-op entirely outside agterm.

**Tech Stack:** bash, `agtermctl` (agterm's control CLI), Claude Code plugin hooks (`hooks.json`), the repo's existing `tests/run.sh` bash test harness.

---

## Context (from discovery)

- `plugins/planning/scripts/agterm-handoff.sh` — shared by `plan`, `review-plan`, `implement-in-session`; creates the new agterm session, types the implementation prompt, prints the session name. This is where the auto-flag call goes.
- `plugins/go-tools/hooks/hooks.json` and `plugins/global-rules/scripts/block-root-find.sh` — existing hook conventions in this repo: `hooks.json` registers `command` hooks pointing at `${CLAUDE_PLUGIN_ROOT}/hooks/...`; hook scripts are either python3 (go-tools) or bash (global-rules), both plain executable scripts, no framework.
- `tests/run.sh` — the repo's only test harness (run via `bash tests/run.sh`, wired into `.github/workflows/test.yml`). Tests plugin scripts by faking `HOME`/`CLAUDE_PLUGIN_ROOT`/`PATH` and asserting on side effects (files written, JSON stdout). New hook tests follow this same pattern: put a fake `agtermctl` on `PATH` that records its invocation, then assert on what got recorded.
- `agtermctl` reference (`~/.claude/skills/agterm/reference.md`, agterm's own CLI documentation — not part of this repo): documents `session flag [on|off|toggle|clear] --target`, `session status <idle|active|completed|blocked> [--blink] [--auto-reset] [--sound NAME] --target`, and confirms `AGTERM_ENABLED`/`AGTERM_SESSION_ID` are set in every shell agterm spawns (so a hook script that's a child of that shell inherits them).
- `README.md` documents each plugin under `## Plugins` with an install line and a hook/skill table (see `### go-tools`, `### global-rules` for the hook-table format this plan follows).
- `CHANGELOG.md` — one `## <plugin> vX.Y.Z - YYYY-MM-DD` heading per version bump, newest first.
- `.claude-plugin/marketplace.json` — flat `plugins` array, `{name, source, description}` per plugin; new plugins are appended.

## Verified Dependency Behaviors

*External CLI (`agtermctl`) this plan calls — behavior verified against its own reference documentation (`~/.claude/skills/agterm/reference.md`), since it's a separate compiled app with no source in this repo.*

- `agtermctl session flag on --target <id>` (reference.md `## session`): flags the target session for the flagged working-set view; a "durable, persisted membership"; `on` is idempotent (safe to call even if already flagged). No output needed on success.
- `agtermctl session status <state> [--sound NAME] [--auto-reset] --target <id>` (reference.md `## session`): sets the sidebar agent-status glyph on the target session. `completed`/`blocked` are valid states. `--auto-reset` clears it back to `idle` once the session is next visited (a one-shot flash, not a state you have to manually clear). `--sound NAME` plays a one-shot sound (`default` = system alert sound); *without* `--sound`, a `blocked` status instead plays the user's own configured "Blocked sound" setting if they set one, and plays nothing if they didn't. Doc: "Setting non-idle is for agents/hooks; `idle` clears it."
- Every shell agterm spawns gets `AGTERM_ENABLED=1`, `AGTERM_SESSION_ID=<uuid of this session>` in its environment (reference.md, "AGTERM_* environment"). A Claude Code hook command runs as a child process of that shell, so it inherits both — no extra plumbing needed to know which session to target.

These three facts are why the hooks can be simple: `flag on` needs no idempotency guard, `--target "$AGTERM_SESSION_ID"` is always correct without a lookup step, and `--auto-reset` means there's no separate "clear the glyph" hook to also write.

## Development Approach

- **testing approach**: Regular (code first, then tests) — matches how `tests/run.sh`'s existing suites were built (write the script, then add assertions against its behavior).
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task that adds a script MUST include matching `tests/run.sh` assertions**
- **CRITICAL: `bash tests/run.sh` must pass before starting the next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all implementation + plan move when complete
- **CRITICAL: every plugin whose bundled content changes gets its `version` bumped and `CHANGELOG.md` updated in the same commit** (`planning` → patch/minor bump for the `agterm-handoff.sh` change; `agterm-hooks` → new plugin at `1.0.0`)
- there is no Go/Node linter in this repo (it's shell + JSON + markdown) — validate JSON files with `jq .` and shell scripts by running them under the test harness

## Solution Overview

- **Auto-flag on hand-off**: `agterm-handoff.sh` already creates the session (`$SID`) and types the plan prompt into it. One line after session creation calls `agtermctl session flag on --target "$SID"`, best-effort (`|| true` — a flag failure must never abort a hand-off that otherwise succeeded). This makes every `plan`/`review-plan`/`implement-in-session` hand-off show up in agterm's flagged sidebar view without any change to the skills that call this script.
- **`agterm-hooks` plugin**: two independent, tiny bash scripts, each guarded by the same three-part check (`AGTERM_ENABLED=1` AND `AGTERM_SESSION_ID` set AND `agtermctl` on `PATH`) so they're a true no-op outside agterm or if it's an old/broken install:
  - `stop-status.sh` (`Stop` hook): `agtermctl session status completed --sound default --auto-reset --target "$AGTERM_SESSION_ID"`. Fires whenever Claude Code finishes responding, inside *any* agterm session — not planning-hand-off-specific. `--auto-reset` means it behaves as a one-shot "just finished" flash rather than a status you must clear.
  - `notification-status.sh` (`Notification` hook): `agtermctl session status blocked --target "$AGTERM_SESSION_ID"` — no `--sound`, so agterm's own configured "Blocked sound" setting (or silence, if unset) governs it instead of this hook forcing one. Fires on Claude Code's `Notification` event (permission requests and idle-waiting-for-input).
  - Both scripts always `exit 0` and swallow `agtermctl` failures (`|| true`) — a hook that can fail the Stop/Notification event would be far worse than one that silently does nothing.
  - Registered via `hooks/hooks.json` with `"timeout": 5, "async": true` on each — these are fire-and-forget side effects, so Claude Code shouldn't block its own Stop/Notification handling waiting on them.
- This plugin is deliberately separate from `planning`: it applies to any Claude Code session hosted in an agterm pane, regardless of whether it got there via a plan hand-off or was started by hand.

## Technical Details

### File structure

- `plugins/planning/scripts/agterm-handoff.sh` — **modify**: add the flag call.
- `plugins/planning/.claude-plugin/plugin.json` — **modify**: version bump.
- `plugins/agterm-hooks/.claude-plugin/plugin.json` — **create**: new plugin manifest.
- `plugins/agterm-hooks/hooks/hooks.json` — **create**: registers both hooks.
- `plugins/agterm-hooks/hooks/stop-status.sh` — **create**.
- `plugins/agterm-hooks/hooks/notification-status.sh` — **create**.
- `.claude-plugin/marketplace.json` — **modify**: add `agterm-hooks` entry.
- `README.md` — **modify**: new `### agterm-hooks` section; a note on the planning section about auto-flagging.
- `CHANGELOG.md` — **modify**: two new entries.
- `tests/run.sh` — **modify**: assertions for the flag call and both new hook scripts.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Auto-flag the hand-off session

**Files:**
- Modify: `plugins/planning/scripts/agterm-handoff.sh`
- Modify: `tests/run.sh`

- [x] **Add the flag call**, right after the existing `$SID` empty/`null` check (so we never flag a session id that failed to create), before the `session type` calls:

```bash
SID=$(agtermctl session new --cwd "$PROJECT_ROOT" --workspace "$AGTERM_WORKSPACE_ID" --name "$SESSION_NAME" --json | jq -r '.result.id')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
  echo "agterm-handoff: session new failed to return a session id" >&2
  exit 1
fi

# Flag the hand-off so it shows up in agterm's flagged sidebar / flagged
# dashboard alongside any other in-flight implementations. Best-effort: a
# flag failure must not abort a hand-off that otherwise succeeded.
agtermctl session flag on --target "$SID" >/dev/null 2>&1 || true

agtermctl session type "claude 'You have a new implementation plan to execute: $PLAN_FILE
```

  (only the new comment + `agtermctl session flag on` line is inserted; everything else in the file is unchanged)

- [x] **Add a test.** `tests/run.sh` has no existing coverage of `agterm-handoff.sh` (it requires `AGTERM_ENABLED`/`agtermctl`, which the harness doesn't currently fake) — add a new section that fakes `agtermctl` on `PATH` and asserts the script both creates the session and flags it. Append this section right before the closing `echo ""` / `Results:` block at the end of `tests/run.sh`:

```bash
# ---------------------------------------------------------------------------
# planning/agterm-handoff.sh
# ---------------------------------------------------------------------------

HANDOFF_SCRIPT="${REPO_ROOT}/plugins/planning/scripts/agterm-handoff.sh"

echo "planning/agterm-handoff.sh"

FAKE_BIN="$(mktemp -d)"
cat > "${FAKE_BIN}/agtermctl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${AGTERMCTL_LOG}"
if [ "$1" = "session" ] && [ "$2" = "new" ]; then
  echo '{"result":{"id":"fake-session-id"}}'
fi
EOF
chmod +x "${FAKE_BIN}/agtermctl"

TEST_REPO="$(mktemp -d)"
(cd "$TEST_REPO" && git init -q)
PLAN_FILE="${TEST_REPO}/docs/plans/2026-01-01-example.md"
mkdir -p "$(dirname "$PLAN_FILE")"
echo "# Example plan" > "$PLAN_FILE"

LOG="$(mktemp)"
result=$(
  cd "$TEST_REPO" && \
  AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_WORKSPACE_ID="ws-1" \
  PATH="${FAKE_BIN}:${PATH}" bash "$HANDOFF_SCRIPT" "$PLAN_FILE"
)
assert_eq "prints the new session's display name on success" "Implement: example" "$result"
assert_contains "flags the new session" "session flag on --target fake-session-id" "$(cat "$LOG")"
assert_contains "creates the session before flagging" "session new" "$(cat "$LOG")"
rm -f "$LOG"

result=$(AGTERM_ENABLED="" bash "$HANDOFF_SCRIPT" "$PLAN_FILE" 2>&1; echo "exit:$?")
assert_contains "refuses to run when AGTERM_ENABLED is unset" "exit:1" "$result"

rm -rf "$FAKE_BIN" "$TEST_REPO"
```

- [x] **Run the tests to verify they pass**

  Run: `bash tests/run.sh`
  Expected: all `PASS`, `Results: N passed, 0 failed`

### Task 2: `agterm-hooks` plugin scaffolding

**Files:**
- Create: `plugins/agterm-hooks/.claude-plugin/plugin.json`
- Create: `plugins/agterm-hooks/hooks/hooks.json`

- [x] **Write the plugin manifest**

```json
{
  "name": "agterm-hooks",
  "description": "Flags Claude Code's session status in agterm's sidebar (completed/blocked) via Stop and Notification hooks — no-op outside agterm",
  "version": "1.0.0",
  "author": {
    "name": "parmaster"
  },
  "homepage": "https://github.com/parmaster/claude-dlc",
  "repository": "https://github.com/parmaster/claude-dlc",
  "license": "MIT"
}
```

- [x] **Write `hooks.json`**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/stop-status.sh",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/notification-status.sh",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ]
  }
}
```

- [x] **Verify it's valid JSON**

  Run: `jq . plugins/agterm-hooks/.claude-plugin/plugin.json plugins/agterm-hooks/hooks/hooks.json`
  Expected: both files print back pretty-formatted, no error

### Task 3: `stop-status.sh` hook

**Files:**
- Create: `plugins/agterm-hooks/hooks/stop-status.sh`
- Modify: `tests/run.sh`

- [x] **Write the script**

```bash
#!/usr/bin/env bash
# Stop hook: when Claude Code running inside agterm finishes responding,
# flag this session "completed" in agterm's sidebar with a sound. No-op
# outside agterm (AGTERM_ENABLED unset) or when agtermctl isn't on PATH.
# Never fails the hook — always exits 0, so a missing/broken agtermctl can
# never block Claude Code's own Stop handling.
#
# --auto-reset clears the glyph back to idle once the session is next
# visited, so this behaves like a one-shot "just finished" flash rather
# than a status that has to be manually cleared.

if [ "${AGTERM_ENABLED:-}" = "1" ] && [ -n "${AGTERM_SESSION_ID:-}" ] && command -v agtermctl >/dev/null 2>&1; then
  agtermctl session status completed --sound default --auto-reset --target "$AGTERM_SESSION_ID" >/dev/null 2>&1 || true
fi

exit 0
```

- [x] **Make it executable**

  Run: `chmod +x plugins/agterm-hooks/hooks/stop-status.sh`

- [x] **Write tests.** Append to `tests/run.sh`, after the `agterm-handoff.sh` section added in Task 1:

```bash
# ---------------------------------------------------------------------------
# agterm-hooks/stop-status.sh
# ---------------------------------------------------------------------------

STOP_STATUS_SCRIPT="${REPO_ROOT}/plugins/agterm-hooks/hooks/stop-status.sh"

echo "agterm-hooks/stop-status.sh"

FAKE_BIN="$(mktemp -d)"
cat > "${FAKE_BIN}/agtermctl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${AGTERMCTL_LOG}"
EOF
chmod +x "${FAKE_BIN}/agtermctl"

LOG="$(mktemp)"
AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_SESSION_ID="abc-123" \
  PATH="${FAKE_BIN}:${PATH}" bash "$STOP_STATUS_SCRIPT" < /dev/null
assert_eq "flags completed with sound + auto-reset, targeted at the session" \
  "session status completed --sound default --auto-reset --target abc-123" "$(cat "$LOG")"
rm -f "$LOG"

LOG="$(mktemp)"
AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="" AGTERM_SESSION_ID="abc-123" \
  PATH="${FAKE_BIN}:${PATH}" bash "$STOP_STATUS_SCRIPT" < /dev/null
assert_eq "no-op when AGTERM_ENABLED is unset" "" "$(cat "$LOG")"
rm -f "$LOG"

LOG="$(mktemp)"
AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_SESSION_ID="" \
  PATH="${FAKE_BIN}:${PATH}" bash "$STOP_STATUS_SCRIPT" < /dev/null
assert_eq "no-op when AGTERM_SESSION_ID is empty" "" "$(cat "$LOG")"
rm -f "$LOG"

result=$(AGTERM_ENABLED="1" AGTERM_SESSION_ID="abc-123" PATH="/usr/bin:/bin" bash "$STOP_STATUS_SCRIPT" < /dev/null; echo "exit:$?")
assert_contains "exits 0 even when agtermctl isn't on PATH" "exit:0" "$result"

rm -rf "$FAKE_BIN"
```

- [x] **Run the tests to verify they pass**

  Run: `bash tests/run.sh`
  Expected: all `PASS`, `Results: N passed, 0 failed`

### Task 4: `notification-status.sh` hook

**Files:**
- Create: `plugins/agterm-hooks/hooks/notification-status.sh`
- Modify: `tests/run.sh`

- [x] **Write the script**

```bash
#!/usr/bin/env bash
# Notification hook: when Claude Code running inside agterm needs
# permission or has been idle-waiting for input, flag this session
# "blocked" in agterm's sidebar. No-op outside agterm or when agtermctl
# isn't on PATH. Never fails the hook — always exits 0.
#
# No --sound here: agterm plays the user's own configured "Blocked sound"
# (Settings ▸ Appearance ▸ Agent Status) when none is passed explicitly, so
# this defers to whatever they've already set instead of overriding it.

if [ "${AGTERM_ENABLED:-}" = "1" ] && [ -n "${AGTERM_SESSION_ID:-}" ] && command -v agtermctl >/dev/null 2>&1; then
  agtermctl session status blocked --target "$AGTERM_SESSION_ID" >/dev/null 2>&1 || true
fi

exit 0
```

- [x] **Make it executable**

  Run: `chmod +x plugins/agterm-hooks/hooks/notification-status.sh`

- [x] **Write tests.** Append to `tests/run.sh`, after the `stop-status.sh` section added in Task 3:

```bash
# ---------------------------------------------------------------------------
# agterm-hooks/notification-status.sh
# ---------------------------------------------------------------------------

NOTIFICATION_STATUS_SCRIPT="${REPO_ROOT}/plugins/agterm-hooks/hooks/notification-status.sh"

echo "agterm-hooks/notification-status.sh"

FAKE_BIN="$(mktemp -d)"
cat > "${FAKE_BIN}/agtermctl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${AGTERMCTL_LOG}"
EOF
chmod +x "${FAKE_BIN}/agtermctl"

LOG="$(mktemp)"
AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="1" AGTERM_SESSION_ID="abc-123" \
  PATH="${FAKE_BIN}:${PATH}" bash "$NOTIFICATION_STATUS_SCRIPT" < /dev/null
assert_eq "flags blocked, targeted at the session, no forced sound" \
  "session status blocked --target abc-123" "$(cat "$LOG")"
rm -f "$LOG"

LOG="$(mktemp)"
AGTERMCTL_LOG="$LOG" AGTERM_ENABLED="" AGTERM_SESSION_ID="abc-123" \
  PATH="${FAKE_BIN}:${PATH}" bash "$NOTIFICATION_STATUS_SCRIPT" < /dev/null
assert_eq "no-op when AGTERM_ENABLED is unset" "" "$(cat "$LOG")"
rm -f "$LOG"

result=$(AGTERM_ENABLED="1" AGTERM_SESSION_ID="abc-123" PATH="/usr/bin:/bin" bash "$NOTIFICATION_STATUS_SCRIPT" < /dev/null; echo "exit:$?")
assert_contains "exits 0 even when agtermctl isn't on PATH" "exit:0" "$result"

rm -rf "$FAKE_BIN"
```

- [x] **Run the tests to verify they pass**

  Run: `bash tests/run.sh`
  Expected: all `PASS`, `Results: N passed, 0 failed`

### Task 5: Register the plugin in the marketplace catalog

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [x] **Add the `agterm-hooks` entry**, right after the existing `planning` entry:

```json
    {
      "name": "planning",
      "source": "./plugins/planning",
      "description": "Structured implementation plan creation with context gathering, approach exploration, and revdiff review"
    },
    {
      "name": "agterm-hooks",
      "source": "./plugins/agterm-hooks",
      "description": "Flags Claude Code's session status in agterm's sidebar (completed/blocked) via Stop and Notification hooks"
    },
```

- [x] **Verify it's valid JSON**

  Run: `jq . .claude-plugin/marketplace.json`
  Expected: prints back pretty-formatted, no error

### Task 6: Version bumps and CHANGELOG

**Files:**
- Modify: `plugins/planning/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

- [x] **Bump `planning`'s version** in `plugins/planning/.claude-plugin/plugin.json` from `1.11.1` to `1.12.0` (minor: new user-visible capability added to an existing script, not just a fix):

```json
  "version": "1.12.0",
```

- [x] **Add both CHANGELOG entries**, at the very top of `CHANGELOG.md` (newest first), above the existing `## planning v1.11.1 - 2026-08-26` entry:

```markdown
## agterm-hooks v1.0.0 - 2026-08-27

### Features

- New plugin: `Stop` and `Notification` hooks that flag the current agterm session's sidebar status (`completed`/`blocked`, with sound on completion) when Claude Code running inside agterm finishes responding or needs attention. Not planning-specific — applies to any Claude Code session hosted in an agterm pane, not just plan hand-offs. No-op outside agterm.

## planning v1.12.0 - 2026-08-27

### Features

- `agterm-handoff.sh` (shared by `plan`, `review-plan`, `implement-in-session`) now flags the newly created session (`agtermctl session flag on`), so every hand-off shows up in agterm's flagged sidebar view / flagged-dashboard grid instead of having to be found and flagged by hand.
```

### Task 7: README

**Files:**
- Modify: `README.md`

- [x] **Add a new `### agterm-hooks` section**, right after the `### planning` section's closing `---` (i.e. before `### brainstorm`):

```markdown
### agterm-hooks

Flags Claude Code's session status in agterm's sidebar.

```
/plugin install agterm-hooks@parmaster-claude-dlc
```

Applies to any Claude Code session running inside agterm — not tied to `planning`'s hand-off flow. No-op outside agterm (`AGTERM_ENABLED` unset) or when `agtermctl` isn't on `PATH`.

| Hook | Trigger | Effect |
|------|---------|--------|
| `stop-status` | `Stop` — Claude Code finishes responding | Flags the session `completed` in agterm's sidebar, with the system alert sound. `--auto-reset` clears it back to idle once you next look at the session. |
| `notification-status` | `Notification` — Claude Code needs permission or has been idle-waiting for input | Flags the session `blocked` in agterm's sidebar. No sound is forced — agterm plays your own configured "Blocked sound" setting (Settings ▸ Appearance ▸ Agent Status) if you've set one. |

---
```

- [x] **Note the auto-flag behavior in the `planning` section.** In the `### planning` section, right after the Skill table (before the `**\`plan\` — flow**` mermaid block), add:

```markdown
Every agterm hand-off (`plan`, `review-plan`, `implement-in-session`) also flags the new session (`agtermctl session flag on`), so all in-flight implementations show up in agterm's flagged sidebar view / flagged-dashboard grid instead of having to be found and flagged by hand.
```

### Task 8: Verify acceptance criteria

- [x] verify both goals are implemented: hand-off sessions are auto-flagged; `agterm-hooks` sets `completed`/`blocked` sidebar status on `Stop`/`Notification`
- [x] run the full test suite: `bash tests/run.sh` — expect `Results: N passed, 0 failed`
- [x] validate every new/changed JSON file: `jq . plugins/agterm-hooks/.claude-plugin/plugin.json plugins/agterm-hooks/hooks/hooks.json plugins/planning/.claude-plugin/plugin.json .claude-plugin/marketplace.json`
- [x] confirm both new hook scripts are executable: `ls -l plugins/agterm-hooks/hooks/*.sh` shows `x` bits
- [x] grep-verify no leftover references to the old `planning` version number: `grep -rn "1.11.1" plugins/planning CHANGELOG.md README.md` returns nothing
  - ⚠️ this check as written returns one hit: the historical `## planning v1.11.1 - 2026-08-26` heading in `CHANGELOG.md`. That's expected — changelog headings are permanent, newest-first entries (per this repo's own convention), not references that should be scrubbed. `plugins/planning` and `README.md` alone return nothing, which is the actually-meaningful check.

### Task 9: [Final] Wrap up and commit

- [x] re-read `README.md`'s `## Plugins` section top-to-bottom once for consistency (heading levels, `---` separators, install-command formatting) against the new `agterm-hooks` section
- [x] move this plan to `docs/plans/completed/` — `mkdir -p docs/plans/completed && mv docs/plans/2026-08-27-agterm-flow-improvements.md docs/plans/completed/`
- [x] single summary commit: all implementation changes + plan move in one commit
- [x] open draft PR — invoke `planning:pr`

## Post-Completion

*Items requiring manual intervention or external systems*

- Installing/upgrading `agterm-hooks` on a machine (`/plugin install agterm-hooks@parmaster-claude-dlc`, or a `/plugin marketplace update` + reinstall for the `planning` bump) is a manual step per machine — not part of this repo's automated flow.
- The actual sidebar glyph/sound behavior can only be observed live inside agterm (the test harness only verifies the hook scripts call `agtermctl` with the right arguments, since `agtermctl`/agterm itself isn't available in CI). Worth a quick manual smoke test after installing: trigger a `Stop` and a `Notification` event in a real agterm session and watch the sidebar.
