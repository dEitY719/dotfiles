---
name: gh:pr-merge
description: >-
  Merge an approved GitHub PR — rebase by default, or squash/merge — without
  asking. Use for /gh:pr-merge, /gh-pr-merge, "PR 51 머지해", "squash merge", "#99
  머지". Refuses un-approved PRs, failing CI, drafts, conflicts — bypass is
  gh:pr-merge-emergency.
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

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and stop
(no API calls). That file also tables the positionals
`<pr-number> [rebase|squash|merge] [remote]` and the per-strategy guidance.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

- `pr-number` — required, positive integer. Missing/invalid → usage pointer, stop.
- `strategy` — default `rebase`; one of `rebase`/`squash`/`merge`. Other → print allowed values, stop.
- `remote` — default `origin`. Bind `TARGET_REPO` **and** `TARGET_HOST` from
  that one remote URL and `export GH_HOST` per `references/github-target.md`
  (#1403/#1407). Missing remote → list `git remote -v`, stop (no silent fallback).

## Step 2: Pre-flight (parallel)

Run in one message: `GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url`
and `GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO" --required`.

Then detect base-branch protection via
`GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/branches/<baseRefName>/protection"` (exit 0 →
present; 403/404 → absent). The exact protection-vs-`reviewDecision` behavior
table is in `references/strategy-selection.md` → "Branch protection detection".

**Hard stops** (full table in `references/strategy-selection.md` →
"Hard-stop decisions"): `state != OPEN`; `isDraft`; `mergeable ==
CONFLICTING`; `mergeStateStatus ∈ {BEHIND, BLOCKED, DIRTY}`; any required
check FAILURE/pending; `reviewDecision != APPROVED` → suggest
`/gh-pr-merge-emergency`. Conditional exception: protection **absent**
**AND** `reviewDecision == ""` → accept and print
`INFO: No branch protection on <baseRefName> — accepting empty reviewDecision.`
(a non-empty non-APPROVED value still stops).

## Step 2-B: Project Board Approval Gate (fail-closed)

Rule set + `gh-pr-approve` cross-link in `references/board-policy.md`. Run the
board approval gate per `references/board-approval-gate.sh.md` (fail-closed;
helper-missing → silent-skip; `GH_PR_MERGE_SKIP_BOARD_CHECK=1` to bypass). Runs
**before** Step 3; gates on the projectV2 board column.

## Step 3: Merge (no confirmation)

```bash
GH_HOST="$TARGET_HOST" gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

Flag mapping in `references/strategy-selection.md`. If `gh` returns
"merge method is not allowed", print the repo-settings guidance from
`references/strategy-selection.md` and stop. **Never** silently switch
strategies.

## Step 4: Sync Project Board Status

Run the two post-merge board reconciliations (PR card → Done; linked Issue cards
→ Done) per `references/project-board-sync.md` — paste the snippets verbatim
(that file also holds the failure modes and gating rationale). Both helpers
auto-detect repos without a projectV2 attachment and silently return; failures
hit stderr, never block the report.

After the board sync completes, post the ai-metrics PR comment per
`references/ai-metrics-comment.sh.md` (soft-fail; skip entirely when `GH_DISABLE_AI_METRICS=1`).

## Step 5: Fetch Merge SHA + Report

```bash
GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in `references/strategy-selection.md` → "Final report format").

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR; redirect to `gh:pr-merge-emergency`. Never bypass CI.
- Never swap strategy if the chosen one fails. Always `--delete-branch`.

## Related Skills

`gh:pr-approve` produces the approval this skill gates on · `gh:pr-merge-emergency`
is the admin-override path when approval cannot be obtained.
