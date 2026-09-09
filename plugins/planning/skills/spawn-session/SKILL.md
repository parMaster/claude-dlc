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
- If the request explicitly wants the result back here (e.g. "make it
  return the result", "report back", "let me know what it finds"), say so
  unconditionally in the task prompt itself: state plainly that calling
  `SendMessage` with the answer/result is the last step of the task, once
  done. Don't rely on the callback note in Step 5 alone for this — it's
  worded as conditional ("if asked at any point") precisely because most
  spawned tasks don't need to report back, so on its own it won't make an
  otherwise-silent session call back.

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

## Step 3: Choose a model

Ask which model the new session should run on, using AskUserQuestion:

```json
{
  "questions": [{
    "question": "Which model should the new session use?",
    "header": "Model",
    "options": [
      {"label": "Inherit", "description": "Use whatever `claude` launches with by default"},
      {"label": "Opus", "description": "Most capable — best for complex or subtle work"},
      {"label": "Sonnet", "description": "Faster and cheaper — good for straightforward tasks"},
      {"label": "Haiku", "description": "Fastest and cheapest — for simple mechanical changes"}
    ],
    "multiSelect": false
  }]
}
```

Lower-case the chosen label (`opus`, `sonnet`, `haiku`) for `MODEL_FLAGS` below
(`--model opus`, etc.); for **Inherit**, leave `MODEL_FLAGS` empty.

## Step 4: Learn this session's own name

Call `ListAgents`. Its result opens with a self-identifying line, e.g.
"This session is `claude-dlc-3f` [8e434c] — the name other sessions use to
message it." Take the bare name before the ` [` — that's `CALLER_NAME`
below. If the output doesn't contain a line in that shape, skip the
callback paragraph in Step 5 entirely rather than blocking the spawn.

## Step 5: Check availability, write the prompt, and spawn — in one command

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
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-spawn.sh" "$PWD" "SESSION_NAME" "$PROMPT_FILE" [WORKSPACE_NAME] [MODEL_FLAGS]
else
  echo "spawn-session: not available — AGTERM_ENABLED is unset or agtermctl wasn't found on PATH" >&2
  exit 1
fi
```

substituting `SESSION_NAME` from Step 2, `CALLER_NAME` from Step 4 (both
occurrences — omit the whole callback paragraph, including its leading
blank line, if Step 4 found no name), appending `WORKSPACE_NAME` only when
grouping (empty string `""` if `MODEL_FLAGS` is also being passed but no
grouping applies), and appending `MODEL_FLAGS` from Step 3 only when it's
non-empty.

## Step 6: Confirm

On success (exit 0), the last stdout line is the new session's display
name — tell the user the task has been handed off to a new agterm session
with that name (and which workspace, if grouped, and which model, unless
Inherit), and they can switch to it to watch or drive it directly. On
failure (non-zero exit), tell the
user the hand-off failed, quoting the stderr output — if it's the
"not available" message, ask whether they want a background subagent
instead rather than falling back to one silently. Stop either way — do
not implement the task yourself in this session.
