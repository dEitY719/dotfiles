# gh:issue-flow — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number |
| 2 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh-issue-flow 16` — chain: implement → commit → PR → quality gate (codex review ∥ /simplify) → schedule pr-reply → resolve conflicts → resolve out-of-date, for issue #16 on `origin`.
- `/gh-issue-flow 16 upstream` — same chain on `upstream` remote.
- `/gh-issue-flow -h` / `--help` / `help` — print this help.

## What this skill chains

This skill invokes **6 skills in sequence** (each step runs only if the previous succeeded), plus a parallel post-PR quality gate:

1. **`gh:issue-implement <N> direct`** — reads the issue, edits files, runs tests. No human intervention.
2. **`gh:commit`** — creates a commit for the changes with a message derived from the conversation (follows the repo's commit style).
3. **`gh:pr`** — pushes the branch and opens a PR, auto-linking `Closes #<N>`.
   - **Post-PR quality gate (soft-fail, parallel).** Two Agent subagents run in one turn: codex second-opinion review (`gh:pr-review --ai codex`, skipped if `codex` is not installed) ∥ built-in `/simplify` on the branch diff. Any resulting simplify changes are committed + pushed before the rebase steps. Failures warn and continue — they never stop the chain.
4. **`devx:schedule` `--time 5 "/gh-pr-reply <PR_NUM>"`** — schedules a pr-reply run 5 minutes after PR creation, giving CI and reviewers time to post before the bot replies.
5. **`gh:pr-resolve-conflict` `<PR_NUM>`** — checks and resolves any merge conflicts in the new PR via rebase. Exits cleanly if the PR has no conflicts (expected for a freshly created branch).
6. **`gh:pr-resolve-outdated` `<PR_NUM>`** — clean rebase-sync when the base branch has moved forward with no conflicts. No-op if the PR is already up to date.

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
