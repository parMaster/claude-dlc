---
worth: later
added: 2026-09-30
---
# browse the backlog as an HTML dashboard in an agterm overlay

Seen elsewhere: a generated HTML page listing the whole `docs/backlog/` store, opened in an agterm overlay.
What it showed:

- A header with the repo, item count, branch and commit it was read from, and a warning when the branch
  isn't the default one ("this is the branch's copy of the backlog").
- Stat tiles that double as filters: all items, worth yes / later / no, added in the last 7 days, `where`
  not found (stale), uncommitted, and the age of the oldest item.
- A search box over titles, slugs, `where` and body text, plus a sort picker (yes, later, no; oldest first
  by default).
- Tag chips by area with counts, derived from the `where` path or the title; `unanchored` for items with no
  `where`.
- One row per item: worth badge, H1, slug, `where`, area, "added N ago" and "touched <date>" (last commit on
  the file). Clicking a row opens the item; `/` focuses search.

Natural fit: `backlog` generates a self-contained HTML file and hands it to the `agterm` plugin's `overlay`
(`html` kind), which already exists.

Still open, which is why this is `later`: whether it beats the plain `/planning:backlog` listing enough to be
worth building. Try it on a repo with a backlog big enough to need filtering before deciding.
