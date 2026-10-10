#!/usr/bin/env bash
# WorktreeCreate hook: fails a worktree that Claude Code tries to create inside
# a session, such as for a subagent with worktree isolation.
#
# This event has no decision JSON. Creation succeeds only when the hook prints
# a path and exits 0, so printing nothing and exiting non-zero is the block.

cat > /dev/null

echo "Worktrees are turned off on this machine. Work in the current checkout." >&2
exit 1
