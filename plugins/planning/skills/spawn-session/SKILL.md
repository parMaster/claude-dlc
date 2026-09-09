---
name: spawn-session
description: Hand off an arbitrary task to a freshly spawned, independent agterm session running its own `claude` process — not a background subagent. Activates on "spawn a new session for this", "hand this off to a new session", "start a separate session for this job", "delegate this to a new terminal session", "run this in a separate/parallel session", "spin up a session for this slice", or when the user is slicing a larger job into pieces to hand off one at a time.
argument-hint: "[task description]"
allowed-tools: Bash, ListAgents, AskUserQuestion
---

# Spawn a Task in a Separate Session

Hand a task prompt to a new agterm session running its own `claude` process —
a visible terminal session the user can switch to and drive, which keeps
running after this conversation ends. Not an `Agent` subagent: those are
in-process, hidden, and die with this conversation.

## Step 1: Resolve the task prompt

- Use `$0` if given.
- Otherwise write a self-contained prompt: what to do, which files/areas are
  involved, how to verify it's done. The new session cannot see this
  conversation.
- If the user wants the result back here ("report back", "let me know what it
  finds"), state in the task prompt itself that `SendMessage` to the caller is
  the task's last step. Step 5's callback note is conditional and won't make an
  otherwise-silent session call back.

## Step 2: Name and workspace

- Session name: short sidebar label, e.g. `Spawn: <slug>`.
- One of several slices of a larger job: pick one short workspace name and
  reuse it verbatim for every slice, which groups them in the sidebar.
  Otherwise omit it — the session opens in the current workspace.
- Slices sharing a stateful resource (database, lock, port): spawn one at a
  time, not back to back.

## Step 3: Choose a model

Ask with `AskUserQuestion` — question "Which model should the new session
use?", header "Model", single-select, options:

- **Inherit** — whatever `claude` launches with by default
- **Opus** — most capable; complex or subtle work
- **Sonnet** — faster and cheaper; straightforward tasks
- **Haiku** — fastest and cheapest; simple mechanical changes

`MODEL_FLAGS` is `--model <lower-cased label>`, or empty for **Inherit**.

## Step 4: Learn this session's own name

Call `ListAgents`. Its result opens with a self-identifying line:

```
This session is claude-dlc-c7 [39feef] — the name other sessions use to message it
```

`CALLER_NAME` is the bare name before the ` [` — no brackets, no backticks
(`claude-dlc-c7` above). If no line matches that shape, drop the callback
paragraph below rather than blocking the spawn.

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

This task was spawned from session `CALLER_NAME`. If asked at any point to
return a result there, use the SendMessage tool addressed to `CALLER_NAME`.
PROMPT_EOF
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agterm-spawn.sh" "$PWD" "SESSION_NAME" "$PROMPT_FILE" [WORKSPACE_NAME] [MODEL_FLAGS]
```

Arguments are positional, so a skipped workspace still needs its slot:

```bash
# grouped, model chosen
... "$PWD" "Spawn: parser" "$PROMPT_FILE" "Refactor" "--model opus"
# ungrouped, model chosen
... "$PWD" "Spawn: parser" "$PROMPT_FILE" "" "--model opus"
# ungrouped, Inherit
... "$PWD" "Spawn: parser" "$PROMPT_FILE"
```

## Step 6: Report the outcome

Exit 0: the last stdout line is the new session's display name. Report the
hand-off with that name, the workspace if grouped, the model unless Inherit,
and that the user can switch to it. Non-zero: report the failure, quoting
stderr; if it's the "not available" message, ask whether they want a
background subagent instead of silently falling back to one.

Either way, stop — do not implement the task in this session.
