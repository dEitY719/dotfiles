# Project Board Sync — push PR card to `Approved` after replies

## Why this step exists

After all replies are posted, push the PR's project-board card to
`Approved` so the kanban reflects "review round closed, awaiting merge".

GitHub's `Code review approved` built-in workflow only fires when a
reviewer submits an `APPROVED` review — and on solo repos the PR author
cannot self-approve their own PR, so without this step the card never
leaves `In review` (or `Backlog` if the worker missed the initial
`Backlog → In review` transition). `/gh-pr-reply` closes that gap.

## How to call it

Source the shared helper (it lives in
`shell-common/functions/gh_project_status.sh`) and call it with the
PR number, guarding the transition with `--only-from` so the card
never regresses from `Done` (e.g. when the user invokes
`/gh-pr-reply` on an already-merged PR by mistake):

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" 2>/dev/null
_gh_project_status_sync pr <PR_NUMBER> "Approved" --only-from "Backlog,In progress,In review"
```

## When it does nothing

If the repo has no projectV2 board attached (auto-detected — the helper
finds zero project items and silently returns 0), nothing happens. Opt
out per-invocation with `GH_PROJECT_STATUS_SYNC=0`.
