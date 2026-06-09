---
name: pr
description: Open a draft PR for the current feature. Composes title from ticket ID/type convention and generates description from the plan file. Activates on "open a PR", "create a draft PR", "open draft PR", or as the final step after plan implementation.
allowed-tools: Read, Bash, AskUserQuestion
---

# Draft PR Creation

Open a draft PR with a structured title and plan-based description.

## Step 1: Find the plan file

1. If `$ARGUMENTS` contains a path, use it
2. Otherwise check `docs/plans/completed/` — most recently modified `.md` file
3. Otherwise check `docs/plans/` — most recently modified `.md` file (excluding `completed/`)

Read the plan file. Extract the **Goal** line and task list for use in the description.

## Step 2: Detect ticket ID from branch

Run: `git branch --show-current`

If the branch name contains a pattern like `BP-1234`, `PROJ-42`, or similar (`[A-Z]+-[0-9]+`), extract it as the candidate ticket ID.

## Step 3: Ask for PR details — one question at a time

**Question 1 — PR type:**

```json
{
  "questions": [{
    "question": "What type of change is this?",
    "header": "PR type",
    "options": [
      {"label": "feat", "description": "New feature or capability"},
      {"label": "fix", "description": "Bug fix"},
      {"label": "chore", "description": "Maintenance, refactor, tooling, docs"}
    ],
    "multiSelect": false
  }]
}
```

**Question 2 — Ticket ID:**

If a ticket ID was detected from the branch, offer it as the first option:

```json
{
  "questions": [{
    "question": "Ticket or epic ID?",
    "header": "Ticket ID",
    "options": [
      {"label": "BP-1234", "description": "Detected from branch name"},
      {"label": "No ticket", "description": "Not linked to a ticket"}
    ],
    "multiSelect": false
  }]
}
```

If no ID was detected, offer:

```json
{
  "questions": [{
    "question": "Ticket or epic ID?",
    "header": "Ticket ID",
    "options": [
      {"label": "No ticket", "description": "Not linked to a ticket"},
      {"label": "Enter ID", "description": "Type the ticket ID (e.g. BP-1234)"}
    ],
    "multiSelect": false
  }]
}
```

(User types their ID via the "Other" input if neither option fits)

**Question 3 — Ticket title:**

Suggest the title from the plan's **Goal** line (strip the "Goal:" prefix). Let the user override via "Other":

```json
{
  "questions": [{
    "question": "PR title (the part after the ticket ID)?",
    "header": "Title",
    "options": [
      {"label": "<goal from plan>", "description": "Use the plan goal as the title"},
      {"label": "Enter title", "description": "Type a different title"}
    ],
    "multiSelect": false
  }]
}
```

## Step 4: Compose the PR title

Format: `[type]: TICKET-ID - ticket title`

- With ticket: `[feat]: BP-1234 - Add user authentication`
- Without ticket: `[feat]: Add user authentication`

## Step 5: Generate PR description

From the plan file, write a description following writing-style principles — direct, brief, no AI-speak:

```markdown
## What

[1-2 sentences from the plan Goal — what was built and why. Start directly, no "This PR implements..."]

## Changes

[bullet list of key changes, summarized from the plan's task list — meaningful level, not every checkbox]
- `path/to/file` — what changed and why
- ...

## Testing

[how to test — from the plan's verify task and testing approach. Include exact commands.]
```

Rules:
- No "This PR...", "This change...", "This commit..." — start sentences directly
- No "comprehensive", "robust", "leverage", "utilize" — use plain words
- No "In order to" — just "To"
- Include exact file paths or function names where they add context
- Bullet points for changes, not prose

## Step 6: Create the PR

```bash
gh pr create --draft --title "[type]: TICKET-ID - title" --body "$(cat <<'EOF'
[generated description]
EOF
)"
```

Output the PR URL to the user after creation.
