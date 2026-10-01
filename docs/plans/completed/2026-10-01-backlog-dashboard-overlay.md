# Backlog dashboard in an agterm overlay

**Goal:** `/planning:backlog --dashboard` shows every `docs/backlog/` item on one filterable HTML page, opened in an agterm overlay.

**Kind of change:** feature

## Intent

The plain `/planning:backlog` listing is one line per item in the chat. It is fine for three items and
poor for thirty: no search, no filtering, and nothing shows at a glance which items are stale or not yet
committed. This adds a generated, self-contained HTML page with the whole store on it, and opens it over
the current session.

```
/planning:backlog --dashboard
        |
        v
planning script ── reads docs/backlog/*.md + git ──> one HTML file in the temp dir, prints its path
        |
        v
backlog skill ── Skill tool ──> agterm:overlay  html "<path>" --js ──> overlay over the session
        |
        └─ not in agterm / overlay fails ──> report the path, so it can be opened in a browser
```

What the page shows:

- **Header** — repo name, item count, branch and short commit it was read from, and a warning when the
  branch is not the default one ("this is the branch's copy of the backlog").
- **Stat tiles that are also filters** — all, worth yes / later / no, added in the last 7 days, `where`
  not found, uncommitted, and (display only) the age of the oldest item.
- **Search** over title, slug, `where` and body; `/` focuses it.
- **Sort** — default is the skill's own order (yes, later, no; oldest `added` first inside each), plus
  newest first and recently touched.
- **Area chips with counts** — one per area, plus `unanchored`.
- **One row per item** — worth badge, title, slug, `where`, `ticket` when present, area, "added N ago",
  "touched <date>". Clicking a row expands the item's body in place.

## Decisions

- **`planning` builds the page, `agterm` shows it** — the script only writes a file and prints its path;
  the skill hands that path to the `agterm:overlay` skill. Dropped: putting it all in `agterm` (copies the
  item format into a second plugin and makes the page useless outside agterm), and having the `planning`
  script call `agtermctl` itself (repeats `overlay.sh` and its approve hook, and adds agterm-only code to
  `planning` while another backlog item is moving such code out).
- **`--dashboard` is a new argument form of the `backlog` skill**, checked next to `--all` and before
  slug handling. It is read-only: it never asks a fix-or-drop question and never changes an item.
- **`overlay.sh html <file> [--js]`** — the `html` kind takes the same optional trailing `--js` the `url`
  kind already has. Without the flag it behaves exactly as today.
- **Bash + `jq` generator, one file out** — matches the other scripts and adds no dependency. The script
  collects the items as JSON and drops it into an HTML template with inline CSS and JS; no external
  scripts, fonts or styles, since the overlay page may have no network.
- **The script does facts, the page does dates** — the script emits `added`, last-commit date and the
  generation time; "N ago", "last 7 days" and "oldest" are worked out in the page's JS. This keeps date
  arithmetic out of bash, where macOS and Linux `date` differ.
- **Body is shown as plain preformatted text** when a row is expanded. A markdown renderer would need a
  bundled library for little gain; items are short prose.
- **Area = the directory of the `where` path, cut to its first two segments** (`plugins/planning`,
  `internal/window`); a top-level file gives its own name; no `where` gives `unanchored`. Dropped:
  guessing an area from the title — not reliable enough to filter by.
- **"`where` not found" means the path does not exist, or the line is past the end of the file.**
  Whether the line still says what the item claims is a judgment the listing flow makes; a script can't.
- **Default branch comes from `git symbolic-ref refs/remotes/origin/HEAD` only.** No `ls-remote`
  fallback: a viewer should not need the network. When it is unset, the header shows the branch with no
  warning.
- **Output goes to the temp dir** (`${TMPDIR:-/tmp}`), one fixed name per repo, overwritten each run —
  never inside the repo, where it would show up as an untracked file.
- **With JS off the page still says something** — a `<noscript>` line telling the reader to reopen it
  with `--js`, so a blank overlay is never the result.

## Constraints / out of scope

- The existing listing, slug and `--all` flows of `backlog` do not change.
- `overlay.sh md`, `url`, and `html` without `--js` behave as before; existing overlay tests pass unchanged.
- No editing from the page: no fix, drop or re-triage buttons. It is a viewer.
- No live refresh; rerun the command to regenerate.
- No hardcoded paths or machine-specific settings in the script.
- Outside a Git repo or with no `docs/backlog/`, the script says so in one line and exits non-zero; it
  does not create the directory.

## Traps

- `approve-overlay.sh` drops any command whose arguments contain `; & | < > $` or a backtick, leaving it
  to the normal permission prompt. The skill must pass the generated path as a literal string, not as
  `$(…)` or a variable, and the output file name must not contain those characters.
  (`plugins/agterm/scripts/approve-overlay.sh`)
- The hook already allows any `html …` call, so `--js` needs no hook change — but
  `tests/run.sh` should gain an approve case for the new form so that stays true.
- `overlay.sh` reads only `$2` for the `html` kind today and ignores `$3`. (`plugins/agterm/scripts/overlay.sh`)
- `overlay.sh html` passes `--cwd <dir of the file>`, which grants the page read access to that whole
  directory. With the file in the shared temp dir that is wider than needed; write it into its own
  subdirectory. (`plugins/agterm/scripts/overlay.sh`, `html` case)
- The existing test asserts the logged call contains `--html <file> --cwd <dir> --navigation`; put `--js`
  after those so the assertion still matches. (`tests/run.sh`, "html opens the absolute file")
- JSON inside a `<script>` tag ends at the first `</script>` in any item body. Escape `</` in the
  embedded data.
- Item text is untrusted for HTML purposes: titles and bodies contain backticks, `<`, `&`. Build rows with
  text nodes, not by pasting strings into markup.
- CI runs `tests/run.sh` on Ubuntu, development is on macOS: stick to flags both `sed`/`awk`/`date`/`mktemp`
  accept.
- A brand-new item has no commit, so `git log` gives no "touched" date; it must show as uncommitted, not
  as an error. A modified tracked item is also "uncommitted".
- The `backlog` skill's `allowed-tools` has no `Skill`; `oversight`, which calls another skill, lists it.
  (`plugins/planning/skills/backlog/SKILL.md`, `plugins/planning/skills/oversight/SKILL.md`)
- None of the three current items has a `where`, so this repo's own backlog exercises only `unanchored`;
  the tests need fixture items with a good `where`, a missing path and a line past the end.

## Definition of Done

- [x] The script, run in a repo with backlog items, writes one HTML file outside the repo and prints its
      path — proof: test runs it against a fixture repo, the printed path exists, `git status` in the
      fixture shows no new file.
- [x] The page's embedded data carries, per item: slug, title, worth, `where`, `ticket`, `added`, body,
      area, last-commit date, `where`-not-found flag, uncommitted flag — proof: test extracts the JSON
      from the file and checks each field on fixtures covering: good `where`, missing path, line past
      end, no `where`, committed, untracked, modified.
- [x] Header data carries repo name, item count, branch, short commit, and the not-default-branch flag —
      proof: test on the fixture's default branch (flag off) and on a second branch (flag on); and with
      `origin/HEAD` unset (flag off, no error).
- [x] An item body containing `</script>`, `<b>` and `&` does not break the page or inject markup —
      proof: test checks the file has exactly one closing data script tag and the body round-trips in
      the extracted JSON; opened by hand, the row shows the text literally.
- [x] No backlog dir, and not a Git repo, each give a one-line message and a non-zero exit — proof: tests.
- [x] `overlay.sh html <file> --js` passes `--js` to `agtermctl`; without the flag the call is unchanged
      — proof: new test on the fake `agtermctl` log, existing html test untouched and passing.
- [x] The approve hook allows `overlay.sh html "<path>" --js` — proof: new case in the approve list in
      `tests/run.sh`.
- [ ] ⚠️ (page checked by hand through `overlay.sh html … --js`; the skill path itself needs the
      updated plugins installed and was not run) `/planning:backlog --dashboard` in agterm opens the page in an overlay with working tiles, search
      (`/` focuses it), sort, area chips and row expand — proof: run it in this repo and try each; with
      the three current items the tiles read all 3, yes 2, later 1 (before this plan's own item is removed).
- [ ] ⚠️ (not run) Outside agterm the skill reports the file path instead of failing silently — proof: run the skill
      with `AGTERM_SESSION_ID` unset and see the path in the reply.
- [x] The `overlay` skill documents `--js` for the `html` kind and the `backlog` skill documents
      `--dashboard` — proof: read both `SKILL.md` files.
- [x] Versions and docs: `planning` minor bump, `agterm` minor bump, a `CHANGELOG.md` section for each,
      README sections for both — proof: `plugin.json` values match the changelog headings.
- [x] `docs/backlog/backlog-dashboard-in-agterm-overlay.md` is removed with `git rm` in the landing commit
      — proof: `git show --stat` lists the deletion.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] linter: the repo has none configured; `bash -n` on each new or changed script is clean
- [x] README.md updated for both plugins
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv docs/plans/2026-10-01-backlog-dashboard-overlay.md docs/plans/completed/`)
- [x] single commit: all changes + plan move + backlog item removal

## Post-Completion

- `/plugin` update for `planning` and `agterm` on each machine, then `/reload-plugins`, before the new
  argument works from the installed copy.
