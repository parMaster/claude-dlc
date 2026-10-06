# agterm: spawned Claude sessions can report back to the session that spawned them

**Goal:** A Claude session started by `agterm:spawn-session` or `/agterm:handoff` knows the Claude name of the session that spawned it, so "report back the result" reaches the right session through `SendMessage`.

**Kind of change:** feature

## Intent

Today a spawned session has no idea where it came from. To get its result into the session that started it, the user copies text between sessions by hand.

After this change, a spawned Claude session's prompt ends with one short footer naming the parent's Claude session and saying to report there with `SendMessage` when the task or the user asks. Nothing else changes: no new script, nothing typed into the parent's terminal.

```
spawning skill                      child (Claude)
  ListAgents -> "This session is      prompt ends with footer
                 claude-dlc-8d"  -->  "Spawned from Claude session claude-dlc-8d ..."
                                        |  user or task: "report back"
  <-------- SendMessage(to: "claude-dlc-8d") --------+
```

Checked live in agterm before writing this: a child spawned with this footer sent its result with `SendMessage`, and it arrived in the parent within seconds, even though the parent was mid-turn. The child didn't ask for permission (manual mode) and nothing was typed into the parent.

## Decisions

- **Claude-to-Claude only, via `SendMessage`.** Claude Code delivers the message itself and queues it if the parent is busy. Dropped: typing a line into the parent with `agtermctl session type`. A live test showed the keystrokes answer a pending permission dialog in the parent: Enter or a digit approves it, with nobody watching.
- **The parent's name comes from `ListAgents`, called by the spawning skill.** The name (e.g. `claude-dlc-8d`) isn't in any environment variable, so the bash scripts can't find it themselves. Use the bare name from the "This session is <name> [<ref>]" line, without the bracketed ref.
- **Where the footer goes:**
  - `spawn-session` writes it into its own prompt heredoc, Claude runtime only.
  - `handoff` passes the name to `agterm-handoff.sh` as a new optional third argument, and `build_handoff_prompt` adds the footer when the name is present.
  - `oversight`'s kick-off goes through `spawn-session`, so it gets the footer with no change.
  - The footer text lives in two places, the `spawn-session` SKILL.md and `handoff-prompt.sh`. Keep the wording identical.
- **Footer wording**, one or two lines: `Spawned from Claude session <name>. When the task or the user asks you to report back, send the result there with SendMessage (to: "<name>").` Dropped: "report only when asked". In the live test, that phrase made the child ignore a "report back" written in its own task.
- **This brings back part of what was removed on Sep 14.** That version addressed every message ahead of time across a multi-session chain, and it was unreliable. This one is a single hop, and the child only reports when asked.

## Constraints / out of scope

- Codex children: no footer. `codex-spawn.sh`, `codex-handoff.sh` and the Codex branches of both skills stay as they are.
- One hop only: a child reports to its direct parent. No parent-to-child messaging.
- If `ListAgents` isn't available or returns no name, the spawn goes ahead without a footer and with no error.
- `agterm-spawn.sh` doesn't change. `agterm-handoff.sh` keeps working when called with only `<plan-file> [model]`.

## Traps

- `handoff-prompt.sh` is sourced by both `agterm-handoff.sh` and `codex-handoff.sh`. The footer must stay off unless a name is passed, so the Codex prompt stays as it is. (`plugins/agterm/scripts/handoff-prompt.sh`, `build_handoff_prompt`)
- `spawn-session` Step 5 checks line 1 of the prompt and, if the check fails, the model edits line 1 and reruns only the spawn script. The footer goes at the end of the heredoc, so the rerun never adds it again. Don't move the footer into the spawn script, or a rerun would add a second copy. (`plugins/agterm/skills/spawn-session/SKILL.md`, Step 5)
- Both skills' `allowed-tools` are `Bash, AskUserQuestion`. Add `ListAgents` to both, or the call prompts for permission. (`plugins/agterm/skills/spawn-session/SKILL.md`, `plugins/agterm/skills/handoff/SKILL.md`)
- The child appears to the parent under its own auto-generated Claude name, taken from its working directory (e.g. `scratchpad-5e`), not its agterm label. That's fine here, but it's why the footer can't ask the child to identify itself by its agterm name.
- An existing handoff test asserts the prompt file "never mentions SendMessage callback". It runs without a name, so it should keep passing. Keep it as the no-name case; don't delete it. The tests already get the prompt file path from the typed `claude "$(cat <path>)"` line, and new tests can do the same. (`tests/run.sh`, "agterm/agterm-handoff.sh")

## Definition of Done

- [x] `agterm-handoff.sh <plan> <model> <name>` leaves a prompt file that starts with the unchanged hand-off text and ends with the footer naming `<name>` — proof: test in `tests/run.sh`.
- [x] `agterm-handoff.sh <plan> [model]` without a name leaves the prompt file exactly as before, with no footer — proof: test.
- [x] `codex-handoff.sh`'s prompt file has no footer — proof: test.
- [x] `spawn-session` (Claude runtime) and `handoff` (Claude runtime) call `ListAgents` and pass or write the name. Both list `ListAgents` in `allowed-tools`. Neither does this for Codex — proof: diff.
- [x] `agterm` bumped 1.2.1 → 1.3.0 with a `CHANGELOG.md` entry. README's agterm section says a spawned Claude session can report back with `SendMessage` when asked — proof: diff.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter passes: none configured; CI runs only `bash tests/run.sh`
- [x] README.md / CLAUDE.md updated if behavior or patterns changed
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-10-06-agterm-report-back.md docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- [x] Live check after pushing and updating the plugin: spawn a session with `agterm:spawn-session` and tell it "report back the result". The result should arrive in the parent as a message from another session. Repeat once with `/agterm:handoff`.
