# strict-bash plugin: one command per Bash call

**Goal:** On a machine where auto mode is off, Claude's Bash calls stay small enough for allow rules to match, so routine commands stop prompting.

**Kind of change:** feature

## Intent

When auto mode is off, every Bash call that isn't on the allowlist asks for permission. Claude often glues 5–8 commands into one call with `&&`, `;`, `$(…)` or loops, so no allow rule can match and every call prompts. A new, opt-in plugin `strict-bash` fixes both sides of this. A hook denies chained commands and tells Claude to split them. A setup script adds an allowlist for the read-only filters that usually follow a pipe. The plugin is installed only on the machine that needs it. Other machines, where auto mode is on, never load it.

```
before:  git fetch -q && git status -sb | head -1; make swagger 2>&1 | tail -5   → 1 prompt, never matchable
after:   git fetch -q                     → matches Bash(git fetch:*)
         git status -sb | head -1         → each pipe side matches
         make swagger 2>&1 | tail -5      → each pipe side matches
```

## Decisions

- **Separate plugin, not part of global-rules** — installs are per machine, so nothing has to detect the account. An env-var switch inside global-rules was dropped because it loads the hook everywhere and adds one more setting to remember.
- **Pipes stay allowed** — Claude Code already checks each side of `|` against allow rules, and filtering output is usually needed. The hook blocks only operators that sequence separate commands.

  | Construct | Hook |
  |---|---|
  | `\|`, `2>&1`, `>&2`, `< file` | allow |
  | `&&`, `\|\|`, `;`, a lone `&` (background), a newline between commands | deny |
  | `$(…)`, backticks | deny |
  | `for` / `while` / `until` / `if` as a command | deny |
  | any of the above inside single/double quotes or a heredoc body | allow (it's data) |

- **Exception for `$(cat <<'EOF' … EOF)`** — this is Claude's default way to pass a multi-line commit or PR message. Blocking it would make every commit fail once first. Allow exactly this form: one `cat` reading a quoted heredoc and nothing else inside the `$(…)`.
- **Deny message says what to do** — "Run each command as its own Bash call; use Read/Grep/Glob for file reads and searches." It also names the operator it found, so the retry fixes the right thing.
- **No-op when no prompts would happen anyway** — if `permission_mode` in the hook input is `bypassPermissions` or `auto`, the hook exits without output. `acceptEdits`/`default`/`plan` still prompt for Bash, so the hook stays active there.
- **Allowlist added by setup.sh**: `Bash(head:*)`, `Bash(tail:*)`, `Bash(grep:*)`, `Bash(wc:*)`, `Bash(sort:*)`, `Bash(uniq:*)`, `Bash(jq:*)`. It never adds `xargs`, `sh`, `bash`, `env` or anything else that runs its arguments as a command. Entries are appended only when missing; existing `permissions.allow` order and content stay untouched.
- **The hook never returns `allow`** — it only denies or stays silent. Approval stays with the user's rules.

## Constraints / out of scope

- global-rules and other plugins don't change.
- No per-project allowlist for things like `git status` or `make test`. The user adds those with `/fewer-permission-prompts` or by hand.
- Sandbox settings aren't touched.

## Traps

- Quoted text holds operators all the time: `git commit -m "fix; also x"`, `grep -E 'a|b&&c'`, `jq '.a | .b'`. A plain regex over the raw string, like `block-root-find.sh` uses, would deny these. The check has to skip single-quoted, double-quoted and heredoc content. Inside double quotes `$(…)` still runs, so it still counts there.
- `2>&1` and `>&2` contain `&`. Only `&&` and a lone `&` (background) are sequencing.
- `approve-overlay.sh` in the agterm plugin returns `allow` for its own overlay calls. Those calls never contain operators, so the two hooks don't conflict. If both ever ran on the same call, deny would win.
- The Setup hook only fires with matcher `init`, so the user has to run `claude --init-only` once after install. README documents this for the other plugins (`plugins/global-rules/hooks/hooks.json`, README "Run `claude --init-only`").
- `tests/run.sh` drives hooks through `run_hook`, which sends only `tool_input.command`. The `permission_mode` cases need input built with `jq -n` instead, the way `run_edit` does.
- The exact `permission_mode` values (`auto` especially) aren't documented in this repo. `agterm-handoff.sh` launches with `--permission-mode auto`, so that name exists as a CLI mode. Whether the hook input reports it the same way needs checking in a live session.

## Definition of Done

- [x] Each blocked construct in the table is denied, and the reason names the operator — proof: `tests/run.sh` cases, one per row.
- [x] Pipes, `2>&1`, operators inside quotes or heredoc bodies, and the `$(cat <<'EOF' … EOF)` commit form are not denied — proof: `tests/run.sh` cases, each asserting empty output.
- [x] Hook is silent when `permission_mode` is `bypassPermissions` or `auto`, and active for `default` — proof: `tests/run.sh` cases with `jq -n`-built input.
- [x] setup.sh adds the seven filter rules to `permissions.allow`, keeps existing entries and order, doesn't duplicate on a second run, creates settings.json if missing, and never adds `xargs`/`sh`/`bash` — proof: `tests/run.sh` cases in the style of the global-rules setup tests.
- [x] Plugin is installable — proof: `strict-bash` entry in `.claude-plugin/marketplace.json`, `plugins/strict-bash/.claude-plugin/plugin.json` at `1.0.0`, `claude --plugin-dir plugins/strict-bash` loads it without errors.
- [x] README has a strict-bash section: what it blocks, why pipes are allowed, install only on machines with auto mode off, run `claude --init-only` once — proof: read the section.
- [x] CHANGELOG has `## strict-bash 1.0.0 - <date>` — proof: read it.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter passes: `shellcheck plugins/strict-bash/scripts/*.sh` (CI has no linter step; run it locally if installed)
- [x] README.md updated
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-10-06-strict-bash-plugin.md docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then on the Team-account machine: `/plugin marketplace update`, `/plugin install strict-bash@parmaster-claude-dlc`, `claude --init-only`.
- Live check in a real session: log one hook input to confirm the `permission_mode` values, then have Claude run a chained command and confirm it gets denied and retries as separate calls.
