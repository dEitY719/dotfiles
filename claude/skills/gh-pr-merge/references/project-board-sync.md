# Project Board Sync — reconcile linked Issue cards after merge

## Why this step exists

GitHub Projects v2 builtin workflows are best-effort only. The
`Item closed` workflow that should move closed Issue cards to `Done`
occasionally drops events, leaving Issue cards stuck at `In review` even
though the Issue itself is `CLOSED`. Concrete observation:
`dEitY719/dotfiles` Issue #239 stayed at `In review` after PR #241 merged
at 2026-04-28T03:24:34Z — 16 of 17 other Issues closed around the same
time on the same board moved to `Done` correctly, ruling out a setup
problem and pointing at transient delivery loss (issue #250).

`/gh-pr-merge` is the only natural surface that knows which Issues will
auto-close from a merge — they are listed in the PR's
`closingIssuesReferences` (Closes / Fixes / Resolves keywords). Adding a
post-merge reconciliation here closes the gap without depending on
builtin workflow reliability.

## How to call it

After Step 3 succeeds, fetch the PR's `closingIssuesReferences` and force
each linked Issue card to `Done`:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" 2>/dev/null

for _issue in $(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
                  --json closingIssuesReferences \
                  --jq '.closingIssuesReferences?[]?.number'); do
    GH_REPO="$TARGET_REPO" _gh_project_status_sync issue "$_issue" "Done" \
        --only-from "Backlog,In progress,In review"
done
```

The `--only-from` whitelist enforces three properties:

- An Issue already at `Done` (builtin fired this round) is left alone —
  no churn, no duplicate update.
- Issue cards never visit `Approved` per
  `docs/standards/github-project-board.md`; if one shows up there, it is
  a manual override worth investigating, so the helper skips rather than
  silently overwriting.
- Empty current Status (card never mounted on the board) is also
  skipped, so this never accidentally adds boards to repos that don't
  have one.

## When it does nothing

- PR body has no `Closes / Fixes / Resolves #N` →
  `closingIssuesReferences` is empty → loop body never runs.
- Repo has no projectV2 board attached → helper finds zero project items
  and silently returns 0.
- `GH_PROJECT_STATUS_SYNC=0` set in environment → opt-out, helper returns
  immediately.
- Issue card already at `Done` → helper skips per `--only-from` guard.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared with `gh:pr`,
`gh:pr-reply`, `gh:commit`, and `gh:flow`. Source the file each
invocation; do not inline-copy the snippet so a single fix propagates
everywhere.
