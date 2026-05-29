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
metadata:
  model_recommendation:
    tier: sonnet
    reason: "clean rebase + --force-with-lease push with rejected-push and conflict handoff; not pure read-only, but no deep reasoning"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-resolve-outdated — Clean Rebase for Out-of-Date PR

## Help

Arg #1 `-h`/`--help`/`help` → read `references/help.md` verbatim, stop.
No API calls.

## Step 1: Parse Args + Preflight

Record `START_TS=$(date +%s)` immediately for Step 5.

| Arg | Description | Default |
|---|---|---|
| `[pr-number]` | PR to resolve; auto-detect from branch if omitted | branch PR |
| `[remote]` | Remote owning the PR's repo | `origin` |

Resolve `TARGET_REPO`, check `gh` auth, and enforce the hard
preconditions (git repo · not default branch · clean tree · no
in-progress rebase) per `references/preflight.md` — full exit codes and
error templates there. Capture `BACKUP_SHA=$(git rev-parse HEAD)`.

## Step 2: Mergeable Triage

```bash
gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json mergeable,mergeStateStatus,baseRefName,headRefName,url
```

Resolve the result via the action matrix in
`references/mergeable-triage.md` — only `MERGEABLE`/`BEHIND` proceeds to
Step 3; `CONFLICTING` delegates to `gh:pr-resolve-conflict` (exit 3),
already-clean is a no-op (exit 0).

## Step 3: Fetch + Clean Rebase

```bash
git fetch "$REMOTE" "$BASE"
git rebase "$REMOTE/$BASE"
```

Rebase exits non-zero with conflicts → `git rebase --abort` immediately,
print `[FAIL] rebase produced conflicts — use /gh-pr-resolve-conflict
<PR_NUMBER>` + exit 4. Never auto-guess — hand off to the sister skill.

## Step 4: Push with `--force-with-lease`

Only after `git rebase` exits 0 and the tree is clean:

```bash
git push --force-with-lease "$REMOTE" HEAD
```

Never plain `--force`. Rejected (remote advanced while rebasing) →
`[FAIL] remote advanced — re-fetch and retry` + exit 6. Never silently
re-fetch — surface divergence so the user decides (lost-update risk).

## Step 5: Verify + Report

Re-read `--json mergeable,mergeStateStatus,url` and interpret per
`references/mergeable-triage.md` → "Step 5 verification".

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
- Never auto-resolve conflicts — delegate to `gh:pr-resolve-conflict` (exit 4).
- Never retry a rejected `--force-with-lease`; never auto-stash (clean tree required).
