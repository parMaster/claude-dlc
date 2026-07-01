# claude-dlc

Personal Claude Code plugins and skills.

## Install

```
/plugin marketplace add parmaster/claude-dlc
```

Then install individual plugins:

```
/plugin install <plugin-name>@parmaster-claude-dlc
```

### Updating a plugin

Installed plugins stay pinned to their version. A session restart or `/reload-plugins` reloads the *currently pinned* version — neither pulls a newer one. To upgrade to a version you've pushed:

```
/plugin marketplace update parmaster-claude-dlc    # refresh the catalog so it sees the new version
/plugin install <plugin-name>@parmaster-claude-dlc # upgrades in place to the latest
/reload-plugins                                     # apply in the current session
```

The `marketplace update` step is the one that's easy to miss: without it, `/plugin install` reports "already installed" and no-ops, because the catalog still thinks your installed version is the latest. There's no separate `/plugin update` command — re-running `install` *is* the upgrade, once the catalog is refreshed. `/reload-plugins` prints a hook/skill/agent count, handy for confirming new components loaded (e.g. an added hook bumps the count).

To skip the manual steps, enable auto-update for the marketplace (off by default for third-party marketplaces): `/plugin` → **Marketplaces** → select `parmaster-claude-dlc` → **Enable auto-update**, or set `"autoUpdate": true` on the marketplace entry in `~/.claude/settings.json`. Claude then refreshes and upgrades at startup and prompts you to `/reload-plugins`.

For local development, `claude --plugin-dir plugins/<name>` bypasses the cache and loads straight from the working tree.

## Skill Workflows

The planning skills form a pipeline — each step is optional, drop in at any point:

```mermaid
flowchart TD
    BS(["brainstorm"])
    PL(["planning:plan"])
    RP(["planning:review-plan"])
    RD(["revdiff:revdiff"])
    IM["implement"]
    DPR(["planning:pr"])

    BS -.->|optional warmup| PL
    PL -->|auto-review| RP
    PL -->|revdiff| RD
    PL -->|skip| IM
    RP --> IM
    RD --> IM
    IM --> DPR
```

## Plugins

### statusline

Custom status line (robbyrussell-style).

```
/plugin install statusline@parmaster-claude-dlc
```

Shows: current dir, git branch + dirty state (`✗`), model name, context %, 5h/7d usage rates with reset time.

After install, run `claude --init-only` once to trigger the setup hook — it writes `statusLine` into `~/.claude/settings.json`. Then relaunch Claude normally.

---

### planning

Structured implementation plan creation.

```
/plugin install planning@parmaster-claude-dlc
```

| Skill | Description |
|-------|-------------|
| `plan` | Create `docs/plans/YYYYMMDD-<name>.md` with context gathering and approach exploration. Offers auto-review and/or revdiff annotation at the end. |
| `review-plan` | Structured agent-based plan critique — correctness, over-engineering, test coverage, conventions. Presents findings by severity (Critical/Important/Minor) with APPROVE/NEEDS REVISION verdict. Iterates up to 3 rounds, then lands on a "what's next" menu (re-run auto-review, switch to revdiff, or Done) that keeps re-asking until Done is explicitly chosen. Invoke on any plan: `/review-plan docs/plans/foo.md` |
| `pr` | Open a draft PR from the plan file — interactive title (`[feat\|fix\|chore]: TICKET-ID - title`) and plan-based description. If a PR already exists on the branch, reads the current description and amends it with the new plan's changes rather than replacing it. |

**`plan` — flow**

```mermaid
flowchart TD
    A["user request"] --> B["parse intent & gather context"]
    B --> C["ask questions: goal, scope, constraints, title"]
    C --> D{"approach obvious?"}
    D -->|no| E["propose 2–3 approaches"]
    E --> F["user picks approach"]
    D -->|"yes / bug fix"| F
    F --> G{"TDD or Regular?"}
    G -->|TDD| H["tests-first task template"]
    G -->|Regular| I["code-first task template"]
    H --> J["create plan + dependency check + self-review"]
    I --> J
    J --> K{"next step?"}
    K -->|auto-review| L(["planning:review-plan"])
    K -->|revdiff| M(["revdiff:revdiff"])
    K -->|done| N(["stop"])
```

**`review-plan` — flow**

```mermaid
flowchart TD
    A["find plan file"] --> B["spawn review agent — Round N"]
    B --> C["read plan + relevant source files"]
    C --> D["verify dependency behaviors end-to-end"]
    D --> E{"verdict"}
    E -->|"NEEDS REVISION, round < 3"| G{"user choice"}
    G -->|"Fix and re-review"| H["apply fixes to plan"]
    H --> B
    G -->|"Switch to revdiff"| RD(["revdiff:revdiff"])
    G -->|Done| STOP(["stop"])
    E -->|APPROVE| M{"post-review menu"}
    E -->|"round limit hit"| M
    M -->|"Run auto-review"| B
    M -->|"Review with revdiff"| RD
    RD --> M
    M -->|Done| STOP2(["stop ✓ ready for implementation"])
```

**`pr` — flow**

```mermaid
flowchart TD
    A["find plan file"] --> B{"existing PR?"}
    B -->|yes| C["read current PR body"]
    C --> D["merge plan changes into description"]
    D --> E(["gh pr edit"])
    B -->|no| F["detect ticket ID from branch"]
    F --> G["ask: type / ticket ID / title"]
    G --> H["generate description from plan"]
    H --> I(["gh pr create --draft"])
    E --> J["output PR URL"]
    I --> J
```

---

### brainstorm

Collaborative design dialogue before implementation.

```
/plugin install brainstorm@parmaster-claude-dlc
```

| Skill | Description |
|-------|-------------|
| `brainstorm` | Turn ideas into designs through one-at-a-time questions, approach exploration, and incremental validation. |

---

### style

Writing style for technical communication.

```
/plugin install style@parmaster-claude-dlc
```

| Skill | Description |
|-------|-------------|
| `writing-style` | Direct, brief style for PRs, Jira tickets, issue comments, commit messages. No AI-speak. |

---

### go-tools

Go development guards.

```
/plugin install go-tools@parmaster-claude-dlc
```

| Hook | Trigger | Effect |
|------|---------|--------|
| `block-explore-in-go` | `Agent` tool with `subagent_type=Explore` in a Go project **and** a prompt signalling Go-symbol intent (`func`/`type`/`interface`/`struct`/`method`/`symbol`/`caller`/`implementation`/`.go`, …) | Denies and redirects to `gosymdb:sym` / `gosymdb:trace` / `gosymdb:impact`. General non-symbol exploration passes through. |
| `block-gosymdb-pipe` | `Bash` command containing `gosymdb \| python` or `gosymdb \| jq` | Denies with a reminder to read gosymdb JSON directly |
| `block-go-symbol-grep` | `Bash` grep/rg/git-grep that targets `.go` files, or searches for a Go declaration keyword (`func`/`type`/`interface`/`struct`) inside a Go module | Denies and redirects to `gosymdb:sym` / `gosymdb:trace` / `gosymdb:impact` |

### global-rules

Shared global CLAUDE.md rules distributed across machines.

```
/plugin install global-rules@parmaster-claude-dlc
```

After install, run `claude --init-only` once to trigger the setup hook — it appends a single `@import` line to `~/.claude/CLAUDE.md` pointing at the plugin file. Existing content on any machine is untouched. Machine-specific rules stay in `~/.claude/CLAUDE.md` directly; shared rules live in the plugin and are updated on reinstall.

Includes: plan-first workflow, commit hygiene (tests + linter before commit), Go tooling (gosymdb), CLI best practices.

---

### git-tools

Git workflow skills.

```
/plugin install git-tools@parmaster-claude-dlc
```

| Skill | Description |
|-------|-------------|
| `squash-rebase` | Rebase onto main after a parent branch was squash-merged — auto-detects the cut point via file overlap heuristic, shows what will be dropped vs replayed, asks for confirmation before running `git rebase --onto`. |

---

## Local Development

Test a plugin from your local working tree without installing it:

```
claude --plugin-dir plugins/<name>
```

This loads the plugin directly from the repo directory. Skills, hooks, and commands are picked up from there instead of the installed cache, so edits take effect immediately.

Use `/reload-plugins` inside an active session to pick up file changes without restarting Claude.

Skills are invokable by full name (e.g. `/planning:plan`) but won't appear in the `/` autocomplete dropdown — only `commands/*.md` files do. Invoke them by typing the full name or via natural language.

To test the marketplace catalog itself (adding/removing plugins), edit `.claude-plugin/marketplace.json` and re-add the marketplace:

```
/plugin marketplace add parmaster/claude-dlc
```
