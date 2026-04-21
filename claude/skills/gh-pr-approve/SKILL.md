---
name: gh:pr-approve
description: >-
  Review a GitHub PR a colleague requested you review, then either approve
  with an LGTM 👍 summary if flawless, or file remaining concerns as
  follow-up GitHub issues and link them from a PR comment. Use when the
  user runs /gh-pr-approve, /gh:pr-approve, or asks "PR 리뷰하고 승인해",
  "approve PR 99", "#99 리뷰 승인", "동료 PR 검토 후 approve", "re-review
  requested". Preserves the AI-driven issue workflow — non-blocking items
  become issues the team can triage automatically, real blockers get an
  explicit "Request changes" review. Project-agnostic; works in any repo
  reachable via gh CLI. Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep, Glob
---

# gh:pr-approve — Review → Approve or File Follow-up Issues

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Resolve + Pre-flight Gate (parallel)

Resolve context, then fetch pre-flight signals in parallel before
reading the diff:

- `TARGET_REPO` from `git remote get-url <remote>` (arg #2, default
  `origin`). Missing remote → list `git remote -v` and stop.
- PR number: explicit arg #1 → `gh pr view --json number` on current
  branch → stop and ask.
- `ME=$(gh api user -q .login)` for self-review / re-review checks.
- PR JSON: `number,title,author,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,files`
- Prior reviews/comments on this PR by `ME`
- `gh pr checks <N> --repo $TARGET_REPO`

**Stop conditions** (explain, don't approve): `state != OPEN` ·
`isDraft == true` · `author.login == ME` · `mergeable == CONFLICTING` ·
any required check failing.

If prior `ME` comments/reviews exist → **re-review mode**: primary goal
is verifying each prior concern was addressed by a subsequent commit.

## Step 2: Fetch Review Material + Review

In parallel: `gh pr diff <N>`, `gh pr view <N> --json commits`, and the
three comment endpoints in `references/review-criteria.md`. Apply that
file's checklist — correctness, conventions, security, performance,
tests. In re-review mode, map each prior concern to the commit that
resolved it (or flag "unresolved").

## Step 3: Classify Findings

Each concern is exactly one of **BLOCKER** (must fix before merge),
**FOLLOW-UP** (valid but non-blocking), or **PRAISE** (collect ≥1 for
approvals, anchored to a concrete diff location). See
`references/review-criteria.md` for the BLOCKER / FOLLOW-UP line.

Path selection:
- 0 BLOCKER, 0 FOLLOW-UP → **4a** clean LGTM
- 0 BLOCKER, ≥1 FOLLOW-UP → **4b** approve with follow-up issues
- ≥1 BLOCKER → **4c** request changes

## Step 4: Submit Review

Command shapes + body templates in `references/approval-templates.md`.
Match the language dominant in the PR (Korean PR → Korean review).

- **4a** `gh pr review --approve` with 👍 + 2–4 specific compliments.
- **4b** One `gh issue create` per FOLLOW-UP → one PR comment linking
  all of them → `gh pr review --approve`.
- **4c** `gh pr review --request-changes` listing each BLOCKER with a
  `file:line` pointer. Never silently file blockers as issues — they
  stay on the PR so the author's next push triggers natural re-review.

## Step 5: Verify and Report

Re-fetch `reviewDecision` + `mergeStateStatus`. If still BLOCKED despite
an approval, diagnose (another reviewer CHANGES_REQUESTED, required
check pending, branch out of date, reviewer lacks write access) and
include that in the report.

Print:
```
PR #<N>: <APPROVED|CHANGES_REQUESTED>
  Blockers:   <n>
  Follow-ups: <n>  → issues: #A, #B
  Merge:      <CLEAN|BLOCKED — <reason>>
  <PR URL>
```

## Constraints

- Never approve without reading the diff, nor approve your own PR.
- Compliments must reference concrete diff locations — no generic praise.
- Never fabricate follow-ups to look thorough. Each issue must represent
  a real concern you can defend.
- Never merge the PR — the author decides when to merge.
- No labels/milestones on follow-up issues unless `gh label list` confirms the label exists.
