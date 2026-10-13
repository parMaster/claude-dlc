# Move block-inline-edit to strict-bash

**Goal:** Teammates get the inline-edit block by installing `strict-bash`, without installing `global-rules`.

**Kind of change:** refactor

## Intent

The `block-inline-edit` hook denies file edits through inline python/node/ruby scripts and `sed -i` / `perl -i`. It points Claude to the Edit tool, so the approval prompt shows a readable diff. Today the hook lives in `global-rules`. That plugin is a personal bundle: it imports personal CLAUDE.md rules and changes personal settings, so teammates won't install it. `strict-bash` is the plugin the team note already points to. Moving the hook there means one install gets teammates both Bash hooks.

```
before                                 after
global-rules                           global-rules
  PreToolUse Bash:                       PreToolUse Bash:
    block-root-find                        block-root-find
    block-coauthor                         block-coauthor
    block-inline-edit   ──────┐
strict-bash                   │        strict-bash
  PreToolUse Bash:            │          PreToolUse Bash:
    block-chained             │            block-chained
                              └──────►     block-inline-edit
```

## Decisions

- **The hook runs in every permission mode** — the hook keeps today's behavior. It does not copy `block-chained`'s early exit for `auto` / `bypassPermissions`. Edits stay as readable diffs even when nobody approves them live. Dropped: going silent in auto mode, because that would change behavior for the user's own machines.
- **strict-bash's pitch gets wider** — its description in `plugin.json`, `marketplace.json` and the README now says "auto mode off". It changes to cover both hooks: the plugin keeps Bash calls small and readable. The README should say the inline-edit hook is useful with auto mode on too. Today the README says "Install it only on the machines that need it". That sentence then applies only to the chained-command hook.
- **Script moves unchanged** — `git mv` the script, so its history follows it. Its deny message and regexes stay the same.
- **Versions** — `strict-bash` 1.1.1 → 1.2.0 (new component). `global-rules` 1.11.2 → 2.0.0, because a user who has only `global-rules` loses the hook. Two `CHANGELOG.md` entries, one per plugin. The `global-rules` entry says to install `strict-bash` to keep the hook.

## Constraints / out of scope

- No change to what the hook matches. Gaps in matching, such as `bash -c "sed -i ..."`, are tracked in `docs/backlog/inline-edit-misses-quoted-sed.md`. That item's `where` points at the old path. Update it to the new path as part of this move.
- `block-root-find`, `block-coauthor` and `block-comment-refs` stay in `global-rules`.
- `HACKING.md` is the user's draft. Don't touch it.

## Traps

- The `perl -i` exception matches any command that contains `docs/plans/`. That ties the hook to the `planning` plugin's checkbox one-liner. Keep the exception and its header comment as they are (`block-inline-edit.sh`, `PERL_I` check).
- `tests/run.sh` defines `run_hook` in the `global-rules/block-root-find.sh` section, near the top. The `strict-bash` sections reuse it. Place the moved test block next to `strict-bash/block-chained.sh`, below that definition. Don't move `run_hook` itself.
- `run_hook` sends input with no `permission_mode`. That is fine for this hook, because it ignores the mode. Don't add mode gating "for consistency" with `block-chained`.
- Both plugins' PreToolUse Bash hooks run on the same call. A chained command that also edits inline gets two deny reasons. That is harmless, and nothing needs to change for it.

## Definition of Done

- [x] The existing inline-edit test cases pass before the move, then pass unchanged against the new path — proof: `bash tests/run.sh`, with the section header and script path now under `strict-bash`.
- [x] `plugins/global-rules/scripts/block-inline-edit.sh` is gone, and `global-rules/hooks/hooks.json` no longer references it — proof: `grep -rn "block-inline-edit" plugins/global-rules` prints nothing.
- [x] `strict-bash/hooks/hooks.json` runs the script on PreToolUse Bash, next to `block-chained` — proof: read the file, and `jq . plugins/strict-bash/hooks/hooks.json` parses.
- [x] README: the hook row moves from the `global-rules` table to the `strict-bash` table. The `strict-bash` intro covers both hooks and says when each one helps — proof: read both sections.
- [x] `strict-bash` description is updated in `plugin.json` and `marketplace.json`, and the two match — proof: diff the two strings.
- [x] Versions are bumped (strict-bash 1.2.0, global-rules 2.0.0), with two `CHANGELOG.md` entries dated 2026-10-13 — proof: read `CHANGELOG.md` and both `plugin.json` files.

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] JSON files parse: `jq . <file>` on both `hooks.json`, both `plugin.json` and `marketplace.json`
- [x] README.md updated (covered in the DoD)
- [x] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed && mv <plan> docs/plans/completed/`)
- [x] single commit: all changes + plan move

## Post-Completion

- Push, then run `/plugin marketplace update parmaster-claude-dlc` and update both plugins on your machines. Until both plugins are updated, the hook is either missing or runs twice.
- The team note gives install steps for `strict-bash`: add the marketplace, install, then `claude --init-only` once.
