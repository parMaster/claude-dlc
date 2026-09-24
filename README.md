# claude-dlc

Personal Claude Code plugins and skills.

## Install

```
/plugin marketplace add parmaster/claude-dlc
/plugin install <plugin-name>@parmaster-claude-dlc
```

### Updating

Installed plugins stay pinned to their version. To pick up a newer one:

```
/plugin marketplace update parmaster-claude-dlc    # refresh the catalog first
/plugin install <plugin-name>@parmaster-claude-dlc # re-running install is the upgrade
/reload-plugins
```

Skip the `marketplace update` step and `install` just says "already installed". To automate this, enable auto-update under `/plugin` → **Marketplaces** → `parmaster-claude-dlc`.

## Planning workflow

Every step is optional, drop in at any point:

```mermaid
flowchart TD
    OV(["planning:oversight"])
    BS(["brainstorm"])
    PL(["planning:plan"])
    RP(["planning:review-plan"])
    RD(["revdiff:revdiff"])
    IM["implement"]
    DPR(["planning:pr"])

    OV -.->|optional, multi-plan epics| PL
    BS -.->|optional warmup| PL
    PL -.->|optional| RP
    PL -.->|optional| RD
    PL --> IM
    RP --> IM
    RD --> IM
    IM --> DPR
```

## Plugins

### statusline

Custom status line (robbyrussell-style).

#### Claude Code

```
/plugin install statusline@parmaster-claude-dlc
```

Shows: current dir, git branch + dirty state (`✗`), model name, context %, 5h/7d usage rates with reset time.

After install, run `claude --init-only` once to trigger the setup hook — it writes `statusLine` into `~/.claude/settings.json`. Then relaunch Claude normally.

#### Codex

Codex uses its native footer renderer. From this repository, run:

```bash
bash plugins/statusline/scripts/setup-codex.sh
```

Restart Codex after setup. The footer shows the current directory, Git branch, model and reasoning effort, context use, five-hour use, and weekly use. Codex controls the colors and labels; its native footer does not expose the Claude line's prompt symbol, dirty-tree marker, custom context color, or reset time.

---

### planning

Plans, plan reviews, PRs, and hand-offs to fresh sessions.

```
/plugin install planning@parmaster-claude-dlc
```

| Skill | What it does |
|-------|--------------|
| `oversight` | Scopes a multi-plan epic: groups tickets into iterations, checks each against INVEST, sets an epic-level Definition of Done. Tracks progress in `docs/plans/wbs-<epic>.md` and can spawn a session per iteration. Meant to be revisited over the epic's lifetime. |
| `plan` | Writes `docs/plans/YYYYMMDD-<name>.md`: gathers context, explores approaches, self-reviews. Stops after writing the file. |
| `review-plan` | Critiques a plan (correctness, over-engineering, test coverage) in up to 3 rounds via a read-only `plan-review` subagent. Findings are ranked Critical/Important/Minor. Can hand the review off to a Codex session. |
| `pr` | Opens a draft PR from the plan file, or amends the description if a PR already exists. |
| `handoff` | Sends a plan to a fresh [agterm](https://github.com/umputun/agterm) session on Claude or Codex. Explicit-only: `/planning:handoff [plan-file]`. |
| `spawn-session` | Sends an arbitrary task to a fresh [agterm](https://github.com/umputun/agterm) session. Also triggers from natural language ("spawn a new session for this"). |

Hand-off sessions are flagged (`agtermctl session flag on`) so in-flight work shows up in [agterm](https://github.com/umputun/agterm)'s flagged view.

**Tip:** to keep a long-lived `oversight` session's prompt cache warm between check-ins, run `/loop 50m keepalive ping — no action, one-word ack` in it.

---

### brainstorm

Collaborative design dialogue before implementation.

```
/plugin install brainstorm@parmaster-claude-dlc
```

| Skill | What it does |
|-------|--------------|
| `brainstorm` | Turns ideas into designs through one-at-a-time questions and incremental validation. |

---

### style

Writing style for technical communication.

```
/plugin install style@parmaster-claude-dlc
```

| Skill | What it does |
|-------|--------------|
| `writing-style` | Direct, brief style for PRs, tickets, issue comments, and commit messages. No AI-speak. |

---

### git-tools

```
/plugin install git-tools@parmaster-claude-dlc
```

| Skill | What it does |
|-------|--------------|
| `squash-rebase` | Rebases onto main after a parent branch was squash-merged. Finds the cut point, shows what gets dropped vs replayed, and asks before running `git rebase --onto`. |

---

### statusline

Custom status line: dir, git branch and dirty state, model, context %, 5h/7d usage.

```
/plugin install statusline@parmaster-claude-dlc
```

Run `claude --init-only` once after install to write `statusLine` into `~/.claude/settings.json`, then relaunch.

---

### global-rules

Shared global `CLAUDE.md` rules, synced across machines.

```
/plugin install global-rules@parmaster-claude-dlc
```

Run `claude --init-only` once after install. The setup hook is additive and idempotent, and never overrides values you've set. It:

- adds an `@import` line to `~/.claude/CLAUDE.md` pointing at the plugin's rules
- sets `CLAUDE_AFK_TIMEOUT_MS` to 24h so `AskUserQuestion` dialogs don't auto-submit after 60s
- denies `ScheduleWakeup` (a bare `/loop` with no interval then runs once; `/loop <interval>` still works)
- sets `bashOutputMaxChars: 4000` so large Bash output is saved to a file and previewed instead of flooding context

The rules cover plan-first workflow, git hygiene, tests and lint before commit, response brevity, and memory and Atlassian MCP discipline.

| Hook | Effect |
|------|--------|
| `block-root-find` | Denies `find` rooted at `/`. Scope the search to a directory. |
| `block-coauthor` | Denies `git commit` / `gh pr create` / `gh pr edit` with a `Co-Authored-By` line or a claude.ai session link (`Claude-Session:` trailer). |

---

## Local development

```
claude --plugin-dir plugins/<name>   # load a plugin straight from the working tree
/reload-plugins                      # pick up edits without restarting
```

To test the marketplace catalog itself, edit `.claude-plugin/marketplace.json` and re-run `/plugin marketplace add parmaster/claude-dlc`.
