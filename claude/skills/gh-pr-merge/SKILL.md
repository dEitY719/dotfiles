---
name: gh:pr-merge
description: >-
  Merge an approved GitHub PR using one of three strategies — rebase
  (default), squash, or merge commit — without asking for confirmation.
  Use when the user runs /gh:pr-merge, /gh-pr-merge, or asks "PR 51
  머지해", "rebase merge", "squash merge", "#99 머지". Refuses to merge
  un-approved PRs (suggests gh:pr-emergency-merge instead), failing CI,
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
- `remote` — default `origin`. Missing remote → `git remote -v` + stop.

## Step 2: Pre-flight (parallel)

Run in one message:
- `gh pr view <N> --repo $TARGET_REPO --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,url`
- `gh pr checks <N> --repo $TARGET_REPO --required`

**Hard stops** (see `references/strategy-selection.md` for exact table):
- `state != OPEN`
- `isDraft == true`
- `mergeable == CONFLICTING`
- `reviewDecision != APPROVED` → suggest `/gh-pr-emergency-merge` for admin bypass
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

## Step 4: Fetch Merge SHA + Report

```bash
gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in
`references/strategy-selection.md` → "Final report format").

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR. Redirect to `gh:pr-emergency-merge`.
- Never swap to a different strategy if the chosen one fails.
- Always `--delete-branch` — head branches accumulate fast.
- Never bypass CI. Required checks must pass.
