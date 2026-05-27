---
name: gh:pr-resolve-outdated
description: >-
  Resolve a GitHub PR's "This branch is out-of-date with the base branch"
  banner (base has moved forward but there are no file conflicts) by
  rebasing onto the latest base and pushing with `--force-with-lease`.
  Use when the user runs /gh:pr-resolve-outdated, /gh-pr-resolve-outdated,
  or asks "PR base out-of-date", "base 변경됐는데 그냥 sync", "rebase 후
  force-with-lease push 해줘". Refuses the repo default branch, refuses
  plain `--force`, and delegates to [[gh-pr-resolve-conflict]] the moment
  rebase produces conflicts. Sister skill of [[gh-pr-resolve-conflict]]
  and [[gh-pr-resolve-ci-fail]] — same PR-lifecycle slot, different verb
  (clean rebase vs conflict resolution vs CI fix). Idempotent: already
  up-to-date PR is a no-op. Accepts `[pr-number] [remote]`; defaults to
  the PR attached to the current branch. Accepts `-h`/`--help`/`help`.
allowed-tools: Bash, Read
---

# gh:pr-resolve-outdated — Clean Rebase for Out-of-Date PR

## Help

Arg #1 `-h`/`--help`/`help` → read `references/help.md` verbatim, stop.
No API calls.

## Step 1: Parse Args + Preflight

Record `START_TS=$(date +%s)` immediately for Step 5.

Positional: `[pr-number] [remote]`. Both optional.

- `pr-number` — if omitted, auto-detect via `gh pr view --json
  number,headRefName,baseRefName,url,mergeable,mergeStateStatus` on
  the current branch. No PR → `[FAIL] no PR for current branch — pass
  PR# explicitly` + exit 2.
- `remote` — default `origin`. Resolve `TARGET_REPO` via
  `git remote get-url <remote>`; missing → `git remote -v` + exit 2.
- `gh` not authenticated → `[FAIL] gh CLI not authenticated — run gh
  auth login` + exit 5.

**Hard preconditions** (any fail → stop): inside a git repo · current
branch ≠ repo default (`[FAIL] cannot run on default branch` + exit 2)
· clean working tree (no auto-stash) · no in-progress rebase/merge/
cherry-pick. Capture `BACKUP_SHA=$(git rev-parse HEAD)` and print it
for `git reset --hard <sha>` recovery.

## Step 2: Mergeable Triage

```bash
gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json mergeable,mergeStateStatus,baseRefName,headRefName,url
```

| `mergeable` | `mergeStateStatus` | Action |
|---|---|---|
| `MERGEABLE` | `CLEAN`/`UNSTABLE` | `[OK] PR은 이미 up-to-date — nothing to do.` exit 0 (NF-1) |
| `MERGEABLE` | `BEHIND` | proceed to Step 3 (the case this skill handles) |
| `CONFLICTING` | — | `[FAIL] PR has merge conflicts — use /gh:pr-resolve-conflict` + exit 3 |
| `UNKNOWN` | — | GitHub still computing; print hint + exit 0 (retry later) |

`BLOCKED` alone (CI/approval pending) is not an out-of-date case — not handled here.

## Step 3: Fetch + Clean Rebase

```bash
git fetch "$REMOTE" "$BASE"
git rebase "$REMOTE/$BASE"
```

Rebase exits non-zero with conflicts → `git rebase --abort` immediately,
print `[FAIL] rebase produced conflicts — use /gh-pr-resolve-conflict
<PR_NUMBER>` + exit 4. The skill's premise is the no-conflict case;
the moment conflicts appear, hand off (never auto-guess — same policy
as the sister skill).

## Step 4: Push with `--force-with-lease`

Only after `git rebase` exits 0 and the tree is clean:

```bash
git push --force-with-lease "$REMOTE" HEAD
```

Never plain `--force`. Rejected (remote advanced while rebasing) →
`[FAIL] remote advanced — re-fetch and retry` + exit 6. **Never**
silently re-fetch and re-rebase — surface divergence so the user
decides (lost-update risk).

## Step 5: Verify + Report

```bash
gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json mergeable,mergeStateStatus,url
```

`mergeStateStatus ∈ {CLEAN, UNSTABLE, BLOCKED}` → banner cleared
(`BLOCKED` here = CI/approval pending, normal). Still `BEHIND` → push
didn't land; print PR URL, do not loop.

```
[OK] PR #<N> out-of-date 해소됨 · <new-sha> push 됨.
Next: /gh-pr-reply <N>  # 리뷰어 회신 또는 CI 결과 대기
```

ai-metrics footer follows the sister-skill pattern; skip when
`GH_DISABLE_AI_METRICS=1` (#399).

## Constraints

- Rebase-only. Never a merge commit.
- `--force-with-lease` only — never plain `--force`.
- Never run on the repo's default branch.
- Never auto-resolve conflicts — delegate to `gh:pr-resolve-conflict`
  and exit 4 the moment rebase produces them.
- Never retry a rejected `--force-with-lease` automatically.
- Never auto-stash. Clean tree required.
