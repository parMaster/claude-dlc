## Workflow: Plan-First Development
- For non-trivial changes, ALWAYS produce a plan document FIRST before writing implementation code — create it with the `planning:plan` skill (writes `docs/plans/<date>-<name>.md`), even when the conversation reaches planning organically without an explicit "write a plan" request. Do NOT substitute the built-in plan mode (EnterPlanMode) for this; it only prints the plan into the conversation and does not save the `docs/plans/` document that `review-plan` and `pr` depend on.
- Wait for user review before implementing
- After implementation is completed, before the last commit, move the plan to a completed/ subfolder

## Git Hygiene
- **Stale branch** — before starting to plan or implement, and again right before the final commit, check whether the current branch is behind its remote tracking branch (`git fetch` then `git status`). If it's behind, resync immediately — `git pull --rebase` (or plain `git pull` if there are no local commits yet) — instead of discovering it later when `git push` is rejected as non-fast-forward. Resolve any conflicts the resync surfaces as part of finishing the work, not as a follow-up.

## Verification Before Commit
- NEVER commit until the project's tests (`make test`, the CI test step, or `go test ./...`) and linter (`golangci-lint run ./...`, `eslint .`) pass locally.
- **Reproduce, then fix** — when a test fails, see it fail before you fix it. A CI log of the failure already counts. After the fix, one passing run proves it. Don't stash or revert a finished fix to watch the test fail again.

## Code Comments
- Never point elsewhere — no ticket, plan, spec, slice or PR reference. Inline the one clause of context the reader needs instead. The `block-comment-refs` hook denies the grep-able cases.

## Atlassian MCP Hygiene
- Route every Atlassian MCP call (Jira or Confluence) through one `global-rules:atlassian-caller` spawn per goal, even a lone `getJiraIssue`. Ask for the end result ("confirm the issue is Done, transitioning it if it isn't") and use only its report.

## Go codebases

**Vendored dependencies** — when a vendored Go repo (has a `vendor/` dir) shows stale/inconsistent vendoring (e.g. `inconsistent vendoring`, missing/extra packages in `vendor/`, or build/import errors right after switching branches or merging), do NOT investigate — just run `go mod tidy && go mod vendor` to resync. Only dig deeper if that doesn't resolve it.

**Dependency source lookup** — to read a dependency's actual source (verifying behavior, checking a function body, etc.), check `./vendor/<module-path>` in the current repo FIRST. Only fall back to `go env GOMODCACHE` if the repo has no `vendor/` dir or the package isn't vendored there — these repos are vendored essentially 100% of the time.

## Auto-Memory Discipline
- Consider a memory only when it (1) isn't already recorded elsewhere — code, CLAUDE.md, git history — and (2) would matter in a future session on unrelated work. Otherwise say nothing about memory.
- Propose the content and ask before any write to `~/.claude/projects/*/memory/`, unless the user explicitly says to save it to memory.

## Response Brevity
- **Answer first.** The first sentence is the answer or the decision. Reasons come after it, never before.
- **Size to the question.** A simple question gets at most 4 sentences and no headings.
- **No opening about yourself.** Don't start by commenting on your last reply or your process. If it matters, add one clause after the answer.
- **One idea per sentence.** At most 25 words and one technical term. If a sentence needs "and", "which" or a dash to carry a second idea, split it.
- **No noun stacks.** At most 3 nouns in a row. Not "reconcile loop status update path"; write "the path that updates status in the reconcile loop".
- **Keep the small words.** Keep articles (a, the) and linking words (because, so, then). Don't drop words to make a sentence shorter.
- **Verbs for actions.** "Install it", not "do the installation".
- **Name who acts.** "The operator deletes the pod", not "the pod gets deleted".
- **Same word, same thing.** Once you name something, keep that name. Don't switch to a synonym.
- **Plain words.** Don't write utilize, leverage, facilitate, implement, functionality, additionally, prior to, in order to. Write use, use, help, build, feature, also, before, to.
- **Lists and paragraphs.** Put 3+ related points in a vertical list. A paragraph has one topic and at most 6 sentences.
- **No recap.** After you act, use at most one sentence on what changed. Don't restate the question or the plan before you act.
- **Long content goes in the file.** Plans, code and reports stay in their file. Don't retell them in chat.
- **Draw flows.** If a flow is easier to see than to read, draw a small text diagram.
