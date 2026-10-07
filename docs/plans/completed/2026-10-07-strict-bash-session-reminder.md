# strict-bash: session-start reminder and colorless Bash output

**Goal:** In a strict-bash session Claude neither chains Bash calls nor pipes output through `sed` to strip colors, so neither costs a permission prompt.

**Kind of change:** feature

## Intent

Two kinds of call still prompt on a strict-bash machine:

1. **The first chained call.** `block-chained` only teaches Claude after it denies a call, so the first chained call of every session is wasted. Sometimes it's also preceded by a prompt the user has to approve.
2. **Color stripping.** When test output has ANSI color codes, Claude adds `| sed 's/\x1b\[[0-9;]*m//g'` to nearly every call. `sed` isn't on the allow list, so each of those prompts, chained or not.

A `SessionStart` hook in strict-bash fixes both:

```
SessionStart hook
  ├─ stdout              → "run each command as its own Bash call…"   → Claude's context
  └─ $CLAUDE_ENV_FILE    → export NO_COLOR=1                          → every later Bash command
```

Tested in a real Go repo: `NO_COLOR=1` cleanly removed the color codes from its `go test` output, and Claude there dropped `sed` on its own.

## Decisions

- **One `SessionStart` script does both jobs** — both come from the same hook event, and `CLAUDE_ENV_FILE` is only available to `SessionStart`, `Setup`, `CwdChanged` and `FileChanged` hooks.
- **`NO_COLOR` through `CLAUDE_ENV_FILE`, not the `env` block in settings.json** — per the hooks reference, exports written there apply only to Bash tool commands in that session. The settings `env` block would reach the whole Claude Code process: hooks, MCP servers, maybe its own interface.
- **Not allowing `sed`** — `sed -i` and sed's `w` command write files, so a `Bash(sed:*)` rule is unsafe. An exact-match rule for one strip pattern breaks as soon as Claude varies it.
- **Plugin hook, not prose in `global-rules/CLAUDE.md`** — it loads only on machines that have strict-bash installed.
- **Context as plain stdout** — the reference says plain stdout reaches Claude for `SessionStart`; JSON is only needed alongside fields like `sessionTitle`.
- **No matcher** — fires on `startup`, `resume`, `clear`, `compact` and `fork`. After compact the earlier denial may have been summarized away, so the line has to come back. Exports appended again on resume are harmless.
- **Always on, no permission-mode check** — `SessionStart` input carries no `permission_mode`. In auto or bypass mode the cost is one unneeded line plus colorless Bash output, which is fine.
- **Reminder text matches the deny reason** — one command per Bash call; pipes into head, tail or grep are fine; Read, Grep or Glob for files. One or two sentences.
- **Version 1.1.0** — this is a new component.

## Constraints / out of scope

- `block-chained.sh` and `setup.sh` behavior doesn't change.
- Tools that ignore `NO_COLOR` will still produce color. Their own flags (`--color=never`) are out of scope.

## Traps

- Nothing in this repo uses `SessionStart` or `CLAUDE_ENV_FILE` yet, so there's no local pattern to copy.
- `CLAUDE_ENV_FILE` may be unset, for example in tests. The script must skip the export then, not write to an empty path. It must append (`>>`), never overwrite, because other plugins' hooks write to the same file.
- `tests/run.sh` `run_hook` builds tool input. This hook needs its own small runner with `CLAUDE_ENV_FILE` pointed at a temp file.

## Definition of Done

- [x] The hook prints the reminder, and the text says to run each command as its own Bash call — proof: `tests/run.sh` case.
- [x] With `CLAUDE_ENV_FILE` set, the hook appends `export NO_COLOR=1` and keeps what's already in the file — proof: `tests/run.sh` case with a file that already has a line.
- [x] With `CLAUDE_ENV_FILE` unset, the hook still prints the reminder and exits 0 without writing anywhere — proof: `tests/run.sh` case.
- [x] `hooks/hooks.json` registers the script under `SessionStart` with no matcher, via `${CLAUDE_PLUGIN_ROOT}` — proof: read the file; `claude --plugin-dir plugins/strict-bash` loads without hook errors.
- [x] `plugin.json` is at `1.1.0` and CHANGELOG has `## strict-bash 1.1.0 - 2026-10-07` — proof: read them.
- [x] The README strict-bash table has a row for the new hook covering both jobs and why `sed` isn't allowed — proof: read the section.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter passes: `shellcheck plugins/strict-bash/scripts/*.sh`
- [x] README.md updated
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-10-07-strict-bash-session-reminder.md docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then on the strict-bash machine run `/plugin marketplace update` and restart.
- Live check in a fresh session: `echo $NO_COLOR` prints `1`, and the first Bash calls arrive unchained.
