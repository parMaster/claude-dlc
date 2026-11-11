# Codex as a plan reviewer

**Goal:** `/planning:review-plan` can send the plan to Codex in the other agterm pane with the same instructions the `plan-review` agent uses, and Claude checks Codex's findings before it applies any.

**Kind of change:** feature

## Intent

Today the user asks Claude to "ask codex to review the plan" through `/agterm:mailbox-chat`. Codex then gets whatever prompt Claude makes up on the spot, not the strict checklist in `plugins/planning/agents/plan-review.md`. When the review comes back, nothing tells Claude to check it, so it tends to accept every finding.

After the change, `review-plan` offers Codex as a third reviewer next to Opus and Sonnet. Codex reads the same `plan-review.md` instructions, so both reviewers judge the plan by one checklist. Codex's reply goes through the same triage as the subagent's: Claude checks each finding against the code and the checklist, applies what holds up, and reports what it rejected and why.

```
review-plan Step 1: Opus | Sonnet | Codex
                                     │
   Step 2 (Codex) ── mailbox-chat say ──► Codex pane
                                     reads plan-review.md + plan, read-only
   later turn: [peer chat] review ◄──────┘
        │
   mailbox-chat Receiving: "a plan review you asked for" ──► review-plan Step 3 triage
```

## Decisions

- **Codex is an option in `review-plan`, not a section in `mailbox-chat`** — `review-plan` already owns the prompt and the triage. A copy in `mailbox-chat` would drift. The user chose this.
- **Codex gets a path to `plan-review.md`, not a pasted copy** — one source of truth, and the mailbox rules say long text goes in a file anyway. Claude resolves the absolute path from the skill's base directory (`<base>/../../agents/plan-review.md`). Codex has no `CLAUDE_PLUGIN_ROOT`.
- **The send goes through `/agterm:mailbox-chat`** — that skill owns the script path, the `status` check and starting Codex when it isn't there. `review-plan` only says what the message holds: the plan path, the instructions path, "read-only", and "reply with the report in the `Output` format".
- **Triage stays one step for both reviewers, with stricter wording** — Step 3 gets explicit grounds to reject: the code doesn't back it, the finding asks for what `plan-review.md` says not to flag (code, file lists, test names, wording), or it is padding. This also tightens the subagent path, which is fine: same checklist, same bar.
- **No reply to Codex about rejected findings** — Claude reports applied and rejected findings to the user only. That keeps the agents from arguing in a loop. The user can say "tell codex" any time. The user chose this.
- **`mailbox-chat` gets one pointer line** — in Receiving: a `[peer chat]` message that is a plan review Claude asked for goes to `review-plan` Step 3, and Claude doesn't answer it with `say`.
- **Codex review only when the session runs in agterm** — the option shows only when `AGTERM_SESSION_ID` is set; elsewhere the question stays Opus / Sonnet.

## Constraints / out of scope

- The subagent path (Opus / Sonnet) behaves as before, apart from the stricter Step 3 wording.
- `plan-review.md` content doesn't change. Its frontmatter line "not for direct use" stays; it doesn't confuse Codex.
- No changes to `mailbox-chat.py` or the hooks.
- No second review pass, same as today.

## Traps

- The review arrives in a later turn, not as a tool result. Step 2's "print the report verbatim" must hold there too. `mailbox-chat` Receiving already quotes the message in full; if Codex sends a `/tmp` path instead of inline text, Claude must read the file and print it (`plugins/agterm/skills/mailbox-chat/SKILL.md`, "Sending — both").
- `${CLAUDE_PLUGIN_ROOT}` inside `review-plan` is the planning plugin's root. It can't reach `mailbox-chat.py`, which lives in agterm. That's why the send goes through the other skill.
- `mailbox-chat` "Shared work" already makes the peer read-only. The message should still say "read-only" because `plan-review.md` says it too and Codex may skim.
- When `status` reports `receiver: claude`, `mailbox-chat` sends only if the user asked for that. Choosing "Codex" in `review-plan` is not that request.

## Definition of Done

- [ ] `review-plan` Step 1 offers Codex when `AGTERM_SESSION_ID` is set, and only then — proof: read the Step 1 text; run the skill inside and outside agterm.
- [ ] Choosing Codex sends a message naming the plan file and the absolute path of `plan-review.md` — proof: live run, the italic summary line and Codex's pane show both paths, and Codex reads that file.
- [ ] Codex's report comes back in the `plan-review` Output format and Claude prints it in full — proof: live run.
- [ ] Claude triages the reply with Step 3: checks code claims with its own tool calls, rejects with a reason, never answers Codex — proof: live run on a plan with at least one finding; the report lists applied and rejected items; no `say` after the review.
- [x] Step 3 names the grounds to reject (unbacked by code, a "what not to flag" item, padding) for both reviewers — proof: read the Step 3 text.
- [x] `mailbox-chat` Receiving sends a returning plan review to `review-plan` Step 3 — proof: read the text.
- [x] planning bumped to 3.7.0, agterm to 2.3.0, `CHANGELOG.md` has both sections — proof: `git diff`.
- [x] README rows for `review-plan` and `mailbox-chat` mention the Codex review — proof: read README.
- [x] ➕ `review-plan` lists `Skill` in `allowed-tools`, so it can call `/agterm:mailbox-chat`.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] README.md updated
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-11-11-codex-plan-reviewer.md docs/plans/completed/`)
- [ ] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update` and `/reload-plugins` before the live test.
