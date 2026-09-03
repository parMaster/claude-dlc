# Atlassian MCP hygiene rule

**Goal:** Add a CLAUDE.md rule to the `global-rules` plugin instructing scoped `fields` + `responseContentFormat: "markdown"` on Atlassian Jira MCP calls, so a simple status/description lookup doesn't pull hundreds of KB of nested user/project JSON (avatar URLs, self-links) into the session.

**Architecture:** Pure content addition — one new `##` section in `plugins/global-rules/CLAUDE.md`, no scripts/hooks. Version bump + changelog entry in the same commit, per repo convention.

---

## Context (from discovery)

- `plugins/global-rules/CLAUDE.md` is the file synced into every project via `@`-include from `~/.claude/CLAUDE.md` — confirmed this is the live source, not a generated copy.
- `plugins/global-rules/.claude-plugin/plugin.json` is at `1.1.5`.
- `mcp__plugin_atlassian_atlassian__getJiraIssue` and `...__searchJiraIssuesUsingJql` both accept:
  - `fields` (array): "Issue fields to return. When omitted or empty, defaults to: summary, description, status, issuetype, priority, labels, components, assignee, reporter, created, updated, resolution, project. Pass `\"*all\"` to return every field."
  - `responseContentFormat` (`"markdown"` | `"adf"`): markdown is "simplified plain text"; ADF is full JSON.
- The default field set already includes `assignee`, `reporter`, `project` — each a nested Jira object carrying avatar URLs (multiple sizes), `self` links, `accountId`, etc. that can't be trimmed once the object is included. That's the actual source of the bloat the owner observed, not just format choice.
- Decided with owner: CLAUDE.md rule only. A `PreToolUse` hook enforcing this (matching the block-root-find.sh precedent in this same plugin) was considered and explicitly rejected — it would allowlist only these two tool names out of ~40 Atlassian MCP tools, giving false confidence while missing other bloat sources (e.g. `getConfluencePage`, `search`). No hook in this pass.
- Existing `atlassian:*` skills (capture-tasks-from-meeting-notes, generate-status-report, etc.) come from a separate plugin/marketplace not present in this repo's `plugins/` — out of scope, can't be edited here.
- CHANGELOG.md format for this plugin (from existing entries): `## global-rules X.Y.Z - YYYY-MM-DD` heading, then a short prose paragraph (no `### Fixes`/`### Improvements` subheadings in the most recent entries — that style was dropped after v1.1.4).

## Development Approach
- **testing approach**: N/A — pure prose/content change, no executable behavior to test. `tests/run.sh` covers hook scripts only; this change touches none.
- **CRITICAL: single summary commit at the end** — one commit covers the CLAUDE.md edit + version bump + changelog entry + plan move.
- **CRITICAL: update this plan file when scope changes during implementation**

## Solution Overview

Add one new section to `plugins/global-rules/CLAUDE.md`, placed after "Honesty About Uncertainty" and before "Go codebases" (keeps the file's existing order of: workflow → git → verification → honesty → language-specific → memory → style → CLI). Two bullets:

1. **Enforceable now, no infra needed**: always pass explicit minimal `fields` + `responseContentFormat: "markdown"`.
2. **Documented pattern, not enforced**: multi-step/compound Jira work goes through a subagent so raw output never lands in the main session.

## Technical Details

### File: `plugins/global-rules/CLAUDE.md` (modify)

Insert after line 20 (end of "## Honesty About Uncertainty" section, before "## Go codebases"):

```markdown

## Atlassian MCP Hygiene
- **Scope Jira field requests** — Atlassian Jira MCP calls (`getJiraIssue`, `searchJiraIssuesUsingJql`, and similar) default to returning `summary, description, status, issuetype, priority, labels, components, assignee, reporter, created, updated, resolution, project` — several of those (`assignee`, `reporter`, `project`) are nested objects carrying avatar URLs and self-links that bloat the session even for a two-line lookup. Always pass an explicit `fields` array scoped to only what's needed (e.g. `["status"]` for a status check, `["description"]` for a description) — never rely on the default set, and never pass `fields: ["*all"]` unless the user explicitly asked for full fidelity. Also pass `responseContentFormat: "markdown"` — it returns simplified plain text instead of full ADF JSON.
- **Delegate compound Jira work to a subagent** — for anything needing several Jira MCP calls to produce one small answer (e.g. transition status + add comment + list subtasks, or bulk JQL search across many issues), dispatch a subagent via the Agent tool with a description of the end result needed, and use only its distilled report. This keeps the raw multi-call JSON out of the main session context; a single well-scoped call (per the rule above) doesn't need this.
```

### File: `plugins/global-rules/.claude-plugin/plugin.json` (modify)

Bump `"version"` from `"1.1.5"` to `"1.2.0"` (minor — new guidance content, per repo convention: "Bump on *any* change to bundled content ... not just plugin.json").

### File: `CHANGELOG.md` (modify)

Insert a new entry at the top of the entries list (immediately after the intro lines, before the current first entry `## planning 1.14.0 - 2026-08-31`):

```markdown
## global-rules 1.2.0 - 2026-09-03

Added "Atlassian MCP Hygiene" rule: scope Jira MCP calls (`getJiraIssue`,
`searchJiraIssuesUsingJql`) with an explicit minimal `fields` array and
`responseContentFormat: "markdown"` instead of relying on the default
field set, which pulls in nested `assignee`/`reporter`/`project` objects
full of avatar URLs and self-links even for a one-line status check.
Also documents delegating multi-step Jira work (status transition +
comment + subtask listing, bulk JQL) to a subagent so raw multi-call
output stays out of the main session. Considered and rejected a
`PreToolUse` hook enforcing this on the same two tool names — too narrow
against the ~40-tool Atlassian MCP surface, would give false confidence.

```

## Progress Tracking
- mark completed items with `[x]` immediately when done

## Implementation Steps

### Task 1: Add the CLAUDE.md rule, bump version, update changelog

**Files:**
- Modify: `plugins/global-rules/CLAUDE.md`
- Modify: `plugins/global-rules/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

- [ ] Insert the "Atlassian MCP Hygiene" section shown above into `plugins/global-rules/CLAUDE.md`, between "## Honesty About Uncertainty" and "## Go codebases"
- [ ] Bump `plugins/global-rules/.claude-plugin/plugin.json` version to `1.2.0`
- [ ] Insert the changelog entry shown above at the top of `CHANGELOG.md`'s entry list
- [ ] Read back all three files to confirm the edits landed correctly and no other content was disturbed

### Task 2: Verify acceptance criteria
- [ ] Confirm `plugins/global-rules/CLAUDE.md` reads correctly end-to-end (no broken heading nesting, no duplicated section)
- [ ] Confirm `plugin.json` is valid JSON: `python3 -m json.tool plugins/global-rules/.claude-plugin/plugin.json >/dev/null`
- [ ] Run the repo's test suite: `bash tests/run.sh` — expect all existing PASS lines unchanged (this change touches no script the suite covers, so this is a regression check, not new coverage)

### Task 3: Wrap up and commit
- [ ] README.md — check whether it documents global-rules' CLAUDE.md sections; update only if it enumerates them (skip if it just says "shared CLAUDE.md rules" at a high level)
- [ ] Move this plan to `docs/plans/completed/`: `mkdir -p docs/plans/completed && mv docs/plans/2026-09-03-atlassian-mcp-hygiene-rule.md docs/plans/completed/`
- [ ] Single summary commit: CLAUDE.md + plugin.json + CHANGELOG.md + plan move, one commit
- [ ] Open draft PR — invoke `planning:pr`

## Post-Completion
*None — this is a self-contained doc change with no external follow-up.*
