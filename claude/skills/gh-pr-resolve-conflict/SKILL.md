---
name: gh:pr-resolve-conflict
description: >-
  Resolve a GitHub PR's "This branch has conflicts that must be resolved"
  warning using rebase (never a merge commit), then push with
  `--force-with-lease`. Use when the user runs /gh:pr-resolve-conflict,
  /gh-pr-resolve-conflict, or asks "PR conflict 해결", "base 변경됐는데 rebase
  해줘", "리베이스로 컨플릭트 풀어". Refuses to run on the default branch,
  refuses plain `--force`, and never auto-guesses conflict content — the
  user drives each resolution. Sister skill of [[gh-pr-resolve-ci-fail]]
  and [[gh-pr-resolve-outdated]] — same PR-lifecycle slot, different
  verb (rebase-resolve vs read-logs-and-edit vs clean-rebase-no-conflicts). Accepts `[pr-number] [remote]`; defaults to the PR
  attached to the current branch. Accepts `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: opus
    reason: "rebase + conflict resolution with user-intent reasoning; high-risk --force-with-lease push, deep context tracking required"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-resolve-conflict — Rebase-based PR Conflict Resolution

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Preflight

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 5.

Positional args: `[pr-number] [remote]`. Both optional.

- `pr-number` — if omitted, auto-detect via
  `gh pr view --json number,headRefName,baseRefName,url,mergeable`
  on the current branch. No PR for the branch → stop.
- `remote` — default `origin`. Resolve `TARGET_REPO` via
  `git remote get-url <remote>`; missing → `git remote -v` and stop.

**Mergeable preflight** — immediately after resolving `PR_NUMBER`, run the
`gh pr view --json mergeable` short-circuit per `references/rebase-flow.md`
→ "Mergeable preflight" (`MERGEABLE` → already-clean skip; `UNKNOWN`/other → continue).

**Hard preconditions** (parallel batch; any fail → stop):
- inside a git repo
- current branch ≠ repo default (refuse to rebase `main`)
- working tree clean, OR auto-stash per `references/safety.md`
  (announce the stash before running it)
- no in-progress rebase/merge/cherry-pick

Capture `BACKUP_SHA=$(git rev-parse HEAD)` and print it so the user can
`git reset --hard <sha>` if anything goes wrong.

## Step 2: Fetch + Rebase

Run `git fetch "$REMOTE" "$BASE"` then `git rebase "$REMOTE/$BASE"`. Full
rebase mechanics, stash handling, and abort instructions live in
`references/rebase-flow.md`.

## Step 3: Conflict Resolution Loop

If `git rebase` exits non-zero with conflicts, run the per-commit loop in
`references/conflict-handling.md`: list `UU`/`AA`/`DU` paths, print the rebase
context, resolve each file with the user's intent (**never auto-guess** an
ambiguous conflict — ask), `git add`, then `git rebase --continue` and repeat.
That file also carries the abort guidance and squash suggestions for repeated
conflicts.

## Step 4: Push with `--force-with-lease`

Only after `git rebase` exits 0 and the working tree is clean, run
`git push --force-with-lease "$REMOTE" HEAD`.

Never plain `--force`. If `--force-with-lease` is rejected (someone
pushed while you rebased), stop and surface the upstream per
`references/rebase-flow.md` — do NOT silently re-pull-and-rebase.

## Step 5: Verify Mergeable + Report

Run `gh pr view <N> --repo "$TARGET_REPO" --json mergeable,mergeStateStatus,url,labels`.
If `mergeable == MERGEABLE` and `mergeStateStatus ∈ {CLEAN, UNSTABLE}`,
the warning is cleared. Print the final report from
`references/rebase-flow.md` → "Final report format". Still `CONFLICTING`
/ `BEHIND` → print the PR URL, name which side diverged, do not loop.

Helper policy (each soft-fail, applies only when `mergeable == MERGEABLE`):
- Remove the `conflict` label per `references/label-removal.sh.md`.
- Return the board status to `In review` per `references/board-sync-in-review.sh.md`.
- Post the ai-metrics PR comment per `references/ai-metrics-comment.sh.md` (soft-fail; skip when `GH_DISABLE_AI_METRICS=1`).

## Constraints

- Never introduce a merge commit. Rebase-only.
- Never use plain `git push --force`. `--force-with-lease` or stop.
- Never rebase onto the default branch from the default branch.
- Never auto-resolve ambiguous conflicts. Ask the user.
- Never retry a rejected `--force-with-lease` by fetching and re-rebasing on the user's behalf. Surface divergence and stop.
- Never skip Step 5. The whole point is clearing the PR warning.
