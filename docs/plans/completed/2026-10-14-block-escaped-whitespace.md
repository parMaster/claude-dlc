# Deny backslash-escaped whitespace in Bash calls

**Goal:** Claude quotes paths with spaces, so Claude Code's escaped-whitespace prompt never fires.

**Kind of change:** feature

## Intent

Claude Code asks for permission on any Bash command with "Contains backslash-escaped whitespace", even when an allow rule would match the command. Claude writes `Application\ Support` when it spells out a path by hand. One trigger: the agterm skill says to pass `--socket "$AGTERM_SOCKET"`, and the strict-bash session-start message says a `$VAR` always prompts. So Claude expands the variable itself and escapes the space.

A PreToolUse hook denies the call before the permission check. The denial tells Claude to double-quote the path. Claude retries, the quoted call matches an allow rule, and the user sees no prompt.

```
before:  Claude → Bash("…Application\ Support…") → built-in check → prompt
after:   Claude → Bash("…Application\ Support…") → hook denies "quote it"
         Claude → Bash("…\"Application Support\"…") → allow rule → runs
```

## Decisions

- **Lives in strict-bash, not global-rules** — strict-bash exists to make Bash calls match allow rules. That is this hook's job too. global-rules was dropped because the hook only pays off where allow rules are in play.
- **New script, not a branch inside `block-chained.sh`** — one denial reason per script, like the other hooks. `block-chained` is a character scanner for operators; mixing a second rule into it makes both harder to read.
- **Skip `bypassPermissions` and `auto` modes** — same reason as `block-chained`: those modes don't prompt, so a denial costs a retry for nothing.
- **Match only what Claude Code flags** — a backslash followed by a space or a tab. A wider match denies commands that would have run without a prompt. Backslash-newline (a line continuation) is out unless Claude Code also flags it.
- **Add one clause to `session-start.sh`** — "quote paths with spaces, don't backslash-escape them", next to the `$VAR` advice. The message runs once per session, and the README says it exists so Claude doesn't learn the rules from a denial.

## Constraints / out of scope

- Don't touch the agterm skill; it ships inside the agterm app.
- `block-chained` and `block-inline-edit` behavior stays as is.
- The hook only denies or stays silent. It never approves.

## Traps

- `block-chained.sh` reads stdin once into `INPUT` and pulls both `permission_mode` and `tool_input.command` from it. A script that calls `jq` twice on stdin, like `block-root-find.sh`, gets nothing the second time. (`plugins/strict-bash/scripts/block-chained.sh`)
- The exact set of characters Claude Code flags isn't documented here. Check it in a live session before fixing the pattern: `\ `, `\<tab>`, and `\` inside double quotes (`"a\ b"`).
- The `tests/run.sh` helper `run_hook` builds input with only `tool_input.command`, so a mode test needs its own input with `permission_mode`. See how the block-chained section does it.
- `docs/backlog/inline-edit-misses-quoted-sed.md` covers `block-inline-edit`, not this hook; leave it alone.

## Definition of Done

- [x] A Bash call with `\ ` outside quotes is denied, and the reason tells Claude to double-quote the path — proof: `tests/run.sh` case on the agtermctl command from this session
- [x] A quoted path with spaces passes — proof: `tests/run.sh` case
- [x] Backslashes not followed by whitespace pass (`grep "a\|b"`, `\n` in printf) — proof: `tests/run.sh` cases
- [x] The hook stays silent in `bypassPermissions` and `auto` modes — proof: `tests/run.sh` cases
- [x] The hook is registered under the strict-bash Bash PreToolUse matcher — proof: `plugins/strict-bash/hooks/hooks.json`
- [x] The session-start message mentions quoting paths with spaces — proof: the existing session-start test asserts the new clause
- [ ] ⚠️ In a live session, Claude retries a denied command with quotes and runs it without a prompt — proof: run the agtermctl command with `\ ` once after `/reload-plugins`

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] `shellcheck` is clean on the new script, if installed
- [x] README.md strict-bash section: new table row, and the session-start row mentions quoting
- [x] strict-bash version bumped to 1.3.0, `CHANGELOG.md` entry `## strict-bash 1.3.0 - <date>`
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update` and `/reload-plugins` on each machine.
