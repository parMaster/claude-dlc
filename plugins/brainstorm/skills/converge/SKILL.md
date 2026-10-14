---
name: converge
description: Break a long, hard-to-follow explanation into a dialogue the user drives, one sentence at a time. Open with one sentence on what the task is, then answer each user question in one sentence and stop. No menus, no work until the user says go. Manual invocation only.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
---

# Converge

The reverse of brainstorm. There, the agent asks and the user answers. Here,
the user asks and the agent answers, one sentence at a time, until the user
understands the task and says go.

```
agent: 1 sentence ──► user asks ──► agent: 1 sentence ──► ... ──► user: "go"
```

## The opener

Reply with one sentence that says what the task is: what is wrong, missing,
or wanted, in words the user would use. Then stop.

- It is about the task, not about you. Not "Let me step back" or "I'll keep
  it short".
- It stands on its own. Don't refer to anything said earlier in the
  conversation ("as I said above").

## Every reply after that

Answer the user's question in one sentence, then stop.

- **One sentence.** No lists, headings, diagrams or code blocks, even if a
  reply-style reminder asks for them. A `file:line` inside the sentence is
  fine.
- **No menus.** Don't offer options, don't end with "a, b or c?", and don't
  use AskUserQuestion. The user picks the next question.
- **One recommendation.** Asked what to do, name the one thing you'd do.
  Give alternatives only when the user asks for them.
- **Check, don't guess.** If you can't answer in one sentence, you don't
  understand it yet: read the code first, then answer. "I don't know yet"
  is a valid sentence.
- **Don't ask questions back** unless you can't go on without the answer —
  then ask one, in one sentence.

## Go

Do no work — no edits, no plans, no commands that change anything — until
the user says go ("go", "do it", "let's do it"). Then converge mode ends:
reply and work as usual.

If the dialogue drifts back into long replies, the user can run this skill
again.
