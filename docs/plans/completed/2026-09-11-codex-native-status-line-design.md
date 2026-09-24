# Codex Native Status Line Design

## Goal

Extend the existing `statusline` plugin with an opt-in setup path for Codex. The Codex footer should show the closest native equivalent of the Claude status line: current directory, Git branch, model and reasoning effort, context use, five-hour use, and weekly use.

## User experience

The repository will provide one documented setup command for Codex. Running it updates the user's Codex configuration and prints the configured field order. A restarted Codex CLI then renders its native footer with these items:

```toml
[tui]
status_line = [
  "current-dir",
  "git-branch",
  "model-with-reasoning",
  "context-used",
  "five-hour-limit",
  "weekly-limit",
]
```

Codex owns the footer's colors, labels, spacing, and live values. The Claude renderer remains unchanged.

## Components

Add `plugins/statusline/scripts/setup-codex.sh` as a separate installer. It edits the Codex config path, which defaults to `$CODEX_HOME/config.toml` when `CODEX_HOME` is set and `$HOME/.codex/config.toml` otherwise. Keeping the Codex installer separate avoids adding Codex-specific behavior to Claude's install hook.

Update `README.md` with the Codex command, the resulting field order, and the native-rendering limitation. The existing Claude installation instructions stay in place.

## Configuration update

The installer performs one narrow change: set `tui.status_line` to the ordered list above. It preserves all other TOML content and comments. It handles an existing `[tui]` table, an existing single-line or multiline `status_line` value, and a config with no `[tui]` table. Repeated runs produce the same file content.

The installer writes through a temporary file in the config directory and replaces the config only after validating the result. If the config does not exist, it creates the parent directory and a minimal config containing the `[tui]` table.

## Error handling

The installer exits without changing the config when it cannot parse the existing table structure, cannot create a temporary file, or cannot validate the generated TOML. It prints the failing path and a short corrective action. A failed run removes its temporary file.

## Verification

Run the installer against temporary fixtures for a missing config, no `[tui]` table, an existing `[tui]` table, an existing multiline value, and a repeated run. Check the exact status-line order, confirm unrelated settings and comments survive, and validate each result as TOML.

After installation, `codex --strict-config --version` checks that the installed Codex accepts the config. The user can launch Codex or run `/statusline` to inspect the rendered footer.

## Limits

Codex's native status line does not expose the Claude renderer's prompt symbol, custom colors, Git dirty marker, magenta context threshold, or explicit reset time. This design uses only supported native item identifiers and avoids patching or wrapping the Codex TUI.
