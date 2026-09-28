# agterm overlay plugin

**Goal:** Say "open the latest plan in glow" (or open a markdown/HTML file or a URL) in any repo and have it appear in an agterm overlay over the current session, with no permission prompt or auto-mode block.

**Kind of change:** feature

## Intent

Viewing a plan, an HTML report or a local dev server from inside a Claude session means leaving the terminal or hand-building an `agtermctl session overlay open` call, and that call has several traps: no login-shell PATH, `glow` without `-p` exits at once, relative paths need `--cwd`. On top of that, auto mode blocks `agtermctl` writes as "Remote Shell Writes". A new `agterm` plugin adds an `overlay` skill backed by one script that handles the traps, plus a PreToolUse hook that approves only that script's viewer calls, so it works on any machine without editing settings.

## Decisions

- **New `agterm` plugin, not `planning`.** An overlay viewer is useful beyond plans (HTML reports, dev servers). `planning` already uses agtermctl, but only to spawn sessions.
- **Skill, not command.** It has to trigger from natural language. Typing `/agterm:overlay <thing>` still works.
- **One script, `scripts/overlay.sh <md|html|url> [arg]`, does all the work.** The skill only picks the kind and argument. The script always adds `--target "$AGTERM_SESSION_ID"` and calls nothing but `agtermctl session overlay open|result`, so the scope rules live in code rather than prose.

  | kind | arg | overlay |
  |---|---|---|
  | `md` | file; empty = latest plan | `"zsh -lc 'glow -p <abs>'"` `--cwd <file's dir>` `--size-percent 90` |
  | `html` | file | `--html <abs>` `--cwd <file's dir>` `--navigation` `--size-percent 90` |
  | `url` | `http(s)://` or `file://` URL; optional `--js` | `--url <url>` `--size-percent 90` |

- **No `run` kind.** Running an arbitrary TUI program is arbitrary code execution. Arbitrary programs remain the installed `agterm` skill's job.
- **Permissions via a PreToolUse hook that returns `"allow"`, not skill `allowed-tools`.** Per the Claude Code docs, `allowed-tools` lasts only for the turn that invokes the skill and does not bypass the auto-mode classifier. Allow rules and hook `"allow"` decisions are settled before the classifier runs. The hook (`scripts/approve-overlay.sh`) approves only a single plain call of `overlay.sh` with kind `md|html|url`. For anything else it prints nothing (it never denies), so the normal permission flow applies.
- **Fallback if a hook `"allow"` turns out not to skip the classifier:** a `setup.sh` Setup hook adds a narrow `permissions.allow` rule for the script to `~/.claude/settings.json`, following `global-rules/scripts/setup.sh` (idempotent, never overwrites a value the user set). Only build this if the live check fails.
- **"Latest plan" = newest `*.md` by modification time in `docs/plans/`, falling back to `docs/plans/completed/`,** relative to `$PWD`. Modification time also catches the plan just edited.
- **Catch a flashing glow.** After `md` opens, the script waits about 1s and calls `overlay result`. If the program already exited non-zero, it reports the exit code (127 = not found). If `result` errors because the program is still running, it prints `opened <path>`.

## Constraints / out of scope

- Never target any session except `$AGTERM_SESSION_ID`. Never call any agtermctl subcommand except `session overlay open|result`.
- Outside agterm (`AGTERM_SESSION_ID` unset), or with `agtermctl` missing, exit 1 with a one-line reason. Never guess a target.
- No overlay resize/close/reload, no `run`, no settings edits unless the fallback is needed.

## Traps

- `${CLAUDE_PLUGIN_ROOT}` may reach the Bash tool unexpanded, e.g. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/overlay.sh" md` (see how `planning/skills/spawn-session/SKILL.md` calls its scripts). The hook's metacharacter check must accept `${…}` while still rejecting `$(`. Match on the script's filename, not a full path, because the cache path includes the plugin version.
- `agtermctl session overlay result` errors while the overlay program is still running, and also when no program ever ran. It doesn't print a status in either case, so "error" means "still open" only right after the script's own `open`. The format printed after a program exits isn't documented in `--help`. Check it live (and with `--json`) before parsing it.
- In `md`, the path sits inside `zsh -lc '…'`, so a single quote in the path must be escaped as `'\''`.
- The shared fake `agtermctl` in `tests/run.sh` logs `echo "$@"`. Joining the arguments with spaces loses quoting, so assert on substrings. It also has no branch for `session overlay result`; add a switch (env var) to fake "still running" vs "exited N".
- Existing hooks read the command with `jq -r '.tool_input.command'` and emit decisions via `jq -n` (`global-rules/scripts/block-root-find.sh`). Follow the same shape with `permissionDecision: "allow"`.

## Definition of Done

- [x] `overlay.sh md <file>` / `html <file>` / `url <url>` each call `agtermctl session overlay open` with the table's flags, absolute paths and `--target $AGTERM_SESSION_ID` — proof: `tests/run.sh` cases against the fake agtermctl, run from a subdirectory with relative paths
- [x] `overlay.sh md` with no argument opens the newest plan in `docs/plans/`, else in `docs/plans/completed/`, else fails with "no plans found" — proof: tests for all three situations
- [x] Unset `AGTERM_SESSION_ID`, a missing file, and a URL that isn't `http(s)`/`file` each exit 1 with a one-line message and never call agtermctl — proof: tests assert the exit code, the message, and an empty agtermctl log
- [x] A path containing a single quote reaches glow intact — proof: test, plus a live overlay of `it's a dir/o'k file.md` read back with `overlay text`
- [x] glow exiting non-zero right after opening is reported with its code; "still running" prints `opened <path>` — proof: tests using the fake's result switch
- [x] `approve-overlay.sh` allows plain `bash <…>/overlay.sh md|html|url [arg]` calls (literal `${CLAUDE_PLUGIN_ROOT}` and expanded forms) and prints nothing for: a chained command (`;` `&&` `||` `|`), `$(` / backticks, redirects, a newline, an unknown kind such as `run`, and unrelated commands — proof: tests
- [x] ➕ The hook approves only the script at the plugin's own `$CLAUDE_PLUGIN_ROOT/scripts/overlay.sh` (or the literal `${CLAUDE_PLUGIN_ROOT}` form), not any file named `overlay.sh`, which Claude could write itself — proof: test with `/tmp/evil/scripts/overlay.sh`
- [x] ➕ An overlay already open in the session (agterm errors `overlay already open`; it doesn't replace it) fails with "close it (q or Cmd-W) and try again" and never closes the user's overlay — proof: tests; seen live
- [x] The skill triggers on "open the latest plan in glow" and passes on the script's output — proof: headless `claude -p` in `cards-v2` picked `agterm:overlay` and opened the active plan
- [x] Live, in auto mode, in a different repo, with the plugin loaded: "open the latest plan in glow" opens glow with no prompt and no classifier block — proof: debug log shows `Hook PreToolUse (approve-overlay.sh) returned permissionDecision: allow` and a 10 ms permission decision; the settings fallback isn't needed. URL overlay opened live via the script.
- [x] HTML overlay live check — proof: `overlay.sh html <scratch>/p.html` opened live
- [x] Plugin is wired into the repo: `plugin.json` (`agterm` 1.0.0), `marketplace.json` entry, README section (install, skill, triggers, self-approving hook, why no `run`), `CHANGELOG.md` `## agterm 1.0.0 - <date>` — proof: files present; `/plugin install agterm@parmaster-claude-dlc` after push

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] `shellcheck` passes on the new scripts, if installed (the repo has no linter step) — not installed
- [x] README.md / CLAUDE.md updated if behavior or patterns changed
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [ ] `git fetch && git status`, then rebase if behind
- [ ] single commit: all changes + plan move
