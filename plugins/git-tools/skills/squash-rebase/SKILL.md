---
name: squash-rebase
description: Rebase the current branch onto main after its parent branch was squash-merged. Activates on "squash rebase", "rebase onto main", "parent branch was squash-merged", or when git rebase would re-apply already-merged commits.
allowed-tools: Bash, AskUserQuestion
---

# Squash-Rebase onto Main

Rebase the current branch onto main, keeping only commits that are NOT already in main via a squash merge.

## Problem this solves

When a feature branch is started from another feature branch (e.g. `feat/A`), and `feat/A` later gets squash-merged into `main`, the current branch inherits all of `feat/A`'s commits. Git cannot detect that those commits are already in main (the squash changed their SHA), so a plain `git rebase main` would conflict or re-apply duplicate work.

## Procedure

1. Verify we're on a branch (not detached HEAD) and that `main` exists.

2. Find the common ancestor:
   ```
   git merge-base main HEAD
   ```

3. List all commits in the branch not in main:
   ```
   git log --oneline main..HEAD
   ```
   Show this to the user so they have full context.

4. Auto-detect the cut point using file overlap heuristic:
   - Get the squash commit (first commit on main after the merge-base):
     `git log --format="%H" "<merge-base>..main" | tail -1`
   - Get the files it touched:
     `git diff --name-only <squash>^ <squash>`
   - Walk the branch commits from **oldest to newest**. For each commit, get its changed files:
     `git diff --name-only <commit>^ <commit>`
   - The last commit where ALL its changed files are also in the squash commit's file list is the likely cut point.
   - The first commit that touches a file NOT in the squash commit is the first "new" commit.

5. Show the user:
   - The detected cut point commit
   - The commits that WILL be replayed onto main (the new work)
   - The commits that will be DROPPED (already in main via squash)

6. Ask for confirmation. If the auto-detected cut point looks wrong, run `git log --oneline <parent-branch>` (if the parent branch still exists locally) to show the user the candidate commits, and ask them to pick the correct cut point.

7. Run:
   ```
   git rebase --onto main <cut-point-hash>
   ```

8. If there are conflicts, explain them and help resolve. After resolution, run `git rebase --continue`.

9. Show the final `git log --oneline -5` to confirm the clean result.

10. Remind the user they'll need `git push --force-with-lease` since history was rewritten.
