---
name: webrev
description: Open a markdown or text file - a plan, a document, or a draft such as a PR body, an issue comment or a commit message - as a rendered page in an agterm overlay, where the user attaches notes to blocks, code lines or the whole file and hands them back as annotation records. Use when the user says "webrev", "/webrev", "web review", "open the plan", "open the latest plan", "show the plan", "open <file.md>", "annotate this plan", "let me annotate this", "review this doc", "review this draft before posting", "let me review the PR body first", or "let me review the commit message". Not for diffs, and not for a plan critique by Claude (that is planning:review-plan).
argument-hint: "[file]"
allowed-tools: Bash
---

# webrev

Requires agterm (`AGTERM_SESSION_ID` set). Outside agterm, say so and stop.

## Launch

Run exactly this form, as a foreground Bash call with `timeout: 600000`:

```
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/webrev.py" review "<file>"
```

Leave the file out to open the newest plan in `docs/plans/`, then `docs/plans/completed/` — use that for
"open the plan" or "open the latest plan" with no file named. Keep it one plain command, nothing chained,
and write every path out in full: the plugin's hook approves only that form, and a `$VAR` or `$(…)` makes
it step aside and prompt. Never run it in the background: Claude Code's status hooks would overwrite the
blinking blocked status the page sets.

The script prints `webrev: page <page-id>` and `webrev: backup <path>` on stderr, then waits for the
user. The page opens at 95% of the session. Options, placed after the file:

- `--fit` for a short draft (a commit message, a comment, a short PR body): the panel is sized to the
  text. If it fails because the session is presented from another Mac (`--width/--height are not
  supported`), run again without it.
- `--size N` for another percent; `--pane left|right` to cover one split pane at full size. Neither
  combines with `--fit`.
- `--title "<what it is>"` when the file is a temp file holding generated content, for example
  `--title "PR description: add retries"`. Annotation records keep the real path.

`WEBREV_STYLE=terminal` in the environment switches to a flat terminal-like look; any other value is an
error. `WEBREV_BACKGROUND` and `WEBREV_FOREGROUND` (`#rrggbb`) replace the theme's page colors; anything
else is an error.

## Result

- exit 0: stdout is the annotations. Empty stdout means the user submitted with no notes: done.
- exit 2: the user cancelled. Stop, change nothing.
- exit 1: report the stderr text verbatim.

When the call times out after 10 minutes, the page is still open and the user is still writing. Do not
relaunch `review`: agterm refuses a second overlay in the slot. Attach to the same page again, the same
way, with the page id from stderr:

```
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/webrev.py" wait <page-id>
```

`wait` sets the blocked status again and has the same exit codes. Repeat it after each timeout until it
returns; never ask the user to say "done". If the waiter was lost some other way, read the backup file
from stderr: the annotations once recorded (empty for no notes), `dismissed` for a cancel, or
`pending <page-id>` while unanswered. `webrev.py result <page-id>` reads the outcome once without waiting
(same exit codes, 1 while pending).

## Annotation format

```
## docs/plan.md (file-level)
split this into two plans

## docs/plan.md:12-15 ( )
this paragraph contradicts task 3

## docs/plan.md:40 ( )
wrong flag name
```

A paragraph, heading, list item or table row reports its source line range; a line in a code block
reports itself. Paths are relative to the cwd the script ran in, absolute outside it.

## Process

1. Split notes into questions and directives. A question contains `??` or opens with `explain`,
   `remind`, `describe`, `what is`, `what are`, `how does`, `how do` or `clarify` (case-insensitive):
   answer it in chat, change nothing for it.
2. Treat every other note as an instruction to change the file at that location, and make the changes.
3. Relaunch webrev on the same file so the user can check the result. Stop when a review comes back
   empty or cancelled.

## Review a draft before posting

Use this when the user asks to review a draft before it goes out: a PR or issue body, a comment, release
notes, or a commit message.

1. Write the draft with the Write tool to a new file in the scratchpad directory (or `/tmp` when there is
   none): `draft.md` for forge text, `draft.txt` for a commit message. The extension decides whether the
   page renders markdown.
2. Run `review` on it with `--title` naming what it is and where it goes, for example
   `--title "PR comment: owner/repo#42"`. Add `--fit` for a commit message, a comment or a short body.
3. On exit 0 with notes, answer the questions in chat and apply the directives to the draft file, then
   review it again. A question never authorizes an edit.
4. On exit 2, stop: the draft is not approved, and nothing is posted or committed. Ask the user what to do
   with it. On exit 1 or a lost result, follow Result; a review that cannot be read is not a clean one.
5. On exit 0 with empty stdout, the review is clean:
   - A commit message is approved by the clean review, since the user already asked for the commit. Commit
     with that file (`git commit -F <draft.txt>`). The review approves the message only, never changes
     staged beyond what the user asked to commit.
   - Anything posted to a forge needs an explicit go-ahead. Show the final text, name the action and the
     destination ("post this comment on owner/repo#42"), and wait for the user to confirm. Post from the
     same file (`--body-file`, `-F`), so the text that goes out is the text that was reviewed.
6. Any edit after the clean review, the user's or yours, sends the draft back to step 2.

## Page controls

The left rail shows each block's first source line; hovering a block shows a `+` there, and an
annotated block keeps an amber `✎`. Click a block, code line or its `+` to annotate it; click a note
to edit or delete it. `j`/`k` move, Page Up/Down and Home/End scroll and move with the view, `Enter` or `a`
annotates the current block, `f` or `A` opens the file note, `t` (or Contents) opens a heading list for
markdown with fuzzy search (arrows or Ctrl-n/p move, Enter jumps, Esc closes), `m` (or the Notes button)
opens the same list for the notes, `n`/`p` jump to the next and previous note, `⌘↵` saves a note, `Esc`
closes the editor. An open editor keeps its text and the keyboard until saved or closed: a click elsewhere
and keys typed after selecting page text go back to it, while `⌘C` copies the selection. Outside an editor
`⌘↵` submits at once when there are no saved notes; with notes it needs a second press within 3 seconds, so
a habitual extra press after saving cannot send the review; the Submit button sends at once. `Esc` outside
an editor or list cancels the review, the same as the Cancel button: with notes it asks for a second `Esc`
or click within 3 seconds before discarding them. `q` submits at once, like the Submit button, and `Q`
cancels the same way `Esc` does. Saved notes survive a theme change reload of the page, not its closing;
text still open in an editor does not.
