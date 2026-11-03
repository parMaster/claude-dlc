# Sidebar ticket line

**Goal:** a Claude Code hook in the agterm plugin shows the branch's ticket key and commits ahead under the session's sidebar row.

**Kind of change:** feature

## Intent

With several Claude sessions open, the sidebar shows only session names. agterm 0.40.0 added `agtermctl session info`, which draws a second line under a session's row. umputun/agterm's cookbook `claude-git-info` (MIT) fills that line from Claude Code hooks with the full git state. We adapt it to a shorter line: the ticket key from the branch, or a cut branch name, then changed files and commits ahead of and behind the upstream.

```
feat/TASK-123-add-something, clean, 2 ahead  →  **TASK-123** ↑2
fix/TASK-1234-fix-everything, 3 changed      →  **TASK-1234** ● 3
spike-new-sidebar-idea, 1 ahead, 4 behind    →  **spike-new-…** ↑1 ↓4
detached at b64de22                          →  **b64de22**
not a git repo / SessionEnd                  →  (line cleared)

colors: ● N orange, ↑N blue, ↓N purple; each part shows only when N > 0
```

## Decisions

- **Adapt the cookbook script, not write one from scratch** — it already solves the hard parts: the index lock, headless runs, the socket, markdown escaping, expiry. Credit upstream in README the same way as webrev.
- **Ship it in the plugin's `hooks/hooks.json`** — SessionStart, PostToolUse (`Edit|MultiEdit|Write|NotebookEdit|Bash`), Stop, SessionEnd, timeout 5, using `${CLAUDE_PLUGIN_ROOT}`. The cookbook's settings.json setup is dropped: installing the plugin is the setup.
- **Ticket key** — the first match of `[A-Z][A-Z0-9]+-[0-9]+` in the branch name, case-sensitive. A lowercase `task-123` counts as no ticket and falls back to the branch name.
- **Fallback name** — the branch name cut to 10 characters plus `…` when longer. A detached HEAD shows its 7-character commit.
- **Changed, ahead and behind counts** — `^[● N](color: "orange")`, `^[↑N](color: "blue")`, `^[↓N](color: "purple")`, each only when N > 0. The cookbook's `✓ clean`, `local only` and emoji are dropped: a bare name already means clean. Changed counts tracked and untracked files, as in the cookbook. Behind is as of the last fetch.
- **No PR state** — a `gh` call would add a network round trip to every edit. Dropped for now.
- **No opt-out switch** — Settings ▸ Interface ▸ Session info → Off already hides the line.

## Constraints / out of scope

- The existing PreToolUse `approve-overlay.sh` entry stays as is.
- The hook prints nothing and always exits 0. SessionStart stdout becomes model context, and a failing hook must not block Claude.
- No change to webrev, overlay or the spawn/handoff scripts.

## Traps

- `agtermctl` doesn't read `AGTERM_SOCKET`; the hook must pass `--socket` itself (cookbook `git-info.sh`, `info()`).
- A headless `claude -p` inherits `AGTERM_*` and would overwrite its spawner's line. Skip when `CLAUDE_CODE_ENTRYPOINT` isn't `cli` (cookbook `git-info.sh`).
- Plain `git status` can take `index.lock` and make a concurrent `git commit` fail. Keep `--no-optional-locks` (cookbook README, "How it works").
- The update must stay synchronous. A background refresh can land after SessionEnd's clear and bring the line back (cookbook README).
- Cut the name first, then escape it. Escaping first can cut a `\` off its character and break the markup. Branch names may hold `` ` ``, `_`, `]` (cookbook `git-info.sh`, the `sed` escape).
- `--hide-after` maxes out at 86400. Without it, a Claude killed before SessionEnd leaves its line for good.
- Hook scripts run with Claude Code's PATH, which may lack Homebrew; the cookbook prepends `/opt/homebrew/bin:/usr/local/bin`. `AGTERMCTL` overrides the binary, so tests can pass a fake.
- `tests/run.sh` `run_hook` sends only `tool_input.command`; this hook reads `hook_event_name` and `cwd`, so its cases need their own JSON input.

## Definition of Done

- [x] A ticket branch shows the bold key, plus blue `↑N` when ahead — proof: `tests/run.sh` cases on a temp repo with a fake `AGTERMCTL` that records its args, for `feat/TASK-123-…` with 0 and 2 commits ahead.
- [x] Changed files show as orange `● N` and commits behind as purple `↓N`, both absent at 0 — proof: run.sh cases with an edited and an untracked file, and with a branch behind its upstream (a local bare remote).
- [x] A branch without a ticket shows its first 10 characters plus `…`; a short one shows in full — proof: run.sh cases for both.
- [x] A branch name with markdown characters is escaped after the cut — proof: run.sh case with `_` or `` ` `` near the 10th character.
- [x] A detached HEAD shows its short commit — proof: run.sh case.
- [x] Outside git and on SessionEnd, the hook sends `--clear` — proof: run.sh cases.
- [x] No `AGTERM_SESSION_ID`, a non-`cli` `CLAUDE_CODE_ENTRYPOINT`, or a failing `agtermctl` leave nothing printed and exit 0 — proof: run.sh cases asserting empty stdout and status 0.
- [x] Every set passes `--target`, `--socket` and `--hide-after 86400` — proof: run.sh asserts on the recorded args.
- [x] The line shows in agterm for this session — proof: running the hook by hand set `**main** ^[● 9](color: "orange")` on this session, read back with `agtermctl tree --json`. The hook fires by itself after the plugin update.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter passes: `shellcheck plugins/agterm/scripts/*.sh`
- [x] README.md agterm section: what the line shows, the agterm 0.40.0 requirement, the upstream MIT credit
- [x] agterm plugin.json → 2.1.0, CHANGELOG entry
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [x] single commit: all changes + plan move
