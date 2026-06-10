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

## Plugins

### statusline

Custom status line (robbyrussell-style).

```
/plugin install statusline@parmaster-claude-dlc
```

Shows: current dir, git branch + dirty state (`✗`), model name, context %, 5h/7d usage rates with reset time.

The setup hook writes `statusLine` into `~/.claude/settings.json` automatically on install.

---

### planning

Structured implementation plan creation.

```
/plugin install planning@parmaster-claude-dlc
```

| Skill | Description |
|-------|-------------|
| `plan` | Create `docs/plans/YYYYMMDD-<name>.md` with context gathering, approach exploration, and revdiff review loop. Single summary commit baked in. |
| `pr` | Open a draft PR from the plan file — interactive title (`[feat\|fix\|chore]: TICKET-ID - title`) and plan-based description following writing-style. |

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
| `block-explore-in-go` | `Agent` tool with `subagent_type=Explore` in a Go project | Denies and redirects to `gosymdb:sym` / `gosymdb:trace` / `gosymdb:impact` |
| `block-gosymdb-pipe` | `Bash` command containing `gosymdb \| python` or `gosymdb \| jq` | Denies with a reminder to read gosymdb JSON directly |

## Local Development

```
claude --plugin-dir plugins/<name>
```

Use `/reload-plugins` inside a session to pick up file changes without restarting.
