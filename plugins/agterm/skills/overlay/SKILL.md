---
name: overlay
description: Open a markdown file (rendered by glow), a local HTML file or a URL in an agterm overlay floating over the current session. Activates on "open the latest plan in glow", "show the plan in an overlay", "open <file.md> in glow", "open <file.md|file.html> in an overlay", "show <file.html> in agterm", "open <url> in an overlay". Only for viewing inside agterm; running programs or any other terminal control belongs to the agterm skill.
argument-hint: "[file.md | file.html | url]"
allowed-tools: Bash
---

# Open in an agterm Overlay

Show a markdown file, an HTML file or a URL in a floating overlay over this
session. The overlay takes keyboard focus and closes on `q` (glow), Cmd-W or
its close button; the session underneath is untouched.

## Pick the kind

| Request | Kind | Argument |
|---|---|---|
| "the latest plan", "the plan" with no file named | `md` | none — the script picks the newest file in `docs/plans/`, then `docs/plans/completed/` |
| a `.md` file | `md` | the path as given |
| an `.html` / `.htm` file | `html` | the path as given |
| an `http(s)://` or `file://` URL | `url` | the URL; add `--js` only if the page needs JavaScript |

A path relative to the current directory is fine; the script resolves it.
Anything else (a program, a `.txt` file, a directory) is out of scope — say so
instead of forcing it into one of these kinds.

## Run it

Run exactly this form — one plain command, nothing chained before or after it,
so the plugin's hook can approve it without a prompt:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/overlay.sh" <kind> "<argument>"
```

It prints `opened <path-or-url>` on success. On failure it prints a one-line
reason on stderr (not inside agterm, file not found, no plans found, glow
exited with status N) — pass that on as is and stop; don't retry with raw
`agtermctl` calls.
