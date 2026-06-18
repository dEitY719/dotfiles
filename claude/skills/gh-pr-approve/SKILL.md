---
name: gh:pr-approve
description: >-
  Review a GitHub PR, approve it when clean, request changes for blockers,
  or file follow-up issues for non-blocking concerns. Use for
  /gh-pr-approve, /gh:pr-approve, "approve PR 99", "#99 리뷰 승인", or
  "re-review requested". Self-authored PRs cannot be approved; they use
  analysis-only, comment-only, or admin-merge paths.
allowed-tools: Bash, Read, Grep, Glob, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "PR review judgment — diff analysis, BLOCKER/FOLLOW-UP/PRAISE classification, follow-up issue filing"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-approve - Review, Approve, or Handle Self-PR

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output it verbatim, then stop. Help is detected only at arg #1, so
`--self-ok -h` is parsed as unsupported `--self-ok` plus extra args.

## Step 1: Resolve + Pre-flight Gate (parallel)

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

Parse args first, then fetch PR metadata in parallel before reading the
diff. Read `references/arg-parsing.md` for the full flag table,
rejection rules, the parallel fetch list (incl. the REST-only
`rebaseable` field), and gate decisions (stop vs. warn). Self-PR
(`author.login == ME`) follows `references/self-pr-handling.md`; prior
`ME` comments trigger re-review mode (verify every prior concern fixed,
tracked, or acceptably declined).

## Step 2: Fetch Review Material

Decide path by diff size: `gh pr view <N> --repo $TARGET_REPO --json additions,deletions`.
When `additions + deletions` meets the threshold defined in
`references/large-diff-delegation.md`, dispatch an Explore subagent
following that file and skip loading the full diff into the main context;
use the returned BLOCKER/FOLLOW-UP/PRAISE summary as the input for
Step 3. Below the threshold, fall back to the inline path.

Inline path — in parallel: `gh pr diff <N>`, commits JSON, and the
three comment endpoints in `references/review-criteria.md`. Apply
that checklist. In re-review mode, map each prior concern to a
fixing commit, tracking issue, or acceptable author reply.

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

After submitting the review (any path), post a separate PR comment with
ai-metrics. Read `references/ai-metrics.md` for the exact command,
footer template, and the `GH_DISABLE_AI_METRICS=1` skip path (#399/#403).

## Step 5: Verify and Report

Re-fetch `reviewDecision` + `mergeStateStatus`; for `--admin-merge`, also
re-fetch `state` and `mergeCommit`. Report status, blocker/follow-up
counts, issue links, merge state, and PR URL. If the PR had
`mergeable: CONFLICTING` or `rebaseable: false`, include the conflict
warning in the report.
For `--self-record`, confirm `reviewDecision` did not become `APPROVED`.

## Constraints

- Never approve without reading the diff, nor approve your own PR.
- GitHub blocks self-approval server-side; no token or flag can bypass it.
- Never accept `--self-ok`; it describes an impossible operation.
- Never fabricate follow-ups. Each issue must represent a defensible concern.
- Never merge a colleague's PR. `--admin-merge` is self-PR only.
- No labels/milestones unless `gh label list` confirms the label exists.
