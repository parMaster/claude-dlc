# Make webrev the default markdown viewer in agterm

**Goal:** Ship upstream agterm's `annotate-document` recipe (webrev) in the `agterm` plugin, drop the glow path, then apply the user's visibility fixes to its page.

**Kind of change:** feature

## Intent

Today "open the plan" in agterm runs glow through the `overlay` skill. Glow only shows the file, so feedback still goes through chat or revdiff. webrev renders the same file as a page where the user clicks a block, writes a note, and submits. Claude gets the notes as revdiff-style records, applies them, and reopens the page until a review comes back empty. The user tried it from `~/.claude/skills/webrev` and wants it as the default. The page also has small visibility issues the user will list during plan review.

```
before:  "open the plan" ─▶ overlay md ─▶ glow (read only, q closes)
after:   "open the plan" ─▶ agterm:webrev ─▶ page ─▶ notes ─▶ Claude edits ─▶ page again
                                                  └─ submit with no notes / cancel ─▶ done
         overlay skill    ─▶ html | url only (backlog dashboard, pages, dev servers)
```

## Decisions

- **Vendor the recipe into `plugins/agterm`** as a `webrev` skill, `scripts/webrev.py` and `assets/`. A runtime fetch from GitHub would run remote code in a page that can drive agterm, the reason upstream inlines its JS libraries. Copy from upstream `acf8d4b0` (agterm `cookbook/annotate-document`); keep the two library LICENSE files and credit agterm (MIT) in README, like the cc-thingz credits.
- **Remove the glow path** (user's choice). `overlay` keeps `html` and `url`; markdown always goes to webrev. glow stops being a dependency.
- **Move "open the latest plan" to webrev.** With no file named, the skill opens the newest file in `docs/plans/`, then `docs/plans/completed/`, the same rule `overlay.sh md` uses now. Pressing `q` with no notes ends it, so plain viewing still costs one key.
- **Approve webrev through the existing PreToolUse hook**, extended to a plain `webrev.py review|result` call of this plugin's script. Same rules as today: no `;&|<>` backticks or `$` in the arguments, never deny.
- **No `mktemp` step.** Without `--output`, `review` writes its backup itself, to `<tmp>/webrev/<page-id>.result`, and prints that path on stderr next to the page id. A review is then one approved call. Upstream asks for a separate `mktemp -d` call, and with the full scratchpad path the user had to approve that call every time. `--output` stays for callers that want their own path.
- **Add `webrev.py wait <page-id>`** so a review can outlast the 10-minute Bash cap. It attaches to a page that is already open, sets the blinking blocked status again, and waits the same way `review` does, with the same exit codes and backup file. After a timeout the skill runs `wait` in the foreground again, as often as needed, so the user never has to say "done". Upstream's `result` only reads the outcome once, so it is not enough on its own.
- **Softer contrast, still following the theme** (user's choice). The page keeps reading `--agterm-foreground` and `--agterm-background`, but body text mixes the foreground about 75% toward the background. The user's reference is `#bbbbbb` on `#242321`. A fixed palette was dropped because it would break light themes. Changing the agterm theme itself was dropped because it changes the terminal too.
- **Body type like the user's markdown preview:** 16px, weight 500, line-height 1.5, JetBrains Mono. The font is already first in the page's `--mono` stack. These apply to the default look; `WEBREV_STYLE=terminal` keeps its own tighter type.
- ➕ **Page background is the terminal background.** Upstream darkens it to match agterm's sidebar tint (`sidebarBackgroundShift`). At the user's setting of 10 that made it 30% darker, which the user found too contrasty. The page now ignores the shift, and `webrev.py` no longer reads agterm's `settings.json`.
- ➕ **`WEBREV_BACKGROUND` / `WEBREV_FOREGROUND` env vars** (user's choice). The user wants `#292827` / `#dbdbdb`. Hardcoding them would break the repo's no-personal-config rule and light themes. A set foreground is used as is, not softened. Only `#rrggbb` is accepted, because the value ends up in a CSS property. The user's values live in `~/.claude/settings.json` `env`.
- **Keep revdiff next to webrev** in `plan`, `review-plan` and the README flow. revdiff still reviews diffs; webrev reviews the plan text.
- **Version:** agterm 2.0.0, because `overlay md` goes away. planning gets a patch bump for the wording changes.

## Constraints / out of scope

- The backlog dashboard keeps opening through `overlay html --js`; it must still work.
- No new runtime dependency beyond `python3` 3.10+ and agterm 0.38.1+, which the README states.
- The README's optional "Glow Selection" key command is standalone user config, not plugin code. Leave it.
- Upstream's draft-review flow (PR bodies, commit messages) ships as is; no CLAUDE.md rule makes it mandatory.

## Traps

- A skill's `allowed-tools` does not get past the auto-mode classifier. That is why `approve-overlay.sh` exists (its header says so). Upstream's `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/…)` line alone would prompt or get blocked in auto mode.
- `webrev.py` finds its libraries at `Path(__file__).parent.parent / "assets"`. In the plugin that means `plugins/agterm/assets/`, not `scripts/assets/` (`webrev.py`, `ASSETS`).
- The upstream skill uses `${CLAUDE_SKILL_DIR}`. In a plugin script path it must become `${CLAUDE_PLUGIN_ROOT}/scripts/webrev.py`, the form the hook matches.
- The review call blocks until the user answers. It must run in the foreground with `timeout: 600000`; a background task lets Claude Code's status hooks overwrite the blinking blocked status (`webrev.py`, `wait_outcome`).
- Upstream's description triggers on "review this plan". That collides with `planning:review-plan` ("review plan"). Drop it and trigger on "webrev", "open/show the plan", "annotate this plan", "let me annotate this".
- `approve-overlay.sh` rejects any `$` in the arguments. So the `--output` backup path must be written out literally, never `$TMPDIR/...`.
- At the timeout, Claude Code's SIGTERM ends the waiter through `sys.exit(143)`, and its `finally` sets the status to idle while the page stays open (`webrev.py`, `wait_outcome`). So `wait` must set blocked again when it attaches.
- Body type is set twice in `assets/page.html`: `body` sets `15px/1.6`, then `#doc` sets `line-height: 1.3`, which wins for the document. Changing only `body` leaves the document at 1.3. `--muted`, `--faint` and `--rule` are mixed from `--fg`, so softening `--fg` itself would also dim the rail numbers and rules. Soften the document's text color instead.
- An open webrev page fills the overlay slot. agterm refuses a second overlay there, so do not relaunch while a result is `pending` (upstream SKILL.md, Launch).

## Definition of Done

- [x] `/agterm:webrev docs/plans/<file>.md` opens the page, and notes come back as records — proof: manual runs of the repo's `webrev.py` in agterm returned `## <path>:<lines> ( )` records. ⚠️ Through the installed skill only after push and reinstall.
- [x] "open the latest plan" with no file opens the newest plan in webrev — proof: `test_latest_plan` and `test_main_review_without_file_opens_latest_plan`; a hook case approves a bare `review`. Not run by hand.
- [ ] A review that outlasts the 10-minute cap still returns its notes, with no "done" from the user — proof: `test_wait_returns_submit_of_open_page` passes (status blocked again, submit returned). ⚠️ The manual timeout run is still to do.
- [x] In auto mode the hook approves webrev `review`, `wait` and `result` calls without a prompt — proof: new `tests/run.sh` cases allow both path forms, with and without `--title "…"`, and stay silent for `$`, `;`, `&&`, `render` and other scripts.
- [x] A review needs no permission prompt beyond the webrev call itself, and that call is hook-approved — proof: the skill's Launch section has no `mktemp` step; `test_review_default_backup`; manual runs printed `webrev: backup <tmp>/webrev/<page-id>.result`.
- [x] `overlay md` is gone and its hook case no longer approves — proof: `tests/run.sh` shows `overlay.sh md` exits 1 with the usage error, and both `md` forms are now silent hook cases.
- [ ] The backlog dashboard still opens — proof: `tests/run.sh` html cases pass. ⚠️ `/planning:backlog --dashboard` by hand after reinstall.
- [x] Upstream unit tests pass on the vendored script — proof: `tests/run.sh` runs the ported `tests/test_webrev.py` (34 tests) and it passes.
- [ ] ➕ README "Webrev Selection" key command (`cmd+shift+w`, free in agterm's defaults) opens the selected file in webrev without Claude. Submitted comments go to the clipboard, because no Claude session reads them. — proof: `/bin/sh -n` passes on the command body; it picks Python 3.14 on agterm's GUI `PATH`. ⚠️ A real key press after install is still to do; the one simulated run copied nothing, cause unknown.
- [x] ➕ The env vars set the page colors, and bad values fail — proof: `test_page_color`, `test_render_passes_colors`; the user's clean review with `#292827` / `#dbdbdb` set.
- [x] Every glow and `overlay md` reference is updated — proof: the grep shows only the "Glow Selection" key command plus the html-only `agterm:overlay` uses (backlog dashboard, README overlay row).
- [x] Document text renders at 16px, weight 500, line-height 1.4 in JetBrains Mono (1.5 looked too loose on the page) — proof: the user's clean webrev review of this plan.
- [ ] Document text is softer than the theme foreground and still follows the theme — proof: the user's clean review in the dark theme. ⚠️ A light theme is not checked yet.
- [ ] Headings, code, links, rail numbers and buttons stay legible after the change — proof: the dark theme passed the user's review. ⚠️ A light theme is not checked yet.

## Work order

1. Vendor the recipe, wire the hook and the tests, update references.
2. Then apply the visibility fixes to `assets/page.html`, so they diff cleanly against the upstream copy.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh` (341 passed)
- [x] linter passes: `bash -n` and `shellcheck` on changed scripts, `python3 -m py_compile plugins/agterm/scripts/webrev.py`
- [x] README.md updated: agterm section, planning flow, upstream credit
- [x] CHANGELOG.md: `agterm 2.0.0` and `planning 3.5.2` entries
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then `/plugin marketplace update parmaster-claude-dlc` and reinstall `agterm`.
- Delete the trial copy at `~/.claude/skills/webrev`, so two `webrev` skills don't compete.
