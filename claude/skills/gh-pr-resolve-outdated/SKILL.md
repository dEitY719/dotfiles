---
name: gh:pr-resolve-outdated
description: >-
  Clean-rebase a GitHub PR "out-of-date with the base branch" — no file
  conflicts. Use for /gh:pr-resolve-outdated, /gh-pr-resolve-outdated,
  "PR base out-of-date", "base 변경됐는데 sync". Conflicts →
  gh:pr-resolve-conflict; CI red → gh:pr-resolve-ci-fail.
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

Bind `TARGET_HOST` + `TARGET_REPO` from the remote's URL **before any `gh`
call** (`references/github-target.md`, #1403), check `gh` auth, and enforce the
hard preconditions (git repo · not default branch · clean tree · no in-progress
rebase) per `references/preflight.md`. Capture `BACKUP_SHA=$(git rev-parse HEAD)`.

## Step 2: Mergeable Triage

```bash
GH_HOST="$TARGET_HOST" gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json mergeable,mergeStateStatus,baseRefName,headRefName,url
```

Resolve the result via the action matrix in
`references/mergeable-triage.md` — only `MERGEABLE`/`BEHIND` proceeds to
Step 3; `CONFLICTING` delegates to `gh:pr-resolve-conflict` (exit 3),
already-clean is a no-op (exit 0 — idempotent, safe to re-run).

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

## Related Skills

Same PR-lifecycle slot, different verb — `gh:pr-resolve-conflict` (rebase that
walks each conflicting file) · `gh:pr-resolve-ci-fail` (read failing CI logs and
fix). Full list: `references/help.md` → "Related skills".
