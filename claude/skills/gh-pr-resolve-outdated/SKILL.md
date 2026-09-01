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
| `[--worktree <path>]` | Run every git command in `<path>` instead of the current checkout | current checkout |

`--worktree <path>` makes `pr-number` **mandatory** — the caller
(`gh:pr-merge-train`) hands over a detached worktree, which has no current
branch to auto-detect a PR from. Everything else in this skill is unchanged;
without the flag the behaviour is exactly what it was.

Bind `TARGET_HOST` + `TARGET_REPO` from the remote's URL **before any `gh`
call** (`references/github-target.md`, #1403), check `gh` auth, and enforce the
hard preconditions (git repo · not default branch · clean tree · no in-progress
rebase) per `references/preflight.md` — that file also lists which of them
`--worktree` mode drops and why. Capture `BACKUP_SHA=$(git rev-parse HEAD)`
(in `--worktree` mode, `git -C "<path>" rev-parse HEAD`).

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

Before fetching, capture the PR's pre-rebase diff range for Step 5's
patch-id comparison (#1698) — `git merge-base` rather than the tracking
ref itself, so a locally stale `$REMOTE/$BASE` still yields the PR's real
diff start:

```bash
OLD_BASE_SHA=$(git merge-base HEAD "$REMOTE/$BASE")
```

Then:

```bash
git fetch "$REMOTE" "$BASE"
git rebase "$REMOTE/$BASE"
```

In `--worktree` mode all three become `git -C "<path>" ...`. `BACKUP_SHA`
from Step 1 is the pre-rebase head — Step 5 reuses it as `OLD_HEAD_SHA`.

A locally stale `$REMOTE/$BASE` (behind the PR's true base) only widens
`OLD_BASE_SHA`'s diff range with content the PR never touched — that pulls
`OLD_PID` and `NEW_PID` apart, never together, so the failure direction is
the same fail-safe one patch-id mismatch already takes: an extra
`devx:pr-review-all` re-run, never a wrongly-preserved `review-passed`
(PR #1699 review, codex round-3).

Rebase exits non-zero with conflicts → `git rebase --abort` immediately,
print `[FAIL] rebase produced conflicts — use /gh-pr-resolve-conflict
<PR_NUMBER>` + exit 4. Never auto-guess — hand off to the sister skill.

## Step 4: Push with `--force-with-lease`

Only after `git rebase` exits 0 and the tree is clean:

```bash
git push --force-with-lease "$REMOTE" HEAD
```

In `--worktree` mode, use the explicit refspec instead — a detached HEAD has
no branch for `git` to infer a destination from, and a bare `HEAD` would be
refused:

```bash
git -C "<path>" push --force-with-lease "$REMOTE" HEAD:refs/heads/$HEAD_REF
```

`HEAD_REF` is the `headRefName` Step 2 already read.

Never plain `--force`. Rejected (remote advanced while rebasing) →
`[FAIL] remote advanced — re-fetch and retry` + exit 6. Never silently
re-fetch — surface divergence so the user decides (lost-update risk).

A successful push means the reviewed commit is no longer head, so Step 5 must
invalidate the stale `review-passed` verdict. Record whether the push succeeded.

## Step 5: Verify + Report

Re-read `--json mergeable,mergeStateStatus,url` and interpret per
`references/mergeable-triage.md` → "Step 5 verification".

Only if Step 4's push actually succeeded, reconcile the `review-passed`
label per `references/verdict-label-removal.sh.md` (soft-fail) — a clean
rebase that reproduced the exact same diff (patch-id unchanged) keeps the
label and re-stamps its freshness marker for the new head; a rebase whose
content actually changed drops it as before (#1698). Never touch
`review-blocked` — this skill holds no evidence the blockers were addressed —
and never *add* `review-blocked`; `devx:pr-review-all` owns that (#1563).

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
- Never remove `review-blocked`, and never independently *decide* to add
  either label — `devx:pr-review-all` owns that. Reconciling `review-passed`
  after a successful push is mandatory (drop on real content change, keep +
  re-stamp on patch-id-identical rebase, #1698) — a stale verdict on an
  unreviewed head is the bug this fixes, and so is an unnecessary re-review
  of content nothing changed.
- Never create or remove the `--worktree` path. The caller owns its lifecycle.

## Related Skills

Same PR-lifecycle slot, different verb — `gh:pr-resolve-conflict` (rebase that
walks each conflicting file) · `gh:pr-resolve-ci-fail` (read failing CI logs and
fix). Full list: `references/help.md` → "Related skills".
