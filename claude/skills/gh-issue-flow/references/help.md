# gh:issue-flow — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number |
| 2 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh-issue-flow 16` — chain: implement → commit → PR for issue #16 on `origin`.
- `/gh-issue-flow 16 upstream` — same chain on `upstream` remote.
- `/gh-issue-flow -h` / `--help` / `help` — print this help.

## What this skill chains

This skill invokes **3 skills in sequence** (each step runs only if the previous succeeded):

1. **`gh:issue-implement <N> direct`** — reads the issue, edits files, runs tests. No human intervention.
2. **`gh:commit`** — creates a commit for the changes with a message derived from the conversation (follows the repo's commit style).
3. **`gh:pr`** — pushes the branch and opens a PR, auto-linking `Closes #<N>`.

If any step fails, the chain stops immediately. No automatic retry.
The final report shows which steps ran, which failed, and how to
resume manually.

## When to use this vs the atomic skills

Use `/gh-issue-flow` when:
- The issue is straightforward and you trust direct-mode to get it right.
- You want one command → PR URL output.

Use the atomic skills (`/gh-issue-implement` + `/gh-commit` + `/gh-pr`)
separately when:
- You want to review changes before committing.
- You need plan or brainstorming mode (gh:issue-flow uses direct only).
- The issue is complex and may need several commits before PR.

## Precondition

Same as `gh:issue-implement`: already inside a dedicated git worktree
on a feature branch with a clean working tree.

## What this skill will NOT do

- Run `gh:issue-implement` in `plan` or `brainstorming` mode — only
  direct. Use atomic skills manually for those modes.
- Retry failed steps.
- Roll back partial progress — if step 2 (commit) succeeded but step
  3 (PR) failed, the commit stays.
- Create a worktree or branch — user must be on a feature branch already.
