---
name: ai-worktree:spawn
description: >-
  Create an isolated git worktree workspace for the current AI coding agent.
  Use when starting new parallel work in a multi-AI agent environment. Triggers
  on: "새로운 작업 시작", "새 작업 시작하자", "격리된 작업 공간 만들어줘",
  "start new task", "spawn a worktree", or any request to begin isolated work
  in a multi-agent setup.
allowed-tools: Bash, Read, Grep, Glob
---

# AI Worktree Spawn

Create an isolated git worktree so this AI agent can work without interfering
with other agents running in the same repository.

Read `references/options-and-errors.md` for CLI options and error handling.

## Execution Steps

Run these steps in order. Stop immediately on any error.
Read `references/bash-commands.md` for exact bash implementations per step.

### Step 1: Validate Preconditions

Verify: git repo, NOT inside a worktree (block if so), warn on dirty state,
check parent directory write permission.

### Step 2: Detect AI Agent

Read `references/agent-detection.md` for the full priority chain and env var table.
Priority: `--agent` arg > `$AI_AGENT_NAME` > agent-specific env vars > `agent`.

### Step 3: Compute Project Name and Index

Extract project name via `basename "$(git rev-parse --show-toplevel)"`.
Scan parent directory for `{project}-{agent}-N` pattern, assign max(N)+1.

### Step 4: Determine Branch Name

| Input | Branch Name |
|---|---|
| No arguments | `wt/{agent}/{N}` |
| `--task "slug"` | `wt/{agent}/{N}-{slug}` |
| Explicit branch name | Use as-is |

If `--task` is given in Korean, translate to English slug first (lowercase,
hyphens, max 30 chars). Example: "로그인 기능" -> `login-feature`.

### Step 5: Determine Base Ref

Priority: `--base` arg > `origin/main` > `main`/`master` > current HEAD.

### Step 6: Create Worktree

git-crypt detection happens in Step 1.5. When active, resolve a key file via priority:
`$GIT_CRYPT_KEY_FILE` > `~/.config/git-crypt/<project>.key` > `~/.config/git-crypt/default.key`.

- **Key found (auto-unlock path)**: `git worktree add --no-checkout` first, then
  `git-crypt unlock <key>` inside the new worktree, then `git checkout -- .`.
  Encrypted files (`.env`, `.secrets/`) decrypt normally — full functionality.
- **Key not found (bypass path, backward-compatible)**: pass `-c filter.git-crypt.smudge=cat
  -c filter.git-crypt.clean=cat` to `git worktree add`, set worktree-local config
  to disable filters permanently. Encrypted files stay binary. Print a hint about
  `git-crypt export-key ~/.config/git-crypt/<project>.key` so next spawn can unlock.

If branch exists: `git worktree add <path> <branch>` (no `-b`).
If new branch: `git worktree add -b <branch> <path> <base_ref>`.

### Step 7: Log the Creation

Append structured log to `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log`.

### Step 8: Report and Move

Print result, then `cd` into the new worktree:

```
[OK] Worktree ready
  Path:   ../my-app-claude-1
  Branch: wt/claude/1
  Base:   origin/main
  git-crypt: unlocked via ~/.config/git-crypt/my-app.key

  Teardown after work is done:
    git push -u origin wt/claude/1
    git worktree remove ../my-app-claude-1
    git branch -d wt/claude/1
```

The `git-crypt` line only appears when the repo uses git-crypt. It shows either
`unlocked via <key path>` (auto-unlock path) or `disabled (no key file)` (bypass
path). When bypassed, the report also prints the `git-crypt export-key` hint.

The script cannot change the caller's cwd. Print the `cd` command as guidance,
then execute it yourself as the AI agent.
