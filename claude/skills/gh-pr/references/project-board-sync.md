# Project Board Sync — push the new PR's card to "In review" + linked Issues to "In progress"

After the PR is created, sync cards on the kanban so reviewers see the PR and
the linked Issues are at the right column without a manual drag.

## Why "In review" with no guard (PR card)

The PR lifecycle is linear. `In review` is the canonical resting state from
the moment a PR opens through approval, so unconditional sync is safe — there
is no prior status that should block the move.

## Why "In progress" for linked Issues (not "In review")

The GitHub builtin "Pull request linked to issue" (project workflow #3) moves
Issue cards to "In review" when a PR is opened with `Closes #N`. However, the
intended Issue lifecycle is `Backlog → In progress → Done` — Issues must never
visit "In review" or "Approved" (issue #289).

Calling `_gh_project_status_sync issue … "In progress"` immediately after the
PR is created corrects the builtin's transition. The `--only-from "Backlog,Ready"`
guard prevents regressing Issues that are already further along (e.g., an Issue
that was manually at "In progress" before the PR opened is left alone).

## Snippet

Source the shared helper, then call it with the new PR number:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" 2>/dev/null
_gh_project_status_sync pr "$PR_NUMBER" "In review"
for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$GH_REPO"); do
    _gh_project_status_sync issue "$_issue" "In progress" \
        --only-from "Backlog,Ready"
done
```

`GH_REPO` must be `owner/repo` (e.g. `dEitY719/dotfiles`). If unavailable,
resolve it via `gh repo view --json nameWithOwner --jq .nameWithOwner`.

## Behavior

- **No projectV2 board attached** — the helper auto-detects zero project items
  and silently returns 0. Nothing happens, no error.
- **PR body has no `Closes #N`** — `_gh_pr_closing_issue_numbers` returns
  nothing; the for-loop body never runs. PR sync still proceeds.
- **Opt-out per invocation** — set `GH_PROJECT_STATUS_SYNC=0` in the
  environment to skip both syncs entirely.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared between `gh:pr`,
`gh:pr-reply`, and other PR/issue lifecycle skills. Do not inline-copy the
snippet; always source the file so a single fix propagates everywhere.
