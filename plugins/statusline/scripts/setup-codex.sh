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
