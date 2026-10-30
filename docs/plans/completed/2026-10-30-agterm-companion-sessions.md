# Spawn and hand off into agterm companion sessions

**Goal:** `spawn-session` and `handoff` create an agterm companion of the calling session instead of a standalone session.

**Kind of change:** feature

## Intent

agterm now has companion sessions: `agtermctl session new --parent SID` creates a session pinned under SID in the sidebar. Today a hand-off opens a standalone session in the caller's workspace, or in a named workspace that `spawn-session` creates for slices of a larger job. A hand-off belongs to the session that started it, so it should sit under that session as a companion. Slices then group under their parent without a separate workspace.

```
before:                                   after:
Workspace A                               Workspace A
  ├─ caller                                 └─ caller
  └─ Implement: foo                             ├─ Implement: foo   (companion)
Workspace "Refactor" (slices)                   ├─ Spawn: slice-1   (companion)
  ├─ Spawn: slice-1                             └─ Spawn: slice-2   (companion)
  └─ Spawn: slice-2
```

## Decisions

- **Every hand-off is a companion of `$AGTERM_SESSION_ID`** — `agterm-session-new.sh` is the single place sessions get created, so the change lives there and reaches all four entry points (`agterm-spawn.sh`, `codex-spawn.sh`, `agterm-handoff.sh`, `codex-handoff.sh`). When the variable is unset (agterm's quick terminal), pass `--parent active`.
- **Drop the workspace-name argument** from `agterm-session-new.sh`, `agterm-spawn.sh` and `codex-spawn.sh`. `--parent` refuses `--workspace-name`, and companions already group slices under their parent. The trailing flags argument moves from position 5 to 4. Keeping the slot as an ignored "" was dropped: it would leave a dead argument in every call.
- **Keep flagging and focusing** — the new companion is still flagged and still selected, as today.
- **Minor version bump** (agterm 1.3.1 → 1.4.0): the session's place in the sidebar changes, and the scripts' positional arguments change.

## Constraints / out of scope

- Prompt delivery stays as it is: the launch command is typed into the new shell. Switching to `session new --command` is a separate change.
- An agterm without `--parent` is not supported; no fallback to the old path.

## Traps

- `--parent` refuses `--workspace`, `--workspace-name`, `--create-workspace`, `--after` and `--before`. `--cwd` is allowed and must still be passed, because the default is the parent's focused directory, not the project root (`agtermctl session new --help`).
- A companion SID passed as `--parent` resolves to its parent. A hand-off from inside a companion becomes a sibling, not a grandchild. That is fine; don't work around it.
- Both handoff wrappers pass `""` as the 4th argument to keep the flags in slot 5 (`agterm-handoff.sh` last line, `codex-handoff.sh` last line). They must drop that `""` together with the argument change, or the flags land in the wrong slot.
- The tests set `AGTERM_WORKSPACE_ID` and assert `--workspace ws-1` / `--workspace-name ... --create-workspace` for session-new, agterm-spawn and codex-spawn (`tests/run.sh`, sections `agterm/agterm-session-new.sh`, `agterm/agterm-spawn.sh`, `agterm/codex-spawn.sh`). The flags cases pass `""` in slot 4 too.
- `spawn-session/SKILL.md` Steps 2, 5 and 6 tell the model to choose a workspace name, pass it positionally, and report it. The examples in Step 5 show the old argument order.

## Definition of Done

- [x] `agterm-session-new.sh` runs `session new --parent "$AGTERM_SESSION_ID"` with `--cwd` and `--name`, and no workspace flags — proof: test asserts ` --parent sess-1` and no ` --workspace` in the fake agtermctl log
- [x] with `AGTERM_SESSION_ID` unset it passes `--parent active` — proof: test
- [x] `agterm-spawn.sh` and `codex-spawn.sh` take `<cwd> <session-name> <prompt-file> [flags]`, and flags in slot 4 reach the launch command — proof: updated flags tests
- [x] both handoff wrappers create a companion and keep their flags (`--permission-mode ...`, codex sandbox flags) — proof: existing handoff tests pass with the new log assertions
- [x] `spawn-session/SKILL.md` no longer mentions workspaces; slices are described as companions of this session; Step 5 examples match the new argument order — proof: `grep -i workspace plugins/agterm/skills` returns nothing
- [x] `handoff/SKILL.md` says the session opens as a companion of this one — proof: read
- [x] README agterm section says hand-offs open as companions — proof: read
- [ ] ⚠️ manual (needs a live agterm session): run `/agterm:spawn-session` in agterm; the new session appears indented under the caller — proof: `agtermctl tree --json` shows its `parent` set to the caller's id

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter passes: `shellcheck plugins/agterm/scripts/*.sh` (if installed) — only pre-existing info-level notes
- [x] README.md updated
- [x] agterm `plugin.json` bumped to 1.4.0, `CHANGELOG.md` entry `## agterm 1.4.0 - <date>`
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [ ] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update` and `/reload-plugins` to pick up the new scripts.
