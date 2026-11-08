# agterm mailbox chat with Codex

**Goal:** From Claude in agterm, say "ask codex …" or "discuss this with codex" and get a live back-and-forth with a Codex running in the other pane of the split.

**Kind of change:** feature

## Intent

Today Claude can hand a task to a separate Codex session (`spawn-session`), but the two agents can't talk. The upstream agterm cookbook `two-agent-mailbox-chat` (umputun/agterm, `cookbook/two-agent-mailbox-chat/`) solves this with agterm's per-pane mailboxes: each agent sends with `mailbox-chat.py say`, and a hook on the other side turns the mail into a new turn. Nothing is typed into a composer.

This plan adopts that recipe into the `agterm` plugin. It wires it up with as little hand setup as possible. It also lets one phrase open the split and start Codex when none is there. Using it for Codex plan reviews is a later plan; this one only builds the channel.

```
Claude pane                         agterm                         Codex pane
"ask codex X"
  skill → say --stdin ──► msg send ─► mailbox(codex pane)
                                        └► on message hook ──► agterm-hook ─► codex queue ─► Codex turn
                                                                                     │
Claude turn ◄─ exit 2 ◄─ claude-hook waiter ◄─ mailbox(claude pane) ◄─ msg send ◄─ say --file
              (asyncRewake)
```

## Decisions

- **Ship in the `agterm` plugin, minor bump.** It is agterm-only and sits next to the Codex launch scripts. A new plugin would duplicate the setup and hook plumbing.
- **Take `mailbox-chat.py` and its tests almost verbatim.** It already handles locking, busy marks, nested `codex exec`, and acking only after delivery. Keep the upstream author and MIT notice in the file header. Local edits stay small and are listed in the CHANGELOG entry.
- **Codex already loads this marketplace's plugins.** `~/.codex/config.toml` lists `[plugins."agterm@parmaster-claude-dlc"]`, and Codex runs the plugin's `hooks/hooks.json` and skills. So:
  - **One `mailbox-chat` skill serves both agents.** Shared rules (receiving, never wait, who edits, no approval by proxy, manners) appear once. The "Sending" section has a Claude part (heredoc on stdin) and a Codex part (`apply_patch` to a file, then `say --file`). No copy into `~/.codex/skills`.
  - **Both agent hooks ship in the plugin's `hooks.json`.** That means `claude-hook` on SessionStart/UserPromptSubmit/Stop (with `asyncRewake`) and `codex-hook` on SessionStart. Each one already exits 0 in the wrong agent, so nothing goes into `~/.codex/config.toml`.
- **The setup script does the outside wiring.** Upstream's manual steps are not used. A new `plugins/agterm/scripts/setup.sh`, run by a `Setup` hook (matcher `init`) like `statusline`, is idempotent and never overwrites a line the user wrote:
  - It links `~/.local/bin/mailbox-chat.py` to the stable marketplace copy (`~/.claude/plugins/marketplaces/<marketplace>/plugins/agterm/scripts/mailbox-chat.py`). That path survives version bumps.
  - It adds the `host_executable` + `prefix_rule` pair to `~/.codex/rules/default.rules`, but only if `~/.codex` exists.
  - It adds `on message <stable path> agterm-hook` to agterm's `hooks.conf`, but only if the file exists. Then it runs `agtermctl hooks reload` and ignores any failure.
  - Dropped: README-only manual steps, which the user rejected. Dropped: Claude editing config in-session, which is slower and must be redone on each machine.
- **"ask codex" with no peer opens one.** Before the first send, the skill runs `mailbox-chat.py status`. If there is no split, or the other pane runs only a shell, the skill does three things:
  - It runs `agtermctl session split visibility on`.
  - It runs `agtermctl session restart --pane-id <other pane> --command 'codex --no-daemon "Answer with the single word READY."'`.
  - It polls `status` until `receiver` is `codex`, with a timeout of about 60 s. On timeout it reports and stops.

  If anything other than a shell runs in the other pane, the skill asks the user before replacing it. This differs from upstream, which never starts agents. The user picked it.
- **Claude calls the plugin's own copy. Codex calls the bare name.** The Claude side of the skill runs `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/mailbox-chat.py …`. The Codex side, `REPLY_LINE` and the Codex rule use the bare `mailbox-chat.py` on PATH. This keeps the approve hook's rule: "this plugin's script, not any file with the same name".
- **Auto-approve the two plain chat commands.** `approve-overlay.sh` gets a new branch for the `${CLAUDE_PLUGIN_ROOT}` prefix only. The branch approves `status`, and `say --stdin` fed by one quoted heredoc (`<<'X'` … `X`). The terminator must appear only as the last line, with nothing after it. A quoted heredoc expands nothing, so its body is safe. The current check exits on any `<` or newline, so heredocs need their own branch. Without this, auto mode prompts on every message. Any other shape gets no output, as today.

## Constraints / out of scope

- No port of other skills to Codex. No plan-review integration; that comes next.
- Do not touch `~/.codex/config.toml`, `~/.claude/settings.json`, or a user's own lines in `hooks.conf` / `default.rules`.
- `setup.sh` must not fail when Codex or agterm isn't installed. It skips that part.
- The existing hooks in the agterm `hooks.json` (overlay approve, `git-info.sh`) keep working unchanged.

## Traps

- Changing `hooks.json` changes its content hash. Codex then treats **all** agterm plugin hooks as untrusted until the user re-trusts them in Codex's `/hooks` (`hooks.state."agterm@parmaster-claude-dlc:hooks/hooks.json:*"` keys in `~/.codex/config.toml`). Until then, `codex-hook` doesn't run, and `receiver` stays `none`.
- Codex runs the plugin's `hooks.json` too. The `claude-hook` entries fire in Codex, where they exit 0 on `CLAUDE_CODE_ENTRYPOINT != "cli"` (`mailbox-chat.py`, `claude_hook`). The `codex-hook` entry fires in Claude, where `find_codex_pid` finds no codex ancestor. Check that Codex ignores `asyncRewake`/`rewakeSummary`/`timeout: 2000000` and does not block its session start on them.
- `Waiter.__init__` records `os.getppid()` as the Claude Code pid and loops while it is unchanged. The hook command must start Python directly (`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/mailbox-chat.py claude-hook`). It must not use a `bash` wrapper, which would make the parent pid a short-lived shell. Check how Claude Code spawns plugin hook commands.
- Not verified: whether plugin `hooks.json` honors `asyncRewake` like `settings.json` does. Upstream only tested `settings.json`. If plugin hooks ignore it, fall back to `setup.sh` writing the three entries into `settings.json`, and record that in Decisions.
- The bare name `mailbox-chat.py` is baked into `REPLY_LINE` and the Codex rule. `~/.local/bin` is on PATH on this machine. `setup.sh` should warn, not fail, when it isn't.
- Which path does Codex's `host_executable` match: the symlink in `~/.local/bin`, or its target? Test it. If unsure, list both paths in `paths=[…]`.
- `Setup` with matcher `init` fires only on `claude --init-only`, not on install or update (README statusline/global-rules sections). Users run `claude --init-only` once, like for the other plugins.
- `~/.config/agterm/hooks.conf`'s header comment lists no `message` kind. It is an older template. `agtermctl msg` exists here, so confirm `on message` loads cleanly (`agtermctl hooks list`).
- `session restart` ends the pane's shell and its foreground program (`agtermctl help session restart`). That is why the skill must check what runs there first.

## Definition of Done

- [x] Upstream unit tests pass against our copy of `mailbox-chat.py` — proof: they run inside `bash tests/run.sh`.
- [x] `setup.sh` is idempotent and leaves user lines alone — proof: `tests/run.sh` cases with a fake HOME:
  - a first run adds the link, the rules pair, and the hooks.conf line
  - a second run changes nothing
  - a missing `~/.codex` or missing `hooks.conf` is skipped with exit 0
  - an existing user line stays as it was
- [x] `approve-overlay.sh` approves the plugin-path `mailbox-chat.py status` and a single quoted-heredoc `say --stdin` — proof: `tests/run.sh` cases. It passes (no output) on each of these:
  - a bare `mailbox-chat.py status`
  - an unquoted heredoc
  - commands after the terminator
  - the terminator line partway through the body, followed by more commands
  - `$(…)` and `;`/`&&` chaining
- [x] Claude → Codex works end to end — proof: in a split with Codex READY, "ask codex what 2+2 is" gets a Codex turn, and Codex's reply arrives in the Claude pane as a new turn.
- [x] Codex → Claude works when Codex starts the chat — proof: "chat with claude about X" typed in the Codex pane starts a Claude turn.
- [x] "ask codex …" with no split opens one, starts Codex, waits for `receiver: codex`, then sends — proof: run it in an unsplit session.
- [x] Hooks are harmless in the other agent (Codex starts clean; `claude -p` not used, so not checked) — proof: a plain Codex session and a `claude -p` both start without delay or error. Codex re-trusts the agterm hooks once.
- [x] README agterm section describes the skill, its trigger phrases, the setup steps it automates, the manual steps (`claude --init-only` once, trust hooks in Codex `/hooks`), and the upstream credit.

## Wrap-up

- [ ] full test suite passes: `bash tests/run.sh`
- [ ] ⚠️ linter: `shellcheck` on new/changed shell scripts (repo has no lint target). `shellcheck` isn't installed here; `bash -n` passes.
- [ ] `plugins/agterm/.claude-plugin/plugin.json` bumped to 2.2.0, description mentions the chat; `CHANGELOG.md` entry `## agterm 2.2.0 - <date>`
- [ ] README.md updated
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-11-08-agterm-mailbox-chat.md docs/plans/completed/`)
- [ ] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update` in Claude and update the plugin in Codex.
- Run `claude --init-only` once on this machine to run the setup hook.
- In Codex, open `/hooks` and trust the changed agterm hooks.
