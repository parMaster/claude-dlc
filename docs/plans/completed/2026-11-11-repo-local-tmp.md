# Repo-local tmp/ instead of the scratchpad

**Goal:** Claude writes temp files to `./tmp/<name>` in the repo, so Bash commands show short paths instead of the long scratchpad path.

**Kind of change:** feature

## Intent

Claude Code's system prompt gives each session a scratchpad, such as
`/private/tmp/claude-501/-Users-...-repo/<session-id>/scratchpad/`. It tells
Claude to keep all temp files there and to write the full path every time.
So a call like `make test > <scratchpad>/e2e.out 2>&1` is wider than the
screen, and the user has to read hundreds of them a day.

The user always works inside a git repo, and writes there are allowed. A
`./tmp/e2e.out` path is just as safe once `tmp/` is ignored by git.

The fix has to steer Claude before its first Bash call. A deny-only hook would
produce a run of "Denied" messages at the start of every fresh session, and
that run is the pain this plan removes.

```
before:  system prompt ──> Claude writes to scratchpad ──> long paths
after:   system prompt
         SessionStart: "use ./tmp/<name>" ──> Claude writes to ./tmp/
         PreToolUse deny (backstop)  ──> catches a drift back, once
```

## Decisions

- **SessionStart guidance is the main fix.** strict-bash's `session-start.sh`
  already injects Bash rules before the first call. It gains one rule: temp
  files go in `./tmp/<name>`, never the scratchpad. The text must say it
  replaces the system prompt's scratchpad instruction. Otherwise Claude sees
  two conflicting rules and may keep the system prompt's one.
- **SessionStart also creates `tmp/`** in the project root when that root is
  a git work tree. Then `cmd > tmp/x.out` works on the first call. It needs no
  `mkdir` call, and block-chained can't deny a `mkdir -p tmp && ...` chain.
  Outside a git repo it creates nothing, so it never drops a `tmp/` into `$HOME`.
- **A deny hook is the backstop, Bash only.** A new `block-scratchpad.sh`
  denies a Bash command whose text contains the scratchpad path. The reason
  points at `./tmp/<name>`. Read and Write calls are left alone: the user
  didn't ask for them, and their paths aren't the screen-wide Bash lines.
- **The deny runs in every mode**, auto and bypassPermissions too, like
  block-inline-edit. The problem is readability, not permission prompts.
- **Global gitignore through setup.sh.** strict-bash's `setup.sh` appends
  `tmp/` to the global excludes file, once. It uses `core.excludesFile` when
  that is set, else git's default `${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore`.
  It never rewrites existing lines. A per-repo `.gitignore` edit was dropped:
  it would touch every repo and show up in diffs.
- **Minor bump:** strict-bash 1.3.1 → 1.4.0 (new hook).

## Constraints / out of scope

- Existing strict-bash hooks and their tests stay as they are.
- No cleanup of old `tmp/` files. The user deletes them when they like.
- No change to Read/Write tool paths or to Claude's own tool-result files
  under `~/.claude/projects/`.

## Traps

- The scratchpad path has several spellings. On macOS `/tmp` links to
  `/private/tmp`, so both `/private/tmp/claude-501/...` and
  `/tmp/claude-501/...` show up. On Linux it's `/tmp/claude-<uid>/...`. Match
  `/tmp/claude-<digits>/`, not a single literal prefix.
- `run_setup` in `tests/run.sh` only swaps `HOME`. Git also reads
  `XDG_CONFIG_HOME` and `GIT_CONFIG_GLOBAL`. The setup tests must point those
  at the test dir too, or a test run writes to the real global ignore file.
- `core.excludesFile` may start with `~`. Git expands it, but bash's `[ -f ]`
  doesn't. Expand it before reading or appending.
- The global ignore file may not end with a newline. Appending `tmp/` blindly
  then glues it onto the last pattern.
- `setup.sh` only runs on plugin install/update via `claude --init-only`
  (the `Setup` hook with matcher `init` in `plugins/strict-bash/hooks/hooks.json`).
  The user has to run it once after updating.
- The SessionStart hook runs with the project dir as cwd, but
  `CLAUDE_PROJECT_DIR` is the reliable name for it. Claude may later `cd`
  into a subdir, so the guidance names `tmp/` at the repo root.

## Definition of Done

- [x] SessionStart output tells Claude to write temp files to `./tmp/<name>` at the repo root, and says this replaces the scratchpad rule — proof: session-start test asserts the text
- [x] SessionStart creates `tmp/` in a git project dir and nothing outside one — proof: two tests, one in a `git init` temp dir and one in a plain temp dir
- [x] Bash commands containing `/private/tmp/claude-501/...` or `/tmp/claude-501/...` are denied with a reason naming `./tmp/` — proof: block-scratchpad tests for both spellings, in default and auto mode
- [x] Commands that only mention `/tmp/x` or `tmp/e2e.out` pass — proof: block-scratchpad tests expect no output
- [x] `setup.sh` adds `tmp/` to the global ignore file once, keeps existing lines, handles a missing trailing newline, and honors `core.excludesFile` with `~` — proof: setup tests run twice and compare file contents
- [x] `git check-ignore tmp/x` succeeds in a fresh repo after setup — proof: setup test with isolated `HOME`/`XDG_CONFIG_HOME`
- [x] README strict-bash section lists the new hook and the gitignore step; CHANGELOG has `strict-bash 1.4.0`; plugin.json says 1.4.0 — proof: diff review

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] no linter in this repo (CI runs only `tests/run.sh`)
- [x] README.md updated
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-11-11-repo-local-tmp.md docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update` and run `claude --init-only` once.
- Live check: start a fresh session that implements a plan. Its temp output
  should go to `./tmp/` with no "Denied" run at the start.
