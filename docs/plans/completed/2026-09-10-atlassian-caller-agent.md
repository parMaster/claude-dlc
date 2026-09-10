# Atlassian caller agent — stop the Jira/Confluence subagent from recursing

**Goal:** Replace the generic "delegate to an Agent-tool subagent" instruction in the Atlassian MCP Hygiene rule with a dedicated `atlassian-caller` subagent that has no Agent tool in its toolset, so it cannot spawn a nested subagent no matter how it reasons about the task.

**Architecture:** One new agent definition file (`plugins/global-rules/agents/atlassian-caller.md`) plus a rewrite of the two affected lines in `plugins/global-rules/CLAUDE.md`. Version bump + changelog entry + README blurb update in the same commit, per repo convention.

**Tech Stack:** Claude Code plugin authoring (agent frontmatter, CLAUDE.md prose, plugin.json/CHANGELOG conventions) — no application code.

---

## Context (from discovery)

- Current rule (`plugins/global-rules/CLAUDE.md`, "Atlassian MCP Hygiene" section, added in the completed plan `docs/plans/completed/2026-09-03-atlassian-mcp-hygiene-rule.md` and tightened since): tells the calling agent to delegate every Jira MCP call to a generic Agent-tool subagent, with a prose instruction — "if you are that subagent, make the calls yourself instead of re-delegating" — telling that subagent not to delegate further.
- Observed failure: a Jira subagent broke its own delegated goal into sub-steps and spawned a second nested subagent for one of them, three levels deep in one case. The generic subagent type has every tool, including Agent, so nothing structurally stops this — the rule depends on each nested agent correctly recognizing "I am already the subagent this applies to," and that reasoning isn't reliable.
- `plugins/global-rules/.claude-plugin/plugin.json` is at `1.5.1`.
- Sibling agent `plugins/planning/agents/plan-review.md` is this repo's only existing custom-agent example: frontmatter is `name`, `description`, `tools` (comma-separated exact tool names) — no `model` field, so it inherits the session model.
- This repo's own root `CLAUDE.md` already states the fix pattern: "Use this [agents/<name>.md's tools: list] — not a prompt-only ... instruction inside a skill — whenever a spawned agent must actually be prevented from writing/editing/deleting: the tools: list is enforced at the tool-permission layer, so [a tool] simply isn't callable if omitted from it." Same mechanism applies to the Agent tool.
- The 39 Atlassian MCP tools available in this environment (server `plugin_atlassian_atlassian`, a separate installed plugin — not part of this repo, so this list is only as stable as that plugin's own tool surface): `addCommentToJiraIssue`, `addTeamworkGraphContext`, `addWorklogToJiraIssue`, `atlassianUserInfo`, `createCompassComponent`, `createCompassComponentRelationship`, `createCompassCustomFieldDefinition`, `createConfluenceFooterComment`, `createConfluenceInlineComment`, `createConfluencePage`, `createIssueLink`, `createJiraIssue`, `editJiraIssue`, `fetch`, `getAccessibleAtlassianResources`, `getCompassComponent`, `getCompassComponents`, `getCompassCustomFieldDefinitions`, `getConfluenceCommentChildren`, `getConfluencePage`, `getConfluencePageDescendants`, `getConfluencePageFooterComments`, `getConfluencePageInlineComments`, `getConfluenceSpaces`, `getContentFormatGuide`, `getIssueLinkTypes`, `getJiraIssue`, `getJiraIssueRemoteIssueLinks`, `getJiraIssueTypeMetaWithFields`, `getJiraProjectIssueTypesMetadata`, `getPagesInConfluenceSpace`, `getTeamworkGraphContext`, `getTeamworkGraphObject`, `getTransitionsForJiraIssue`, `getVisibleJiraProjects`, `lookupJiraAccountId`, `search`, `searchConfluenceUsingCql`, `transitionJiraIssue`, `updateConfluencePage`.
- The rule's section title is "Atlassian MCP Hygiene" (not "Jira MCP Hygiene") and the completed 2026-09-03 plan already covers both Jira and Confluence bloat sources — the new agent's tool list covers the full Atlassian surface above, not just Jira, so ad hoc Confluence requests ("add a comment to that page") are covered by the same rule instead of falling back to an unrestricted subagent.
- No conflicting recorded decision: the 2026-09-03 plan rejected a `PreToolUse` hook for the *field-scoping* rule specifically (too narrow against ~40 tools, would give false confidence on only 2 of them). This plan doesn't add a hook — it adds an agent `tools:` allowlist, a different mechanism that covers the whole tool surface by construction. No contradiction.
- `tests/run.sh` (run via `bash tests/run.sh`, wired into `.github/workflows/test.yml`) covers only the shell scripts under `plugins/*/scripts/` — it doesn't touch CLAUDE.md, agent files, or plugin.json content, so this change adds no new coverage there and must not break existing PASS lines.
- CHANGELOG.md format: `## <plugin> X.Y.Z - YYYY-MM-DD` heading, then a prose paragraph — no subheadings (dropped after global-rules v1.1.4).

## Verified Dependency Behaviors

- Claude Code sub-agent `tools:` frontmatter field (docs: `code.claude.com/docs/en/sub-agents.md`, confirmed live via a documentation check in this session): specifying `tools:` switches the agent to an explicit allowlist — anything not named is unavailable to it. This is the same behavior this repo's own `CLAUDE.md` already asserts for `Write`/`Edit`/`NotebookEdit`; it applies identically to `Agent`, so omitting `Agent` from `atlassian-caller`'s `tools:` list makes it structurally unable to spawn a subagent.
- Wildcard patterns (`mcp__<server>__*`) are documented only for `disallowedTools`, not for the `tools:` allowlist. There is no confirmed way to allow "every tool from one MCP server" with a single pattern in `tools:` — each MCP tool must be listed by its exact full name. This plan lists all 39 Atlassian MCP tools individually rather than guessing at wildcard support.
- `disallowedTools: Agent` is added alongside the `tools:` omission as an explicit, auditable backstop — belt-and-suspenders given the `tools:`-allowlist behavior for the `Agent` tool specifically isn't spelled out verbatim in the docs (only implied by the general allowlist model).

## Development Approach
- **testing approach**: Regular — this is prompt/config authoring (CLAUDE.md prose, agent frontmatter, JSON), not executable code, so there's no unit-test layer. Verification is grep/jq checks against the edited files, `bash tests/run.sh` as a regression check, and a local plugin load (`claude --plugin-dir plugins/global-rules`) to confirm the agent file parses.
- complete each task fully before moving to the next
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all implementation + plan move when complete
- **CRITICAL: no ticket keys, project names, or org names in any file this plan touches** — this is a public repo (established convention from prior work in this repo); write the CLAUDE.md rule, agent file, and changelog entry generically (e.g. "a Jira issue", not a real ticket key)

## Technical Details

### File: `plugins/global-rules/agents/atlassian-caller.md` (create)

Full file content:

```markdown
---
name: atlassian-caller
description: Executes one delegated Atlassian (Jira/Confluence) goal end-to-end via direct MCP tool calls — reads, writes, comments, and transitions. Spawned by the "Atlassian MCP Hygiene" rule in this plugin's CLAUDE.md; not for direct use. Has no Agent tool, so it cannot spawn further subagents.
model: haiku
tools: mcp__plugin_atlassian_atlassian__addCommentToJiraIssue, mcp__plugin_atlassian_atlassian__addTeamworkGraphContext, mcp__plugin_atlassian_atlassian__addWorklogToJiraIssue, mcp__plugin_atlassian_atlassian__atlassianUserInfo, mcp__plugin_atlassian_atlassian__createCompassComponent, mcp__plugin_atlassian_atlassian__createCompassComponentRelationship, mcp__plugin_atlassian_atlassian__createCompassCustomFieldDefinition, mcp__plugin_atlassian_atlassian__createConfluenceFooterComment, mcp__plugin_atlassian_atlassian__createConfluenceInlineComment, mcp__plugin_atlassian_atlassian__createConfluencePage, mcp__plugin_atlassian_atlassian__createIssueLink, mcp__plugin_atlassian_atlassian__createJiraIssue, mcp__plugin_atlassian_atlassian__editJiraIssue, mcp__plugin_atlassian_atlassian__fetch, mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources, mcp__plugin_atlassian_atlassian__getCompassComponent, mcp__plugin_atlassian_atlassian__getCompassComponents, mcp__plugin_atlassian_atlassian__getCompassCustomFieldDefinitions, mcp__plugin_atlassian_atlassian__getConfluenceCommentChildren, mcp__plugin_atlassian_atlassian__getConfluencePage, mcp__plugin_atlassian_atlassian__getConfluencePageDescendants, mcp__plugin_atlassian_atlassian__getConfluencePageFooterComments, mcp__plugin_atlassian_atlassian__getConfluencePageInlineComments, mcp__plugin_atlassian_atlassian__getConfluenceSpaces, mcp__plugin_atlassian_atlassian__getContentFormatGuide, mcp__plugin_atlassian_atlassian__getIssueLinkTypes, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__getJiraIssueRemoteIssueLinks, mcp__plugin_atlassian_atlassian__getJiraIssueTypeMetaWithFields, mcp__plugin_atlassian_atlassian__getJiraProjectIssueTypesMetadata, mcp__plugin_atlassian_atlassian__getPagesInConfluenceSpace, mcp__plugin_atlassian_atlassian__getTeamworkGraphContext, mcp__plugin_atlassian_atlassian__getTeamworkGraphObject, mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue, mcp__plugin_atlassian_atlassian__getVisibleJiraProjects, mcp__plugin_atlassian_atlassian__lookupJiraAccountId, mcp__plugin_atlassian_atlassian__search, mcp__plugin_atlassian_atlassian__searchConfluenceUsingCql, mcp__plugin_atlassian_atlassian__transitionJiraIssue, mcp__plugin_atlassian_atlassian__updateConfluencePage
disallowedTools: Agent
---

You are executing one delegated Atlassian goal end-to-end via direct Jira/Confluence MCP tool calls. You were spawned because the calling agent's "Atlassian MCP Hygiene" rule routes all Atlassian MCP work through you instead of calling the tools directly. You have no Agent tool available — re-delegating isn't something you can do, so make every call yourself, however many steps the goal takes.

The invoking prompt states the end result needed (e.g. "confirm the issue is Done, transitioning it if it isn't"). Work the goal to completion, then report back a short result summary — never the raw JSON from an individual call.

Field hygiene on every Jira read:
- Pass an explicit `fields` array scoped to only what the goal needs (e.g. `["status"]` for a status check). Never rely on the default field set — it includes `assignee`, `reporter`, and `project`, each a nested object full of avatar URLs and self-links. Use `fields: ["*all"]` only when the goal explicitly calls for full fidelity.
- Pass `responseContentFormat: "markdown"` — it returns simplified plain text instead of full ADF JSON.

Report format: a few plain sentences stating what you found and what you changed (e.g. "The issue was In Progress; transitioned it through Done and added a closing comment."). Do not paste raw tool output back to the caller.
```

### File: `plugins/global-rules/CLAUDE.md` (modify)

Replace the "Atlassian MCP Hygiene" section's first bullet (the rest of the section is unchanged):

Old:
```markdown
## Atlassian MCP Hygiene
- **Delegate the goal, once** — every Jira MCP call goes through an Agent-tool subagent, even a lone `getJiraIssue`. Ask for an end result ("complete TASK-123": read status, walk the transitions, verify) and use only its report. One subagent per goal, never one per call — and if you are that subagent, make the calls yourself instead of re-delegating.
- **Scope the fields** — pass an explicit `fields` array (`["status"]`, `["description"]`) and `responseContentFormat: "markdown"`. The default set drags in `assignee`, `reporter` and `project` as nested objects full of avatar URLs; use `["*all"]` only when asked for full fidelity.
```

New:
```markdown
## Atlassian MCP Hygiene
- **Delegate the goal, once, to `atlassian-caller`** — every Atlassian MCP call (Jira or Confluence) goes through the `atlassian-caller` subagent (Agent tool, `subagent_type: atlassian-caller`), even a lone `getJiraIssue`. Ask for an end result ("confirm the issue is Done, transitioning it if it isn't": read status, walk the transitions, verify) and use only its report. One `atlassian-caller` spawn per goal, never one per call — it has no Agent tool in its own toolset, so it cannot re-delegate even if it tries.
- **Scope the fields** — pass an explicit `fields` array (`["status"]`, `["description"]`) and `responseContentFormat: "markdown"`. The default set drags in `assignee`, `reporter` and `project` as nested objects full of avatar URLs; use `["*all"]` only when asked for full fidelity.
```

### File: `plugins/global-rules/.claude-plugin/plugin.json` (modify)

Bump `"version"` from `"1.5.1"` to `"1.6.0"` (minor — new bundled agent file, per repo convention: "Bump on *any* change to bundled content ... not just plugin.json").

### File: `CHANGELOG.md` (modify)

Insert a new entry at the top of the entries list (immediately before the current first entry, `## global-rules 1.5.1 - 2026-09-10`):

```markdown
## global-rules 1.6.0 - 2026-09-10

Adds a dedicated `atlassian-caller` subagent (Haiku, 39 Atlassian MCP tools,
no Agent tool) and points the Atlassian MCP Hygiene rule at it by name
instead of a generic Agent-tool subagent. Observed live: a Jira subagent
broke its own delegated goal into sub-steps and spawned a second nested
subagent for one of them — the generic subagent type has every tool,
including Agent, so the rule's "don't re-delegate" instruction depended on
each nested agent correctly recognizing it already was that subagent, and
that reasoning isn't reliable. `atlassian-caller`'s `tools:` allowlist
omits Agent entirely (plus `disallowedTools: Agent` as an explicit
backstop), so it's structurally unable to spawn a child regardless of how
it reasons about the task.

```

### File: `README.md` (modify)

In the `global-rules` section's feature list (the line starting "Includes: plan-first workflow..."), update the Atlassian MCP hygiene clause from:

```
Atlassian MCP hygiene (delegate all Jira MCP work to a subagent — one per goal, not per call — and scope the requested fields).
```

to:

```
Atlassian MCP hygiene (delegate all Jira/Confluence MCP work to a dedicated `atlassian-caller` subagent that has no Agent tool of its own — one spawn per goal, not per call — and scope the requested fields).
```

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Create the `atlassian-caller` agent

**Files:**
- Create: `plugins/global-rules/agents/atlassian-caller.md`

- [ ] Write the file exactly as shown in Technical Details above
- [ ] Confirm the frontmatter's `tools:` list has exactly 39 entries, one per tool name listed in Context above, each prefixed `mcp__plugin_atlassian_atlassian__` — count them: `grep -o 'mcp__plugin_atlassian_atlassian__[A-Za-z]*' plugins/global-rules/agents/atlassian-caller.md | sort -u | wc -l` should print `39`
- [ ] Confirm `Agent` does not appear anywhere in the `tools:` value: `grep -A2 '^tools:' plugins/global-rules/agents/atlassian-caller.md | grep -w 'Agent'` should print nothing
- [ ] Confirm the `disallowedTools: Agent` line is present: `grep -x 'disallowedTools: Agent' plugins/global-rules/agents/atlassian-caller.md`

### Task 2: Rewrite the CLAUDE.md rule, bump version, update changelog and README

**Files:**
- Modify: `plugins/global-rules/CLAUDE.md`
- Modify: `plugins/global-rules/.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] Replace the "Atlassian MCP Hygiene" section's first bullet in `plugins/global-rules/CLAUDE.md` with the new bullet shown above; leave the "Scope the fields" bullet and every other section untouched
- [ ] Bump `plugins/global-rules/.claude-plugin/plugin.json` version to `1.6.0`
- [ ] Insert the changelog entry shown above at the top of `CHANGELOG.md`'s entry list, immediately before `## global-rules 1.5.1 - 2026-09-10`
- [ ] Update the `README.md` global-rules feature-list clause as shown above
- [ ] Read back all four files to confirm the edits landed correctly and no other content was disturbed

### Task 3: Verify acceptance criteria
- [ ] Confirm the old phrase is gone: `grep -n 'and if you are that subagent' plugins/global-rules/CLAUDE.md` — expect no output
- [ ] Confirm the new rule references the named agent: `grep -n 'atlassian-caller' plugins/global-rules/CLAUDE.md` — expect at least one match
- [ ] Confirm `plugin.json` is valid JSON and shows the new version: `jq -r .version plugins/global-rules/.claude-plugin/plugin.json` — expect `1.6.0`
- [ ] Run the repo's test suite: `bash tests/run.sh` — expect all existing PASS lines unchanged (this change touches no script the suite covers, so this is a regression check, not new coverage)
- [ ] Load the plugin locally and confirm the agent is recognized with no parse errors: `claude --plugin-dir plugins/global-rules` — check that no startup warning is printed about `agents/atlassian-caller.md`
- [ ] Grep the whole diff for ticket keys / org or project names before committing: `git diff --cached | grep -inE '[A-Z]{2,}-[0-9]+'` — expect no output (public-repo hygiene)

### Task 4: Wrap up and commit
- [ ] Move this plan to `docs/plans/completed/`: `mkdir -p docs/plans/completed && mv docs/plans/2026-09-10-atlassian-caller-agent.md docs/plans/completed/`
- [ ] Single summary commit: agent file + CLAUDE.md + plugin.json + CHANGELOG.md + README.md + plan move, one commit
- [ ] Open draft PR — invoke `planning:pr`

## Post-Completion
*Known limitation, not a follow-up task*: the `atlassian-caller` tools list is coupled to the current Atlassian MCP plugin's exact tool names (a separately installed plugin, not owned by this repo). If that plugin adds, removes, or renames tools, this agent's `tools:` list needs a matching manual update — there's no confirmed wildcard syntax in `tools:` to make it self-adjusting.
