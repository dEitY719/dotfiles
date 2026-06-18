# Argument parsing — flags, rejections, fetch list

## Positional + flags

Positional: `<pr-number>` and `<remote>` (default `origin`). Flags may
appear anywhere:

- `--self-record` - self-authored PR only; submit a comment-only record.
- `--admin-merge` - self-authored PR only; after a blocker-free review,
  run `gh pr merge --admin`.
- `--squash`, `--rebase`, `--merge` - optional strategy for
  `--admin-merge`; reject if used without it.

## Rejections

Reject unknown flags, `--self-record` with `--admin-merge`, and legacy
`--self-ok` with:
`--self-ok is not supported; GitHub blocks self-approval server-side.`

## Parallel fetch (before reading the diff)

- `TARGET_REPO` from `git remote get-url <remote>`. Missing remote:
  list `git remote -v` and stop.
- PR number: explicit arg or `gh pr view --json number` on current
  branch; if neither exists, stop and ask.
- `ME=$(gh api user -q .login)`.
- PR JSON: `number,title,author,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,files`
- `REBASEABLE=$(gh api repos/$OWNER/$REPO/pulls/<N> --jq .rebaseable)` —
  the `rebaseable` field is REST-only; `gh pr view --json rebaseable`
  fails with `Unknown JSON field` because GraphQL has no such field.
- Prior reviews/comments on this PR by `ME`.
- `gh pr checks <N> --repo $TARGET_REPO`.

## Gate decisions

Stop on `state != OPEN`, draft, or required-check failure. Warn (but
do not stop) on `mergeable: CONFLICTING` or `rebaseable: false` —
prepend a visible conflict warning block to the review body and include
it in the Step 5 report.
If `author.login == ME`, follow `references/self-pr-handling.md`.
If prior `ME` comments/reviews exist, use re-review mode: every prior
concern must be verified as fixed, tracked, or acceptably declined.
