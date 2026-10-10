# no-worktrees plugin

**Goal:** A new plugin that stops Claude Code from creating git worktrees, so all work stays in the checkout the user has open.

**Kind of change:** feature

## Intent

Claude sometimes moves work into a git worktree without being asked. For this user that has only costs:

- They never run two writing sessions in one repo, so the one benefit of a worktree (isolation between writers) does not apply.
- The worktree is a different folder, so the edits do not show in the open VS Code window.
- On a machine where auto mode is off, the repo's allow rules do not match the new folder, so every command prompts.

Today the only defence is to notice and say "no worktrees". The plugin replaces that with a block the harness enforces. It has no off switch other than disabling the plugin in `/plugin`.

## Decisions

- **Its own plugin, `no-worktrees`, version 1.0.0** — not part of `global-rules`. Claude Code toggles hooks per plugin, so a separate plugin is the only way to turn this block on or off alone, and to install it on one machine only.
- **Hard block, no env var switch and no relocation** — an `ALLOW_WORKTREES` variable and a "create the worktree in a visible sibling folder" mode were both considered. Dropped: the user has no case where a worktree helps, so a switch is unused surface.
- **Everything is a hook; no `setup.sh`, no `permissions.deny` edits** — deny rules in `~/.claude/settings.json` would do part of the job, but they need `claude --init-only` after install and they stay behind when the plugin is disabled. That breaks the toggle. Hooks load with the plugin and leave with it.
- **Three paths are blocked:**

  ```
  path                                        blocked by
  ------------------------------------------  ---------------------------------
  claude --worktree                           not blocked in testing (see DoD)
  subagent with isolation: "worktree"         WorktreeCreate hook, non-zero exit
  background session                          WorktreeCreate hook, non-zero exit
  EnterWorktree tool                          PreToolUse deny (matcher EnterWorktree)
  Bash: git worktree add                      PreToolUse deny (matcher Bash)
  ```

- **The denial text says what to do, not how to undo the block** — it tells Claude that worktrees are off on this machine and to work in the current checkout. It does not name the plugin or how to disable it.
- **Only `git worktree add` is blocked in Bash** — `git worktree list`, `remove` and `prune` stay allowed so an existing worktree can still be inspected and cleaned up.
- **The Bash block runs in every permission mode** — unlike `strict-bash`, which goes silent in auto and bypass modes. The reason for this block (hidden work) holds in every mode.

## Constraints / out of scope

- The user's own `claude --worktree` was expected to fail too. It does not (see the ⚠️ item in the DoD). Accepted: that flag is the user's own request, not Claude drifting.
- Commands the user types in their own shell are not touched.
- The Bash block is a guard against Claude drifting into a worktree, not a sandbox. Forms such as an alias or a script that calls git are out of scope.
- No change to any other plugin. `global-rules/CLAUDE.md` gets no prose rule about worktrees.
- No personal paths or machine-specific values in the plugin.

## Traps

- `WorktreeCreate` is not a normal decision hook. Per the hooks docs, a command hook must print the worktree path on stdout to succeed, any non-zero exit fails creation, and JSON output is not read on failure. So the block is the exit code plus a message on stderr, not a `permissionDecision` JSON. The event takes no matcher.
- The hooks docs say the hook's stderr is shown to the user. Whether Claude also sees it when an `Agent` call with `isolation: "worktree"` fails is not confirmed. The DoD has a live check for it.
- Two readings of the hooks docs disagreed on whether `WorktreeCreate` fires for the `EnterWorktree` tool. Do not rely on it: the `PreToolUse` deny for `EnterWorktree` is required either way. The tools reference confirms that `EnterWorktree` is a valid name for hook matchers.
- A naive match on the text `git worktree add` gives false denials: `grep -rn "git worktree add" .`, or `git commit -m "doc: git worktree add"`. It also misses `git -C <dir> worktree add`. The existing Bash hooks in `plugins/global-rules/scripts/` (`block-root-find.sh`, `block-coauthor.sh`) solve the same "command word, not a mention" problem and have tests for it in `tests/run.sh`.
- `PreToolUse` deny output must match the JSON shape the other hooks emit (`deny()` in `plugins/strict-bash/scripts/block-chained.sh`); `tests/run.sh` asserts on the literal `"permissionDecision": "deny"` with the space that `jq` prints.
- Hook commands must use `${CLAUDE_PLUGIN_ROOT}`; the plugin is copied to a cache on install.
- `CHANGELOG.md` already tells the reader to run `git worktree add` by hand for the old `planning` version. That is a command for the user's shell and stays valid; do not edit it.

## Definition of Done

- [x] The `WorktreeCreate` script fails creation — proof: a `tests/run.sh` case feeds it a `WorktreeCreate` JSON input and asserts a non-zero exit, empty stdout, and a stderr message that says worktrees are off.
- [x] The denial text never reveals an off switch — proof: test asserts that the stderr and the deny reasons contain no mention of the plugin name, `/plugin`, `disable` or an env var.
- [x] `EnterWorktree` is denied — proof: test feeds a `PreToolUse` input with `tool_name: "EnterWorktree"` and asserts `"permissionDecision": "deny"`.
- [x] Bash `git worktree add` is denied in its common forms — proof: tests for `git worktree add ../x`, `git worktree add -b feat ../x main`, `git -C /some/repo worktree add ../x`, and the command chained after `&&`.
- [x] Other worktree subcommands and mere mentions pass — proof: tests assert no output for `git worktree list`, `git worktree remove ../x`, `git worktree prune`, `grep -rn "git worktree add" .`, `git commit -m "doc: git worktree add"`, and `git status`.
- [x] The Bash block ignores the permission mode — proof: test with `permission_mode: "auto"` in the input still gets a deny.
- [x] ⚠️ The block works in a real session, except for the startup flag. Result: a subagent with worktree isolation and the `EnterWorktree` tool were both refused in `claude --plugin-dir` sessions, no worktree appeared, and Claude saw the hook's message verbatim. `claude --plugin-dir plugins/no-worktrees --worktree probe` was NOT blocked: the worktree was created. The same script blocked it when given through `--settings`, so the script is right and the plugin hook did not fire at startup. Not tested with an installed plugin. Original proof: start Claude with `claude --plugin-dir plugins/no-worktrees --worktree probe` and see it refuse with the message; then, in a normal session with the plugin loaded, ask for a subagent with worktree isolation and confirm that no worktree appears (`git worktree list` shows only the main checkout) and that Claude carries on in the checkout. Note in this plan whether Claude saw the hook's message.
- [x] The plugin is installable from the marketplace — proof: `.claude-plugin/marketplace.json` has a `no-worktrees` entry, and `plugins/no-worktrees/.claude-plugin/plugin.json` has the same fields as the `strict-bash` one, with version `1.0.0`.
- [x] The docs describe it — proof: `README.md` has a `no-worktrees` section (what it blocks, the three reasons, that `claude --worktree` is not blocked, how to turn it off by disabling the plugin); `CHANGELOG.md` has `## no-worktrees 1.0.0 - <date>`.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter: the project has none in CI; run `bash -n` on each new script
- [x] README.md updated (covered by the DoD); CLAUDE.md needs no change
- [x] branch is not behind `origin/main` (`git fetch`, `git status`)
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push before installing: installed plugins come from GitHub, not from this checkout.
- On each machine: `/plugin marketplace update`, `/plugin install no-worktrees@parmaster-claude-dlc`, `/reload-plugins`.
