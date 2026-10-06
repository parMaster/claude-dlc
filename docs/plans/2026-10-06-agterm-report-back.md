# agterm: spawned sessions can report back to the session that spawned them

**Goal:** A session started by `agterm:spawn-session` or `/agterm:handoff` knows which session spawned it, so "report back the result" lands in the right place.

**Kind of change:** feature

## Intent

Today a spawned session has no idea where it came from. To get its result into the session that started it, the user copies text between sessions by hand.

After this change, every spawned session's prompt ends with a short footer: who spawned it and the one command that sends a report back. The child does nothing with it unless the user (or the task prompt) asks for a report.

```
before:  parent --spawn--> child            (child can't reach parent)

after:   parent --spawn--> child
            ^                 |  user: "report back the result"
            |                 v
            +--- one typed line: Report from "<child>": read <file>
```

## Decisions

- **The footer is added by the two spawn scripts, not by the skills.** `agterm-spawn.sh` and `codex-spawn.sh` are the only way a session gets spawned, so `spawn-session`, both hand-off scripts and `oversight`'s kick-off all get it with no change of their own. The footer text is built in one shared place so the two runtimes can't drift. Dropped: writing the footer in each skill's prompt — three places to keep in sync.
- **The report travels as a file plus a one-line pointer.** The child writes its report to a file; a new helper script types `Report from "<child name>": read <absolute path>` into the parent and presses Enter. This mirrors how the task prompt already reaches a child. Dropped: typing the report text itself — a newline in typed text submits early, and long text through the typing channel is what the spawn scripts already avoid.
- **New helper: `scripts/report-back.sh <parent-session-id> <child-name> <report-file>`.** The footer gives its absolute path, resolved at spawn time, so a Codex child (no `CLAUDE_PLUGIN_ROOT`) can run it too. Dropped: putting raw `agtermctl` commands in the footer — the child would rebuild them by hand each time, and the two-step type-then-Enter is easy to get wrong.
- **The parent is identified by `$AGTERM_SESSION_ID` only.** No session name lookup: nothing in this repo reads a session's name from `agtermctl`, and the id is all the helper needs.
- **Report on request only.** The footer says so in plain words. An unasked report would type into a session the user may be working in.
- **No auto-approval hook for the helper.** The child asks for permission once when it reports. Typing into another session is a bigger step than opening an overlay on your own.

## Constraints / out of scope

- One hop only: a child reports to its direct parent. No chains, no parent-to-child messaging, no reply channel.
- Spawning must still work when the parent id is unknown — no footer, no error.
- The spawn scripts' arguments and stdout stay as they are; the skills that call them don't change.
- The helper never types anything except the fixed-format line and Enter, and only into the id it was given.

## Traps

- `AGTERM_SESSION_ID` can be unset where `AGTERM_ENABLED=1` still holds — the spawn scripts already handle the same gap for `AGTERM_WORKSPACE_ID` (agterm's quick terminal). `overlay.sh` treats an unset id as "not inside a session". (`plugins/agterm/scripts/agterm-session-new.sh`, `plugins/agterm/scripts/overlay.sh`)
- The prompt file belongs to the caller: `spawn-session` tells the model to `Edit` line 1 of it and rerun the spawn script when the first-line check fails. A rerun must not leave two footers. (`plugins/agterm/skills/spawn-session/SKILL.md`, Step 5)
- The typed line lands wherever the parent's cursor is. If `claude` has exited there, the shell runs it. Keep the line free of anything a shell would act on: strip quotes, `$`, backticks, `;`, `&`, `|`, `<`, `>` and newlines from the child name, and refuse a report path that has them.
- The helper's absolute path sits inside a versioned plugin cache directory. A plugin update while the child runs can remove it; the helper call then fails with "no such file", which is acceptable — don't build a fallback.
- The fake `agtermctl` in `tests/run.sh` records `session type --stdin` text to `$AGTERMCTL_TYPED` and logs every call to `$AGTERMCTL_LOG`; existing spawn tests assert on the prompt file path, not its contents, so they keep passing with a footer added. (`tests/run.sh`, "Shared fake agtermctl")
- agterm isn't installed on the machine this plan was written on, so real `agtermctl` behavior — typed text reaching a running `claude` as a submitted message — is proven only by the live check under Post-Completion.

## Definition of Done

- [ ] A Claude spawn with `AGTERM_SESSION_ID` set leaves the prompt file ending in a footer that names the parent id, the child's session name, the helper's absolute path, and says to report only when asked — proof: test asserts each on the prompt file after `agterm-spawn.sh`.
- [ ] The same holds for a Codex spawn — proof: same assertions after `codex-spawn.sh`.
- [ ] The original task prompt is still the start of the file, unchanged — proof: test compares the leading lines.
- [ ] With `AGTERM_SESSION_ID` unset, the spawn succeeds and the prompt file is byte-identical to what was passed in — proof: test.
- [ ] Spawning twice with the same prompt file leaves one footer — proof: test counts it.
- [ ] `report-back.sh` types exactly `Report from "<name>": read <absolute path>` and then Enter into the given id and nothing else — proof: test asserts on the fake's typed text and log.
- [ ] `report-back.sh` exits 1 with a one-line reason and makes no `agtermctl` call for: a missing argument, a report file that doesn't exist, a path with shell-active characters, `agtermctl` not on PATH — proof: one test each.
- [ ] A child name with quotes or `$` reaches the parent with those stripped — proof: test.
- [ ] `agterm` version bumped (minor: new script) with a `CHANGELOG.md` entry; README's agterm section says a spawned session can report back on request and how — proof: diff.

## Wrap-up

- [ ] full test suite passes: `bash tests/run.sh`
- [ ] linter passes: none configured — CI runs only `bash tests/run.sh`
- [ ] README.md / CLAUDE.md updated if behavior or patterns changed
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-10-06-agterm-report-back.md docs/plans/completed/`)
- [ ] single commit: all changes + plan move

## Post-Completion

- [ ] Live check inside agterm, after pushing and updating the plugin: spawn a session with `agterm:spawn-session`, tell it "report back the result", and see the `Report from …` line arrive in the parent as a submitted message that the parent then reads. Repeat once with the Codex runtime.
