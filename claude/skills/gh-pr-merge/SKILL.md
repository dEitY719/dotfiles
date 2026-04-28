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
