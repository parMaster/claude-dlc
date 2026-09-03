## Workflow: Plan-First Development
- For non-trivial changes, ALWAYS produce a plan document FIRST before writing implementation code — create it with the `planning:plan` skill (writes `docs/plans/<date>-<name>.md`), even when the conversation reaches planning organically without an explicit "write a plan" request. Do NOT substitute the built-in plan mode (EnterPlanMode) for this; it only prints the plan into the conversation and does not save the `docs/plans/` document that `review-plan` and `pr` depend on.
- Save plans under the project's plans/ directory following existing naming conventions
- Wait for user review (often via revdiff annotations) before implementing
- After implementation is completed, before the last commit, move the plan to a completed/ subfolder

## Git Hygiene
- **Stale branch** — before starting to plan or implement, and again right before the final commit, check whether the current branch is behind its remote tracking branch (`git fetch` then `git status`). If it's behind, resync immediately — `git pull --rebase` (or plain `git pull` if there are no local commits yet) — instead of discovering it later when `git push` is rejected as non-fast-forward. Resolve any conflicts the resync surfaces as part of finishing the work, not as a follow-up.

## Verification Before Commit
- NEVER commit until all tests pass locally (run `go test ./...` first)
- NEVER commit until the linter passes — run the appropriate linter for the project (e.g. `golangci-lint run ./...` for Go, `eslint .` for JS/TS) and fix any failures before committing
- NEVER auto-commit when the user is mid-review or has indicated they'll commit manually
- For config/setting name changes, verify all references (grep) and update plan docs, memory, AND application code
- For multi-file refactors, verify no duplicate declarations across files in the same package before claiming done

## Honesty About Uncertainty
- Do NOT claim 'no regressions' without actually running the relevant test suites
- Do NOT invent helper functions, verify they exist via grep/Read first
- When asked about a library's capabilities (e.g., slog support in controller-runtime), check the actual source rather than asserting from memory

## Atlassian MCP Hygiene
- **Scope Jira field requests** — Atlassian Jira MCP calls (`getJiraIssue`, `searchJiraIssuesUsingJql`, and similar) default to returning `summary, description, status, issuetype, priority, labels, components, assignee, reporter, created, updated, resolution, project` — several of those (`assignee`, `reporter`, `project`) are nested objects carrying avatar URLs and self-links that bloat the session even for a two-line lookup. Always pass an explicit `fields` array scoped to only what's needed (e.g. `["status"]` for a status check, `["description"]` for a description) — never rely on the default set, and never pass `fields: ["*all"]` unless the user explicitly asked for full fidelity. Also pass `responseContentFormat: "markdown"` — it returns simplified plain text instead of full ADF JSON.
- **Delegate compound Jira work to a subagent** — for anything needing several Jira MCP calls to produce one small answer (e.g. transition status + add comment + list subtasks, or bulk JQL search across many issues), dispatch a subagent via the Agent tool with a description of the end result needed, and use only its distilled report. This keeps the raw multi-call JSON out of the main session context; a single well-scoped call (per the rule above) doesn't need this.

## Go codebases

**Vendored dependencies** — when a vendored Go repo (has a `vendor/` dir) shows stale/inconsistent vendoring (e.g. `inconsistent vendoring`, missing/extra packages in `vendor/`, or build/import errors right after switching branches or merging), do NOT investigate — just run `go mod tidy && go mod vendor` to resync. Only dig deeper if that doesn't resolve it.

**Dependency source lookup** — to read a dependency's actual source (verifying behavior, checking a function body, etc.), check `./vendor/<module-path>` in the current repo FIRST. Only fall back to `go env GOMODCACHE` if the repo has no `vendor/` dir or the package isn't vendored there — these repos are vendored essentially 100% of the time.

## Auto-Memory Discipline
- Don't treat "user gave feedback/correction" alone as a trigger to propose a memory save. Only consider saving something when it (1) isn't already recorded elsewhere — code, CLAUDE.md, git history — and (2) would matter in a future session on unrelated work. If it fails either check, say nothing about memory.
- If it passes both checks, before writing to the auto-memory system (`~/.claude/projects/*/memory/`), propose the memory content and ask for confirmation first — do not write silently.
- Exception: skip the checks and the confirmation ask only when the user unambiguously directs you to persist something to *your memory system* — "remember this for next time", "save that to memory", "add this to your notes." A colloquial "remember" about a task ("we should remember to update the ticket") is not this — that's a to-do, not an instruction to write to memory, and gets no special treatment.
- This applies per memory write. Don't chain 2-3 unconfirmed saves in a row just because several things seemed memory-worthy in the same turn — ask about each, or batch them into one confirmation ask if closely related.

## Response Brevity
- Simple questions get a few sentences, not multi-paragraph answers — skip the surrounding essay.
- **Conclusion before justification, always** — the first sentence is the answer or decision, full stop, no matter why you're explaining anything (self-correction, weighing options, showing work). Reasoning worth keeping goes after the conclusion, never before it.
- **No self-critique preamble** — don't open by commenting on your own prior turn or process (question count, clarity, overcomplication). Cut it; if it matters at all, fold it into one clause after the actual content, not as a lead-in.
- **Plain words, no exceptions** — swap jargon and Latinate filler for the word a colleague would actually say out loud: utilize→use, leverage→use, facilitate→help, implement→build, functionality→feature, additionally→also, prior to→before, in order to→to. One unavoidable technical term per sentence, max — split the sentence or cut the second term. Before sending, reread the draft: if any sentence needs to be decoded word-by-word, rewrite it — don't add a caveat and move on.
- If the user corrects this once, it stays fixed for the rest of the session, not just the next reply — don't drift back into jargon once the immediate feedback fades.
- If a relationship or flow is easier to see than read (a few boxes and arrows), sketch a small text diagram instead of describing it in prose.
- Don't recap what you just did beyond one sentence — the diff/output already shows it.
- Don't restate the question or the plan back before acting on it.
- Long-form content belongs in the artifact itself (plan, code, report) — don't narrate it again in chat on top of that.

## CLI Best Practices
- Don't put `sleep` in front of curl or other CLIs, i.e. `sleep 3 && curl -f ....`
- Don't prepend `cd <path>` to a Bash command when the session is already rooted in that directory — the shell resets to the working dir each call, so it's redundant noise. Only `cd` (or use `make -C <dir>`) when the command must operate outside the session root.
