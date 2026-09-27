# Comment hygiene hook

**Goal:** Stop code comments that point at tickets, links, plans or slices, with a hook for what grep can catch and a short rule for the rest.

**Kind of change:** feature (global-rules 1.8.2 → 1.9.0)

## Intent

planning 2.0.0 dropped the "Code comment rules" because plans no longer carry
code. The problem they fought is real: comments like `// PROJ-1234: see Slice B`
or `# per docs/plans/2026-09-01-foo.md` kept showing up. Comments are now
written only during implementation, so that's where the check belongs. It then
covers all code, not just code that came from a plan. Closes backlog item
`code-comment-rules-unenforced`.

## Decisions

- **Hook for the grep-able part, prose for judgment** (per this repo's
  "Harness Before Prose"). The hook can't judge "states the why"; the prose
  can't be enforced. Neither alone covers it.
- **PreToolUse on Edit, Write and MultiEdit, deny with a reason.** Deny, not
  ask: the fix is always "rewrite the comment", which the model can do without
  the user. The reason names the matched text and the rule.
- **Only lines being added are checked.** For Edit/MultiEdit: lines in
  `new_string` that aren't in `old_string`. For Write: lines not already in the
  file on disk. Otherwise one old bad comment blocks every edit near it.
- **Only comment lines in code files.** A line counts when, after leading
  whitespace, it starts with `//`, `#`, `/*`, `*` or `--`, and the file's
  extension is on a code allowlist (go, js/ts/jsx/tsx, py, sh/bash/zsh, rb,
  java, kt, rs, swift, c/h/cpp, sql, yaml/yml, toml, tf). Markdown, JSON and
  anything unlisted pass untouched: plans, CHANGELOGs and READMEs legitimately
  hold ticket IDs and links.
- **What's denied in such a line:**
  - ticket IDs `[A-Z]{2,}-[0-9]+`, except standard names (UTF-8, SHA-256,
    RFC-7231, AES-256, ISO-8601 and the like — carry over the old list)
  - links to Jira, Confluence, Atlassian, and GitHub/GitLab PR/MR URLs
  - `Slice <N|letter>` markers
  - pointers to a specific plan/spec doc: `docs/(plans|specs)/…\.md`
  - commit SHAs (see Traps for the shape)
- **Ticket IDs in `TODO(PROJ-123)` are denied too.** The old rule had no
  exception and one keeps the regex simple. Revisit if a repo requires them.
- **Prose rule:** a short "Code Comments" section in global-rules `CLAUDE.md`:
  a comment states the "why" a reader needs at that spot, 1–2 lines; never
  restates the code; never points at a plan, ticket, spec or slice — inline the
  one clause of context instead.

## Constraints / out of scope

- Existing comments in any repo aren't touched or reported.
- No config knobs or per-repo opt-out — add one only if a false positive shows up.
- NotebookEdit and Bash-written files aren't checked (Bash edits are already
  blocked by `block-inline-edit`).

## Traps

- A bare path mention isn't a pointer: `block-inline-edit.sh:10` has a
  legitimate comment about `docs/plans/` (the path the code handles). Only a
  path to a specific `.md` file counts.
- A naive SHA regex `[0-9a-f]{7,40}` matches plain numbers (`1234567`) and
  hex constants. Require both a digit and a letter a–f, and skip `0x`-prefixed
  values.
- `#` starts a comment in shell/Python/YAML but is a heading in Markdown,
  which is why the allowlist excludes `.md`.
- `tests/run.sh`'s `run_hook` helper builds a Bash tool payload
  (`.tool_input.command`). The new hook reads `.tool_input.file_path`,
  `.new_string`/`.old_string`, `.content`, `.edits[]`, so tests need a helper
  that builds those payloads.
- `hooks.json` currently has one PreToolUse entry with matcher `Bash`; this adds
  a second entry with its own matcher, not a new hook in the Bash list.

## Definition of Done

- [x] New comment lines with a ticket ID, Jira/Confluence/PR link, `Slice N`,
  plan/spec `.md` pointer or commit SHA are denied in a `.go`, `.py` and `.sh`
  file via Edit, Write and MultiEdit — proof: `tests/run.sh` cases, one per
  pattern plus one per tool.
- [x] No false positives on: UTF-8/SHA-256/RFC-7231 in comments, ticket IDs in
  strings (not comments), `1234567` and `0xdeadbeef`, the existing
  `docs/plans/` comment in `block-inline-edit.sh`, Markdown files, a bad comment
  already in `old_string` / on disk — proof: `tests/run.sh` allow cases.
- [x] Deny reason names the matched text and says to rewrite the comment —
  proof: a test asserts on the reason.
- [x] Hook registered for Edit, Write and MultiEdit — proof: read `hooks.json`;
  `/reload-plugins` then an Edit adding `// PROJ-1 fix` to a scratch `.go` file
  gets denied.
- [x] "Code Comments" prose section in global-rules `CLAUDE.md`, 3–4 lines.
- [x] README global-rules hook table lists the new hook.
- [x] global-rules at 1.9.0 with a CHANGELOG entry.
- [x] `docs/backlog/code-comment-rules-unenforced.md` deleted (it was never
  committed, so a plain `rm`, not `git rm`).

## Wrap-up

- [x] full test suite passes: `bash tests/run.sh`
- [x] resync with remote (`git fetch && git status`)
- [x] move this plan to `docs/plans/completed/`
- [x] single commit: all changes + plan move
