# Dummy Test Fixture Plan

**Goal:** Provide a small, real, harmless plan file under `docs/plans/` purely so the planning skills (`review-plan`, `handoff`, `spawn-session`, `pr`, ...) have something concrete to operate on while testing their mechanics — this is a throwaway fixture, not a real feature request. Its "feature" is intentionally trivial: add one small reference doc nobody depends on.

**Architecture:** Single new Markdown file, no code, no dependencies, nothing else touches it.

**Tech Stack:** Markdown only.

---

## Context (from discovery)
- files/components involved: none — net-new file, no existing code touched
- related patterns found: n/a
- dependencies identified: none

## Development Approach
- **testing approach**: Regular (code first, then tests) — moot here; there is no code, so "testing" is just confirming the file was created with the right content
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: update this plan file when scope changes during implementation**
- **CRITICAL: single summary commit at the end** — no per-task commits; one commit covers all implementation + plan move when complete

## Technical Details
- Creates `docs/testing/dummy-fixture-note.md`, a short note documenting that the file itself is a test fixture (so anyone who stumbles on it later understands why it exists and it's safe to delete).
- No version bump, no CHANGELOG entry, no plugin.json touch — this isn't a plugin change, it's a standalone doc.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Create the dummy fixture doc

**Files:**
- Create: `docs/testing/dummy-fixture-note.md`

- [ ] **Write the file**, with real content (not a placeholder):

```markdown
# Dummy Fixture Note

This file exists only to give the `planning` plugin's skills (`review-plan`,
`handoff`, `spawn-session`, `pr`, ...) something real to operate on while
testing their mechanics — spawning sessions, running review rounds, opening
PRs — without touching any actual plugin code.

Safe to delete once no longer needed for testing.
```

- [ ] **Verify the file exists with the expected content**

  Run: `cat docs/testing/dummy-fixture-note.md`
  Expected: the exact three-paragraph content above

### Task 2: Wrap up and commit

- [ ] Verify `docs/testing/dummy-fixture-note.md` exists and matches the content from Task 1
- [ ] No README.md or CLAUDE.md update needed — this is a standalone test fixture, not a documented feature
- [ ] Move this plan to `docs/plans/completed/` — use `mkdir -p docs/plans/completed && mv docs/plans/2026-09-15-dummy-test-fixture.md docs/plans/completed/` (plain `mv`, not `git mv`)
- [ ] Single summary commit: file creation + plan move in one commit

## Post-Completion
*Items requiring manual intervention or external systems*

- None — this plan exists purely to be run through the planning skills' machinery during testing. Discard the resulting file/commit afterward if it was only used for a dry run.
