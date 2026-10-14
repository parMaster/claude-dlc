# Converge skill

**Goal:** A manual `/converge` skill that turns a sprawling explanation into a one-sentence-at-a-time dialogue the user drives.

**Kind of change:** feature

## Intent

A session that got a big task (often a spawned one, with a full screen of context) explores the code. Then it replies with two screens of explanation and ends with "a, b or c?". The user can't follow it. What worked by hand: "step back, start with one sentence". After that, the user asked short questions, often from Claude Code's native prompt suggestions, and the picture converged.

`/converge` makes that the default for the rest of the dialogue. It is the reverse of `brainstorm`: there, the agent asks and the user answers; here, the user asks and the agent answers.

```
brainstorm:  agent asks ──► user answers ──► agent asks ...
converge:    agent: 1 sentence ──► user asks ──► agent: 1 sentence ──► ... ──► user: "go"
```

The task can be anything: a bug, a feature, a refactor. The skill has no fixed steps such as problem → cause → fix.

## Decisions

- **The user drives the order.** The opener is one sentence on what the task is. After that, each reply answers the user's question in one sentence and stops. Fixed steps were dropped, because a feature task has no "cause", and fixed steps follow the agent's order, not the user's gaps.
- **No `AskUserQuestion`, no option menus.** A menu brings back the "a, b or c?" feel. A plain short reply leaves room for the native prompt suggestions, which proved good at picking the next question.
- **One recommendation when asked "what would you do".** Alternatives come only when the user asks for them.
- **One sentence is a test of understanding.** If the agent can't answer in one sentence, it checks the code first (Read/Grep/Glob, read-only Bash). It doesn't hand the confusion to the user. It may say "I don't know yet" in one sentence.
- **No work until the user says go.** "Go" (or a clear equivalent, like "do it") ends the converge mode. From then on, normal replies and normal work resume.
- **Manual only.** `disable-model-invocation: true`, as in `agterm/skills/handoff`. The user wants to run it by hand until the process proves itself.
- **Lives in the `brainstorm` plugin**, next to `brainstorm`. It's the same kind of skill: a dialogue mode, not a tool.
- **Kept small.** The SKILL.md should fit on one screen. Its weight comes from a few firm rules, not from phases.

## Constraints / out of scope

- `agterm/skills/spawn-session` stays unchanged. The spawned session gets the full context as today, and nothing runs `/converge` automatically.
- `brainstorm` stays unchanged.
- No hook and no settings change. This is a dialogue style the user calls on demand, so no harness mechanism fits.

## Traps

- **The per-prompt reminder pushes toward lists and diagrams.** The `global-rules` `UserPromptSubmit` hook adds "Put 3+ related points in a list. Draw a flow" to every prompt. The skill must say plainly that converge replies are one sentence, with no list, heading or diagram, until "go".
- **The skill text loads once.** It sits in context from the turn it was called, and its rules can fade over a long Q&A, as the brevity rules did. Accepted: the user can run `/converge` again. Don't add a hook for it.
- **The long reply is still in context.** The agent will want to refer to it ("as I said above"). The skill must say each sentence stands on its own.
- **The opener must be about the task, not about the agent.** "Let me step back" or "I'll keep it short" is the wrong first sentence.
- **`allowed-tools` pre-approves, it doesn't restrict.** The "no work until go" rule is prose, so the SKILL.md must state it plainly.

## Definition of Done

- [x] `plugins/brainstorm/skills/converge/SKILL.md` exists with `name`, `description`, `disable-model-invocation: true` and read-only `allowed-tools` — proof: read the file.
- [x] The skill states: one-sentence opener about the task; one-sentence answers; stop after each; no menus or `AskUserQuestion`; check the code instead of guessing; one recommendation unless asked; no list, heading or diagram; no work until "go", then normal mode — proof: read the file against this list.
- [ ] ⚠️ The skill doesn't appear as model-invocable, and `/converge` works by hand — proof: `claude --plugin-dir plugins/brainstorm`, run `/brainstorm:converge` in a session that has some context, and see a one-sentence opener that stops. Left for the user after push.
- [x] `brainstorm` plugin goes to 1.1.0, with a CHANGELOG entry `## brainstorm 1.1.0 - <date>` — proof: `plugin.json` and `CHANGELOG.md`.
- [x] README's brainstorm section has a `converge` row, and the plugin's one-line description covers both skills; `plugin.json` and `marketplace.json` descriptions match it — proof: grep `converge` in `README.md`.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter passes: none for this repo beyond `tests/run.sh`
- [x] README.md updated (see DoD)
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-10-14-converge-skill.md docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update parmaster-claude-dlc`, `/plugin install brainstorm@parmaster-claude-dlc`, `/reload-plugins`.
- Try it on the next spawned session that sprawls. If it works, decide later whether spawn-session should mention it.
