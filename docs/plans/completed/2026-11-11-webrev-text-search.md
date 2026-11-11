# Webrev text search

**Goal:** `/` in the webrev page finds a substring anywhere in the document, highlights every match,
and `]`/`[` step through them.

**Kind of change:** feature

## Intent

The webrev page renders a file in a chromeless agterm overlay, so the webview has no Cmd-F. The only
search today is `t`, which fuzzy-filters headings. People also use webrev just to read documents. They
need to find a word or phrase in the body text, code lines included, and skim from one match to the next.

`/` opens the existing picker (the one `t` and `m` use) as a text search. It lists every block whose
text contains the query. Enter jumps to a match and keeps the search active. The page then highlights
every match, and `]`/`[` step to the next and previous one.

```
/ ──▶ picker "search text" ──type──▶ rows: <line>  …snippet with **hit**…
                                       │ Enter / click
                                       ▼
            search active: all matches highlighted, current one stronger, Search 3/17
                 │ ] / [ : next / prev match (wraps), scrolls it into view, sets current block
                 │ /     : reopen picker with the same query
                 ▼ Esc   : clear highlights (does not cancel the review)
```

## Decisions

- **Reuse the picker for the query, not a separate find bar** — the picker already handles input,
  arrows, Ctrl-n/p, Enter, Esc and click. Its list also gives an overview of where the hits are.
- **`]`/`[` step through matches** — `n`/`p` already step through notes, and the user chose free keys
  over overloading `n`/`p` or using `⌘G`, which agterm may take first.
- **Matches are occurrences, picker rows are blocks** — a block with three hits is one row but three
  steps. Enter on a row makes that block's first hit current.
- **Picker preselects the first hit at or after the current block** — so `/ word Enter` acts like a
  forward find from where you are reading.
- **Highlight with the CSS Custom Highlight API** (`CSS.highlights`, `::highlight()`) — it paints ranges
  without touching the DOM. Wrapping hits in `<mark>` would split text nodes that note placement,
  `keyOf` and the current-line code rely on. Without the API, stepping still works with no paint.
- **Substring match, case-insensitive, whitespace collapsed** — fuzzy matching over paragraphs matches
  almost anything. Headings (`t`) and notes (`m`) stay fuzzy.
- **Empty query shows no rows**, with a "type to search" hint.
- **Search button shows the position** — "Search 3/17" while a search is active.

## Constraints / out of scope

- Existing keys keep their meaning: `j`/`k`, `t`, `m`, `n`/`p`, `a`, `f`/`A`, `q`/`Q`, `⌘↵`.
- `Esc` cancels the review as before, except that it first clears an active search.
- No regex, no whole-word mode.
- Works for both page kinds: rendered markdown and plain text (code lines).

## Traps

- `cancel` closes the overlay at once when there are no notes (`page.html`, `cancel`). `Esc` with a
  search active must clear the search and return before reaching it.
- Block text spans many text nodes: highlight.js spans in code, inline code, links. Match offsets come
  from the whitespace-collapsed text, so they must be mapped back to (text node, offset) pairs to
  build a `Range`.
- `filterPick` always calls `fuzzy` and sorts by score; the text search needs its own path that keeps
  document order (`page.html`, `filterPick`).
- `paintTitle` paints the whole text, and `.toc-item .t` cuts long text with an ellipsis. Rows need a
  snippet around the hit.
- Blocks are `[data-ls]` elements: paragraphs, headings, table rows, `hr`, each code line. They don't
  nest, and notes are placed as siblings, so block text never includes a note.
- The page keydown handler returns early for an open picker, an open editor, or a Meta/Ctrl/Alt chord.
  `/`, `]`, `[` need `preventDefault`, or `/` lands in the focused query box.
- `tests/test_webrev.py` covers only the Python side. Nothing runs the page JS, so the proof is manual.

## Definition of Done

- [x] `/` opens the picker with a "search text" placeholder and no rows — proof: manual
- [x] typing lists, in document order, every block containing the query in any case, each with its line
      number and a snippet with the hit in bold — proof: manual, with a hit late in a long paragraph and
      one in a fenced code line
- [x] Enter jumps to the hit; every match in the page is highlighted, the current one stronger — proof: manual
- [x] `]`/`[` step through matches, wrap at the ends, and the button shows the position — proof: manual
- [ ] `Esc` with a search active clears it and leaves the review open; a second `Esc` behaves as before — proof: manual
- [ ] a plain text file searches its lines the same way — proof: manual
- [ ] `t`, `m`, `n`/`p` behave as before — proof: manual
- [ ] stays responsive while typing on a ~2000-line file — proof: manual
- [ ] SKILL.md "Page controls" and the README webrev row describe `/`, `]`/`[` — proof: read the diff
- [ ] agterm bumped to 2.4.0 with a `## agterm 2.4.0 - <date>` CHANGELOG entry — proof: read the diff

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] README.md / CLAUDE.md updated if behavior or patterns changed
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update` and `/reload-plugins` to get the new page in agterm.
