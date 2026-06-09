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

### planning

Structured implementation plan creation.

```
/plugin install parmaster/claude-dlc/planning
```

| Skill | Description |
|-------|-------------|
| `plan` | Create `docs/plans/YYYYMMDD-<name>.md` with context gathering, approach exploration, and revdiff review loop. Single summary commit baked in. |
| `pr` | Open a draft PR from the plan file — interactive title (`[feat\|fix\|chore]: TICKET-ID - title`) and plan-based description following writing-style. |

---

### brainstorm

Collaborative design dialogue before implementation.

```
/plugin install parmaster/claude-dlc/brainstorm
```

| Skill | Description |
|-------|-------------|
| `brainstorm` | Turn ideas into designs through one-at-a-time questions, approach exploration, and incremental validation. |

---

### style

Writing style for technical communication.

```
/plugin install parmaster/claude-dlc/style
```

| Skill | Description |
|-------|-------------|
| `writing-style` | Direct, brief style for PRs, Jira tickets, issue comments, commit messages. No AI-speak. |

---

### go-tools

Go development guards.

```
/plugin install parmaster/claude-dlc/go-tools
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
