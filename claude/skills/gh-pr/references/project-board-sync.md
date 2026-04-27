# Project Board Sync — push the new PR's card to "In review"

After the PR is created, sync its project-board card so reviewers see it on
the kanban without a manual drag.

## Why "In review" with no guard

The PR lifecycle is linear. `In review` is the canonical resting state from
the moment a PR opens through approval, so unconditional sync is safe — there
is no prior status that should block the move.

## Snippet

Source the shared helper, then call it with the new PR number:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" 2>/dev/null
_gh_project_status_sync pr "$PR_NUMBER" "In review"
```

## Behavior

- **No projectV2 board attached** — the helper auto-detects zero project items
  and silently returns 0. Nothing happens, no error.
- **Opt-out per invocation** — set `GH_PROJECT_STATUS_SYNC=0` in the
  environment to skip the sync entirely.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared between `gh:pr`,
`gh:pr-reply`, and other PR/issue lifecycle skills. Do not inline-copy the
snippet; always source the file so a single fix propagates everywhere.
