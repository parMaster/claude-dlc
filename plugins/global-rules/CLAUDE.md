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

## Go codebases

**Vendored dependencies** — when a vendored Go repo (has a `vendor/` dir) shows stale/inconsistent vendoring (e.g. `inconsistent vendoring`, missing/extra packages in `vendor/`, or build/import errors right after switching branches or merging), do NOT investigate — just run `go mod tidy && go mod vendor` to resync. Only dig deeper if that doesn't resolve it.

## Auto-Memory Discipline
- Before writing to the auto-memory system (`~/.claude/projects/*/memory/`), propose the memory content and ask for confirmation first — do not write silently. Exception: the user explicitly asked to remember/save something ("remember this", "save that to memory") — write immediately in that case, no confirmation needed.
- This applies per memory write. Don't chain 2-3 unconfirmed saves in a row just because several things seemed memory-worthy in the same turn — ask about each, or batch them into one confirmation ask if closely related.

## CLI Best Practices
- Don't put `sleep` in front of curl or other CLIs, i.e. `sleep 3 && curl -f ....`
- Don't prepend `cd <path>` to a Bash command when the session is already rooted in that directory — the shell resets to the working dir each call, so it's redundant noise. Only `cd` (or use `make -C <dir>`) when the command must operate outside the session root.

- Never include "co-authored..." tag line into commit messages
