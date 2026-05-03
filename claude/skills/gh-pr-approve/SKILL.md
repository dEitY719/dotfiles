---
name: gh:pr-approve
description: >-
  Review a GitHub PR, approve it when clean, request changes for blockers,
  or file follow-up issues for non-blocking concerns. Use for
  /gh-pr-approve, /gh:pr-approve, "approve PR 99", "#99 리뷰 승인", or
  "re-review requested". Self-authored PRs cannot be approved; they use
  analysis-only, comment-only, or admin-merge paths.
allowed-tools: Bash, Read, Grep, Glob
---

# gh:pr-approve - Review, Approve, or Handle Self-PR

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output it verbatim, then stop. Help is detected only at arg #1, so
`--self-ok -h` is parsed as unsupported `--self-ok` plus extra args.

## Step 1: Resolve + Pre-flight Gate (parallel)

Parse args first. Positional: `<pr-number>` and `<remote>` (default
`origin`). Flags may appear anywhere:

- `--self-record` - self-authored PR only; submit a comment-only record.
- `--admin-merge` - self-authored PR only; after a blocker-free review,
  run `gh pr merge --admin`.
- `--squash`, `--rebase`, `--merge` - optional strategy for
  `--admin-merge`; reject if used without it.

Reject unknown flags, `--self-record` with `--admin-merge`, and legacy
`--self-ok` with:
`--self-ok is not supported; GitHub blocks self-approval server-side.`

Fetch in parallel before reading the diff:

- `TARGET_REPO` from `git remote get-url <remote>`. Missing remote:
  list `git remote -v` and stop.
- PR number: explicit arg or `gh pr view --json number` on current
  branch; if neither exists, stop and ask.
- `ME=$(gh api user -q .login)`.
- PR JSON: `number,title,author,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,files`
- Prior reviews/comments on this PR by `ME`.
- `gh pr checks <N> --repo $TARGET_REPO`.

Stop on `state != OPEN`, draft, or required-check failure. Warn (but
do not stop) on `mergeable: CONFLICTING` — prepend a visible conflict
warning block to the review body and include it in the Step 5 report.
If `author.login == ME`, follow `references/self-pr-handling.md`.
If prior `ME` comments/reviews exist, use re-review mode: every prior
concern must be verified as fixed, tracked, or acceptably declined.

## Step 2: Fetch Review Material

In parallel: `gh pr diff <N>`, commits JSON, and the three comment
endpoints in `references/review-criteria.md`. Apply that checklist. In
re-review mode, map each prior concern to a fixing commit, tracking issue,
or acceptable author reply.

## Step 3: Classify Findings

Classify each concern as **BLOCKER**, **FOLLOW-UP**, or **PRAISE**. Praise
for approvals must cite concrete diff locations. Path selection:

- Non-self, 0 BLOCKER, 0 FOLLOW-UP: **4a** clean LGTM.
- Non-self, 0 BLOCKER, at least 1 FOLLOW-UP: **4b** approve with issues.
- Non-self, at least 1 BLOCKER: **4c** request changes.
- Self-authored PR: use the selected path from `references/self-pr-handling.md`.

## Step 4: Submit Review or Self-PR Action

Use `references/approval-templates.md` for commands and body templates.
Match the PR's dominant language.

- **4a** Submit `gh pr review --approve`.
- **4b** Create one issue per FOLLOW-UP, post one linking PR comment,
  then submit `gh pr review --approve`.
- **4c** Submit `gh pr review --request-changes`; blockers stay on the PR.
- Self-authored PR: never approve. Use analysis-only, `--self-record`, or
  `--admin-merge` exactly as specified in `references/self-pr-handling.md`.

## Step 5: Verify and Report

Re-fetch `reviewDecision` + `mergeStateStatus`; for `--admin-merge`, also
re-fetch `state` and `mergeCommit`. Report status, blocker/follow-up
counts, issue links, merge state, and PR URL. If the PR had
`mergeable: CONFLICTING`, include the conflict warning in the report.
For `--self-record`, confirm `reviewDecision` did not become `APPROVED`.

## Constraints

- Never approve without reading the diff, nor approve your own PR.
- GitHub blocks self-approval server-side; no token or flag can bypass it.
- Never accept `--self-ok`; it describes an impossible operation.
- Never fabricate follow-ups. Each issue must represent a defensible concern.
- Never merge a colleague's PR. `--admin-merge` is self-PR only.
- No labels/milestones unless `gh label list` confirms the label exists.
