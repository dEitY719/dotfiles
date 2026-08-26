# gh:issue-flow — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number |
| 2 | remote-name | `origin` | Git remote whose repo owns the issue. Threaded into every GitHub-touching sub-skill (#1405), so implement / commit / PR / review all target it |

## Usage

- `/gh-issue-flow 16` — chain: implement → commit → PR → devx:pr-review-all (agy ∥ codex ∥ /simplify quality gate + deferred pr-reply) → resolve conflicts → resolve out-of-date, for issue #16 on `origin`.
- `/gh-issue-flow 16 upstream` — same chain entirely on the `upstream` remote: the issue is read there, the commit's metrics land there, and the PR is pushed and opened there.
- `/gh-issue-flow -h` / `--help` / `help` — print this help.

## What this skill chains

This skill invokes **6 skills in sequence** (each step runs only if the previous succeeded), plus one non-fatal bash dispatcher call right after the 4th:

1. **`gh:issue-implement <N> direct <remote>`** — reads the issue, edits files, runs tests. No human intervention.
2. **`gh:commit <N> <remote>`** — creates a commit for the changes with a message derived from the conversation (follows the repo's commit style); the ai-metrics comment and board sync go to `<remote>`'s repo (#1405).
3. **`gh:pr <N> <remote>`** — pushes the branch to `<remote>` and opens the PR there, auto-linking `Closes #<N>` (#1405).
4. **`devx:pr-review-all` `<PR_NUM> <remote> --defer-reply 4`** — one delegated call runs the post-PR quality gate (soft-fail, parallel): agy ∥ codex second-opinion reviews (each skipped if its CLI is absent) ∥ built-in `/simplify` on the branch diff. Any simplify changes are committed + pushed synchronously before it returns (so they land before the rebase steps), and `/gh-pr-reply <PR_NUM>` is scheduled 4 minutes later — giving CI and reviewers time to post before the reply pass runs. Failures warn and continue — they never stop the chain.
   - **`aicron run merge-train`** (non-fatal, not a `Skill()` call) — fires the merge-train dispatcher once, in the background (not awaited — a real train launch can block minutes), so it checks the new PR immediately instead of waiting for the cron backstop. A missing binary is the only synchronously-observed failure, printed as a single `[WARN]` line; the dispatcher's own locking prevents a duplicate train.
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
