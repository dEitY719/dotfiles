---
name: ai-worktree:teardown
description: >-
  Clean up an AI worktree after work is done — remove worktree, delete branch,
  sync main. The reverse of ai-worktree:spawn. Use when the user says "작업 끝",
  "워크트리 정리", "teardown", "cleanup worktree", "작업 완료", "워크트리 제거",
  or any request to clean up after finishing work in a worktree.
allowed-tools: Bash, Read, Grep, Glob
---

# AI Worktree Teardown

Remove an AI worktree and sync main after work is complete.
This is the reverse of `ai-worktree:spawn`.

Read `references/options-and-errors.md` for CLI options and error handling.

## Execution Steps

Run these steps in order. Stop immediately on any error.
Read `references/bash-commands.md` for exact bash implementations per step.

### Step 1: Validate — Must Be Inside a Worktree

Check `git-dir != git-common-dir`. If NOT inside a worktree, print error and stop.
This is the inverse of spawn's check.

### Step 2: Pre-flight Checks

Block on uncommitted changes or unpushed commits to prevent work loss.
Skip these checks if `--force` is given.

### Step 3: Identify Main Repo and Worktree Info

Extract from current worktree:
- `WORKTREE_PATH` — current toplevel
- `MAIN_REPO` — derived from git-common-dir
- `BRANCH` — current branch name
- `WORKTREE_NAME` — basename of worktree path

### Step 4: Switch to Main Repo

`cd` into the main repo directory. All subsequent commands run from there.

### Step 5: Remove Worktree

`git worktree remove <path>`. On failure, try `--force` if user opted in.

### Step 6: Sync Main

`git checkout main && git pull origin main`.
Must run BEFORE branch delete so `git branch -d` can verify merge status.
If pull conflicts, the AI agent attempts to resolve them and reports.

### Step 7: Delete Branch

`git branch -d <branch>` (safe delete — verifies merge status).
Skip if `--keep-branch` is given. Warn if branch is not fully merged.

### Step 8: Log

Append `TEARDOWN` entry to `ai-worktree-spawn.log` (same file as spawn).

### Step 9: Report

```
[OK] Teardown complete
  Removed:  ../my-app-gemini-1
  Branch:   wt/gemini/1 (deleted)
  Now on:   main (up to date with origin/main)
```
