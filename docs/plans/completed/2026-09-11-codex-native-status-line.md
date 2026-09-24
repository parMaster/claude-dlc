# Codex Native Status Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in installer that configures Codex's native footer to mirror the existing Claude status line as closely as supported.

**Architecture:** A standalone shell entry point runs an embedded Python updater against `$CODEX_HOME/config.toml` or `$HOME/.codex/config.toml`. The updater validates TOML before and after a narrow, comment-preserving edit and atomically replaces the config; the existing Claude hook remains untouched.

**Tech Stack:** Bash, Python 3.11+ standard library, Codex CLI configuration, Markdown.

---

### Task 1: Add the Codex config installer

**Files:**
- Create: `plugins/statusline/scripts/setup-codex.sh`

- [x] **Step 1: Create the installer**

Create `plugins/statusline/scripts/setup-codex.sh` with the complete implementation below:

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
  printf 'error: Python 3.11 or newer is required to update the Codex config safely\n' >&2
  exit 1
fi

CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
CONFIG="${CODEX_CONFIG_DIR}/config.toml"
mkdir -p "$CODEX_CONFIG_DIR"

python3 - "$CONFIG" <<'PY'
import os
import re
import sys
import tempfile
import tomllib
from pathlib import Path

config_path = Path(sys.argv[1])
status_line = '''status_line = [
  "current-dir",
  "git-branch",
  "model-with-reasoning",
  "context-used",
  "five-hour-limit",
  "weekly-limit",
]'''


def fail(message):
    raise SystemExit(f"error: {config_path}: {message}")


def assignment_end(lines, start):
    value = lines[start].split("=", 1)[1].strip()
    if not value.startswith("["):
        fail("tui.status_line must be an array before it can be updated")
    if re.search(r"]\s*(?:#.*)?$", value):
        return start + 1
    for index in range(start + 1, len(lines)):
        if re.match(r"^\s*]\s*(?:#.*)?$", lines[index]):
            return index + 1
    fail("could not find the end of the existing tui.status_line array")


original = config_path.read_text() if config_path.exists() else ""
if original.strip():
    try:
        parsed = tomllib.loads(original)
    except tomllib.TOMLDecodeError as exc:
        fail(f"existing config is invalid TOML: {exc}")
    current = parsed.get("tui", {}).get("status_line")
    if current is not None and not isinstance(current, list):
        fail("tui.status_line must be an array before it can be updated")

lines = original.splitlines(keepends=True)
section_re = re.compile(r"^\s*\[([^]]+)]\s*(?:#.*)?$")
key_re = re.compile(r"^\s*status_line\s*=")
tui_start = None
tui_end = len(lines)
first_tui_child = None

for index, line in enumerate(lines):
    match = section_re.match(line.rstrip("\r\n"))
    if not match:
        continue
    section = match.group(1).strip()
    if section == "tui":
        tui_start = index
        continue
    if section.startswith("tui.") and first_tui_child is None:
        first_tui_child = index
    if tui_start is not None and index > tui_start:
        tui_end = index
        break

replacement = status_line + "\n"
if tui_start is not None:
    assignment = next(
        (index for index in range(tui_start + 1, tui_end) if key_re.match(lines[index])),
        None,
    )
    if assignment is None:
        lines.insert(tui_start + 1, replacement)
    else:
        end = assignment_end(lines, assignment)
        lines[assignment:end] = [replacement]
else:
    insert_at = first_tui_child if first_tui_child is not None else len(lines)
    prefix = "" if insert_at == 0 or lines[insert_at - 1].endswith("\n\n") else "\n"
    lines.insert(insert_at, f"{prefix}[tui]\n{replacement}\n")

updated = "".join(lines)
try:
    tomllib.loads(updated)
except tomllib.TOMLDecodeError as exc:
    fail(f"generated config is invalid TOML: {exc}")

if updated == original:
    print(f"Codex status line already configured in {config_path}")
    raise SystemExit(0)

mode = config_path.stat().st_mode & 0o777 if config_path.exists() else 0o600
temp_name = None
try:
    with tempfile.NamedTemporaryFile(
        mode="w", dir=config_path.parent, prefix="config.toml.", delete=False
    ) as temp:
        temp_name = temp.name
        temp.write(updated)
        temp.flush()
        os.fsync(temp.fileno())
    os.chmod(temp_name, mode)
    os.replace(temp_name, config_path)
except OSError as exc:
    if temp_name:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
    fail(f"could not write config atomically: {exc}")

print(f"Configured Codex status line in {config_path}")
print("Fields: current-dir, git-branch, model-with-reasoning, context-used, five-hour-limit, weekly-limit")
PY
```

- [x] **Step 2: Mark the installer executable and check its syntax**

Run:

```bash
chmod +x plugins/statusline/scripts/setup-codex.sh
bash -n plugins/statusline/scripts/setup-codex.sh
```

Expected: exit status 0 with no syntax errors.

### Task 2: Document the Codex setup path

**Files:**
- Modify: `README.md:57`

- [x] **Step 1: Separate the client instructions**

Keep the current instructions under a `#### Claude Code` heading. Add:

````markdown
#### Codex

Codex uses its native footer renderer. From this repository, run:

```bash
bash plugins/statusline/scripts/setup-codex.sh
```

Restart Codex after setup. The footer shows the current directory, Git branch, model and reasoning effort, context use, five-hour use, and weekly use. Codex controls the colors and labels; its native footer does not expose the Claude line's prompt symbol, dirty-tree marker, custom context color, or reset time.
````

- [x] **Step 2: Inspect the rendered section**

Run `sed -n '55,100p' README.md`.

Expected: separate Claude Code and Codex subsections, each with one setup command.

### Task 3: Verify fixtures and install locally

**Files:**
- Modify: `/Users/gusto/.codex/config.toml` through the installer after filesystem approval

- [x] **Step 1: Exercise temporary fixtures**

Use temporary `CODEX_HOME` directories for a missing config, an existing `[tui]` table, an existing multiline `status_line`, and the current-shape case where `[tui.model_availability_nux]` exists without `[tui]`. Validate each output with `tomllib` and confirm comments and unrelated keys remain.

Expected: all fixtures parse; the six fields appear in order; the parent `[tui]` table precedes an existing `[tui.*]` child.

- [x] **Step 2: Verify idempotence**

Run the installer twice against the same temporary fixture and compare checksums.

Expected: the second run prints `already configured` and the checksum stays unchanged.

- [x] **Step 3: Install and validate the live config**

Run `bash plugins/statusline/scripts/setup-codex.sh` with approval to write outside the repository, followed by `codex --strict-config --version`.

Expected: the installer updates `/Users/gusto/.codex/config.toml` and Codex accepts it.

### Task 4: Review without committing

**Files:**
- Review: `plugins/statusline/scripts/setup-codex.sh`
- Review: `README.md`
- Review: `docs/plans/2026-09-11-codex-native-status-line-design.md`
- Review: `docs/plans/2026-09-11-codex-native-status-line.md`

- [x] **Step 1: Run final checks**

Run:

```bash
bash -n plugins/statusline/scripts/setup-codex.sh
git diff --check
git status --short
```

Expected: checks pass, and status lists the status-line work plus the user's pre-existing untracked files.

- [x] **Step 2: Review the complete diff**

Inspect the four files above. Leave every change uncommitted until the user reviews the finished job.
