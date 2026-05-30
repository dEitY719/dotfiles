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
metadata:
  model_recommendation:
    tier: haiku
    reason: "gh pr merge wrap with policy/preflight gate; bounded mutation, no deep reasoning"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-merge — Merge Approved PR (3 strategies)

## Help

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and stop. No API calls.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

Positional args: `<pr-number> [strategy] [remote]`.

- `pr-number` — required, positive integer. Missing/invalid → usage pointer, stop.
- `strategy` — default `rebase`; one of `rebase`/`squash`/`merge`. Other → print allowed values, stop.
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>` from
  `git remote get-url <remote>` (parse `https://github.com/<o>/<r>.git` or
  `git@github.com:<o>/<r>.git`). Missing remote → list `git remote -v`, stop (no silent fallback).

## Step 2: Pre-flight (parallel)

Run in one message: `gh pr view <N> --repo $TARGET_REPO --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url`
and `gh pr checks <N> --repo $TARGET_REPO --required`.

Then detect base-branch protection via
`gh api "repos/$TARGET_REPO/branches/<baseRefName>/protection"`
(exit 0 → present; 403/404 → absent). The exact protection-vs-
`reviewDecision` behavior table is in `references/strategy-selection.md`
→ "Branch protection detection".

**Hard stops** (full table in `references/strategy-selection.md` →
"Hard-stop decisions"): `state != OPEN`; `isDraft`; `mergeable ==
CONFLICTING`; `mergeStateStatus ∈ {BEHIND, BLOCKED, DIRTY}`; any required
check FAILURE/pending; `reviewDecision != APPROVED` → suggest
`/gh-pr-merge-emergency`. Conditional exception: protection **absent**
**AND** `reviewDecision == ""` → accept and print
`INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.`
(a non-empty non-APPROVED value still stops).

## Step 2-B: Project Board Approval Gate (fail-closed)

Rule set + `gh-pr-approve` cross-link in `references/board-policy.md`.
Run the board approval gate per `references/board-approval-gate.sh.md`
(fail-closed; helper-missing → silent-skip; `GH_PR_MERGE_SKIP_BOARD_CHECK=1`
to bypass). Runs **before** Step 3; gates on the projectV2 board column.

## Step 3: Merge (no confirmation)

```bash
gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

Flag mapping in `references/strategy-selection.md`. If `gh` returns
"merge method is not allowed", print the repo-settings guidance from
`references/strategy-selection.md` and stop. **Never** silently switch
strategies.

## Step 4: Sync Project Board Status

Run the two post-merge board reconciliations (PR card → Done; linked
Issue cards → Done) per `references/project-board-sync.md` — paste the
snippets verbatim (that file also holds the failure modes and gating
rationale). Both helpers auto-detect repos without a projectV2
attachment and silently return; failures hit stderr, never block the report.

After the board sync completes, post the ai-metrics PR comment per
`references/ai-metrics-comment.sh.md` (soft-fail; skip entirely when
`GH_DISABLE_AI_METRICS=1`).

## Step 5: Fetch Merge SHA + Report

```bash
gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in `references/strategy-selection.md` → "Final report format").

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR; redirect to `gh:pr-merge-emergency`. Never bypass CI.
- Never swap strategy if the chosen one fails. Always `--delete-branch`.
