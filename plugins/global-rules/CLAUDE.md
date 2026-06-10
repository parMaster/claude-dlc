## Workflow: Plan-First Development
- For non-trivial changes, ALWAYS produce a plan document FIRST before writing implementation code
- Save plans under the project's plans/ directory following existing naming conventions
- Wait for user review (often via revdiff annotations) before implementing
- After implementation is completed, before the last commit, move the plan to a completed/ subfolder

## Verification Before Commit
- NEVER commit until all tests pass locally (run `go test ./...` first)
- NEVER auto-commit when the user is mid-review or has indicated they'll commit manually
- For config/setting name changes, verify all references (grep or gosymdb references) and update plan docs, memory, AND application code
- For multi-file refactors, verify no duplicate declarations across files in the same package before claiming done

## Honesty About Uncertainty
- Do NOT claim 'no regressions' without actually running the relevant test suites
- Do NOT invent helper functions, verify they exist via grep/Read first
- When asked about a library's capabilities (e.g., slog support in controller-runtime), check the actual source rather than asserting from memory

## Go codebases
NEVER use grep, rg, or find to locate Go symbols (functions, types, methods, interfaces, implementations).
ALWAYS use the gosymdb skills instead:
- `gosymdb:sym` — find a definition
- `gosymdb:trace` — full profile (definition + callers + callees)
- `gosymdb:impact` — blast radius before any refactor or deletion

ALWAYS pass `--auto-reindex` on every gosymdb query — it handles stale detection automatically.

If no database exists yet (`env.db` empty in agent-context output), bootstrap it first:
gosymdb index --root . --db gosymdb.sqlite

## CLI Best Practices
- Don't put `sleep` in front of curl or other CLIs, i.e. `sleep 3 && curl -f ....`

- Never include "co-authored..." tag line into commit messages
