# Project Board Sync — push emergency-merged PR card to `Done`

After the admin merge succeeds, sync the PR's project-board card to `Done`.
The emergency path bypasses approval, but it still completes the same PR
lifecycle as a normal merge.

## Why no `--only-from` guard

`Done` is the terminal PR state after merge. Emergency merges may happen from
`In review`, `Approved`, or another in-flight status; all should move forward
to `Done`. Repeating the sync on an already-`Done` card is harmless.

## Snippet

Source the shared helper, then call it with the merged PR number:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" 2>/dev/null
_gh_project_status_sync pr <PR_NUMBER> "Done"
```

## Behavior

- **No projectV2 board attached** — the helper auto-detects zero project
  items and returns 0.
- **Sync failure** — the helper logs to stderr and returns 0; merge/audit
  success remains the primary outcome.
- **Opt-out per invocation** — set `GH_PROJECT_STATUS_SYNC=0` to skip sync.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared by PR and Issue
lifecycle skills. Do not inline-copy the GraphQL logic.
