---
name: handoff
description: Hand off an implementation plan directly to a fresh agterm session running Claude or Codex. Explicit invocation only.
argument-hint: "[plan-file]"
disable-model-invocation: true
user-invocable: true
allowed-tools: Bash, AskUserQuestion
---

# Handoff to a Separate Session

Hand a plan straight to a fresh agterm session. `plan` and `review-plan` no
longer offer implementation hand-off inline — this is the direct route from
a finished plan to a running implementation.

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

## Step 2: Choose a runtime

Ask with `AskUserQuestion` — question "Which CLI should the new session run?",
header "Runtime", single-select, options:

- **Claude** (Recommended) — a `claude` process, matching this session
- **Codex** — a `codex` process (Codex CLI)

## Step 3: Choose a model

Check the Step 2 answer before asking — do not default to the Claude tier
list out of habit just because it's the familiar one from other planning
skills. Codex gets its own, different question.

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

## Step 5: Report the outcome

On success, the script's last stdout line is the new session's display name
(e.g. `Implement: foo`) — tell the user: implementation has been handed off
to a new agterm session with that name, running the chosen runtime (Claude or
Codex), in this same workspace (noting the chosen model, unless Inherit), and
they can switch to it to watch or drive it directly. Stop completely.
