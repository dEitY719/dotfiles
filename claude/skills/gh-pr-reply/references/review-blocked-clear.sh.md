# gh:pr-reply Step 6.6 — Clear the `review-blocked` label (#1527)

Called from `SKILL.md` Step 6.6, after Step 6.5's board sync. `devx:pr-review-all`
labels a PR `review-blocked` when any reviewer lane returned a blocking verdict,
and `gh:pr-merge-train` refuses to merge while that label is on
(`gh-pr-merge-train/references/review-verdict-gate.md`). This step is what
releases it once the blockers have actually been addressed.

## When it runs

Only when **Step 6 pushed at least one fix commit** (`PUSHED_FIXES > 0`) **and**
at least one comment this run was classified `ACCEPT` or `ACCEPT-PARTIAL`. Both
halves matter:

- No push → nothing changed on the branch, so the blocking verdict still stands
  as written. All-`DECLINE` / all-`QUESTION` runs leave the label alone.
- A push with no accepted comment (an unrelated commit that happened to land)
  is not evidence a blocker was fixed.

Declining a blocker is a legitimate outcome — but it is a **human's** call to
override the gate, made by removing the label by hand. A skill that cleared it
on its own reasoning would be marking its own homework.

## What it does NOT do

It never adds `review-passed`. Clearing the block returns the PR to the
*unverified* state, not to a passing one — the train still skips it until a
fresh `devx:pr-review-all` run re-reviews the pushed fixes and re-labels. That
asymmetry is deliberate: a fix that introduces a new blocker must be caught by
review, not waved through by the act of fixing.

## The block

Soft-fail — warn on any error, never block the Step 7 report.
Use REST `DELETE`, **not `gh pr edit --remove-label`** — the latter silently
exits 1 on repos with classic Projects attached (#326 Bug B, the same
deprecation `_gh_pr_edit_safe_label` exists to absorb on the add path).
A 404 means the label was already absent, which is success for this step's
purposes — hence the idempotent `||` branch.

```bash
if [ "${PUSHED_FIXES:-0}" -gt 0 ] && [ "${ACCEPTED_COUNT:-0}" -gt 0 ]; then
    if GH_HOST="$TARGET_HOST" gh api -X DELETE \
        "repos/$TARGET_REPO/issues/$PR_NUMBER/labels/review-blocked" \
        >/dev/null 2>&1; then
        echo "[OK] \`review-blocked\` 라벨 제거됨 — 재리뷰 후 \`review-passed\` 가 붙어야 머지 가능 (#1527)"
    else
        echo "[WARN] \`review-blocked\` 라벨 제거 실패 또는 이미 없음 — 머지가 막히면 수동 확인"
    fi
fi
```

`gh api` takes no `--repo` flag, so the repo goes in the path (#658), and
`GH_HOST="$TARGET_HOST"` pins the server — without it a dual-host login deletes
a label on the wrong GitHub server with no error (#1403 / #1407). Step 1 bound
both from the `[remote]`'s URL.

## Re-review is the caller's job

`gh:pr-reply` does not re-dispatch the reviewers; it has no reviewer lanes.
On the `gh:issue-flow` path the operator (or the next `devx:pr-review-all` run)
supplies the re-review. Until then the PR sits unlabelled and the train skips
it — the fail-closed direction.
