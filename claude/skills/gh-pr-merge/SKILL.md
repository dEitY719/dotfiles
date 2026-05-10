---
name: gh:pr-merge
description: >-
  Merge an approved GitHub PR using one of three strategies — rebase
  (default), squash, or merge commit — without asking for confirmation.
  Use when the user runs /gh:pr-merge, /gh-pr-merge, or asks "PR 51
  머지해", "rebase merge", "squash merge", "#99 머지". Refuses to merge
  un-approved PRs (suggests gh:pr-merge-emergency instead), failing CI,
  draft PRs, or PRs with conflicts. Accepts
  `<pr-number> [rebase|squash|merge] [remote]`. Accepts `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep
---

# gh:pr-merge — Merge Approved PR (3 strategies)

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

Positional args: `<pr-number> [strategy] [remote]`.

- `pr-number` — required, positive integer. Missing/invalid → print
  usage pointer and stop.
- `strategy` — default `rebase`. Must be `rebase`, `squash`, or `merge`.
  Any other value → print allowed values and stop.
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>`
  via `git remote get-url <remote>` (parse `https://github.com/<o>/<r>.git`
  or `git@github.com:<o>/<r>.git`). Missing remote → list `git remote -v`
  and stop (no silent fallback).

## Step 2: Pre-flight (parallel)

Run in one message:
- `gh pr view <N> --repo $TARGET_REPO --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url`
- `gh pr checks <N> --repo $TARGET_REPO --required`

Then detect whether the base branch has protection rules (uses
`baseRefName` from the previous call):

- `gh api "repos/$TARGET_REPO/branches/<baseRefName>/protection"`
  - HTTP 200 → protection **present**; strict rules apply.
  - HTTP 403 (Free plan locks the feature) or 404 (not configured)
    → protection **absent**; empty `reviewDecision` is accepted
    (solo / personal repos where no one can approve your own PR).

**Hard stops** (see `references/strategy-selection.md` for exact table):
- `state != OPEN`
- `isDraft == true`
- `mergeable == CONFLICTING`
- `reviewDecision != APPROVED` → suggest `/gh-pr-merge-emergency` for admin bypass
  - Exception: protection **absent** (403/404) **AND** `reviewDecision == ""`
    → accept and print an informational line:
    `INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.`
    A non-empty non-APPROVED value (`REVIEW_REQUIRED`,
    `CHANGES_REQUESTED`) still stops regardless of protection.
- `mergeStateStatus ∈ {BEHIND, BLOCKED, DIRTY}`
- Any required check FAILURE or pending

## Step 2-B: Project Board Approval Gate (fail-closed)

Read `references/board-policy.md` for the rule set and the cross-link
to `gh-pr-approve`. This step runs **before** Step 3 and gates merges
on the team's projectV2 board column.

```bash
# Reuse the SSOT query helper — never inline a fresh GraphQL block.
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" 2>/dev/null

# Operator escape hatch: GH_PR_MERGE_SKIP_BOARD_CHECK=1
# Use for in-transition repos or one-shot ops (also leaves an audit signal:
# any reviewer can re-run gh-pr-merge without the env var to verify).
if [ "${GH_PR_MERGE_SKIP_BOARD_CHECK:-0}" != "1" ]; then
    BOARD_STATUS=$(GH_REPO="$TARGET_REPO" \
        _gh_project_status_query_current pr "$PR_NUMBER" 2>/dev/null)

    # Empty result = no projectV2 attached OR no read access.
    # Auto-skip in both cases — the merge gate is opt-in by board attachment.
    if [ -n "$BOARD_STATUS" ] && [ "$BOARD_STATUS" != "Approved" ]; then
        echo "Refusing to merge PR #$PR_NUMBER — board Status is \"$BOARD_STATUS\", required \"Approved\"."
        echo "  Have a teammate move the card to Approved, or use /gh-pr-merge-emergency for admin bypass."
        echo "  One-shot escape: GH_PR_MERGE_SKIP_BOARD_CHECK=1 /gh-pr-merge $PR_NUMBER"
        exit 2
    fi
fi
```

Failure modes:

- Board Status `!= Approved` (and non-empty) → exit 2, redirect to
  `/gh-pr-merge-emergency`.
- Empty Status (no projectV2 attached, or query failed) → silently
  continue. Repos without a board run on the legacy `reviewDecision`
  gate from Step 2 alone.
- `GH_PR_MERGE_SKIP_BOARD_CHECK=1` → skip Step 2-B entirely. Document
  the reason in the operator's commit message or Slack channel; this
  flag is for repos in transition, not a quiet-the-warning button.

## Step 3: Merge (no confirmation)

```bash
gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

Flag mapping in `references/strategy-selection.md`.

If `gh` returns "merge method is not allowed", print the repo-settings
guidance from `references/strategy-selection.md` and stop. **Never**
silently switch strategies.

## Step 4: Sync Project Board Status

Read `references/project-board-sync.md` for the failure modes and
gating rationale. Two reconciliations run after a successful merge:

(a) PR card → `Done` (closes the gap from #248 where the merged PR
    card stayed at `Approved`):

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" 2>/dev/null
GH_REPO="$TARGET_REPO" _gh_project_status_sync pr "$PR_NUMBER" "Done"
```

(b) Linked Issue cards from `closingIssuesReferences` → `Done`
    (boosts the best-effort `Item closed` builtin per #250). Use the
    `_gh_pr_closing_issue_numbers` helper instead of
    `gh pr view --json closingIssuesReferences` — older `gh` (≤ 2.45)
    rejects that field with "Unknown JSON field" (#264):

```bash
for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$TARGET_REPO"); do
    GH_REPO="$TARGET_REPO" _gh_project_status_sync issue "$_issue" "Done" \
        --only-from "Backlog,In progress,In review"
done
```

Both helpers auto-detect repos without a projectV2 attachment and
silently return. This step never blocks the report — failures are
logged to stderr and ignored.

After the board sync completes, post an ai-metrics PR comment (soft-fail).
When `GH_DISABLE_AI_METRICS=1`, skip the comment entirely (issue #399):

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="<!-- ai-metrics:gh-pr-merge tokens=${TOKENS:-2000} human_h=0.25 ai_min=$ELAPSED -->
PR merge: ~$ELAPSED min"
fi
```

On failure: `[WARN] ai-metrics comment failed — continuing.`

## Step 5: Fetch Merge SHA + Report

```bash
gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in
`references/strategy-selection.md` → "Final report format").

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR. Redirect to `gh:pr-merge-emergency`.
- Never swap to a different strategy if the chosen one fails.
- Always `--delete-branch` — head branches accumulate fast.
- Never bypass CI. Required checks must pass.
