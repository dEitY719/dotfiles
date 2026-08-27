# gh:pr-reply Step 6.6 — Retire the stale verdict labels (#1527)

Called from `SKILL.md` Step 6.6, after Step 6.5's board sync. `devx:pr-review-all`
labels a PR `review-blocked` when any reviewer lane returned a blocking verdict,
and `gh:pr-merge-train` refuses to merge while that label is on
(`gh-pr-merge-train/references/review-verdict-gate.md`). This step is what
releases it once the blockers have actually been addressed.

## When it runs

All three must hold — each rules out a different way the clear would be wrong:

- **`PUSHED_FIXES > 0`** — no push means nothing changed on the branch, so the
  blocking verdict still stands exactly as written.
- **`ACCEPTED_COUNT > 0`** — a push carrying no `ACCEPT` / `ACCEPT-PARTIAL`
  comment (an unrelated commit that happened to land) is not evidence a blocker
  was fixed.
- **`DECLINED_COUNT == 0`** — one `DECLINE` anywhere in the run holds the label
  (#1527, PR #1529 codex review). The verdict is a single line for the whole
  review, not per-comment, so `gh:pr-reply` cannot tell which comment the
  reviewer considered blocking: "accepted one thing, declined another" is
  indistinguishable from "declined the blocker, fixed a nit". The rule is
  deliberately blunt and errs the way the gate itself does — declining an
  out-of-scope nit costs a manual label removal, the looser rule costs an
  unreviewed merge.

Declining a blocker is a legitimate outcome — but overriding the gate is a
**human's** call, made by removing the label by hand. A skill that cleared it on
its own reasoning would be marking its own homework.

## Two different labels, two different rules

`review-passed` and `review-blocked` are not symmetric, because they fail in
opposite directions.

**`review-passed` is dropped on ANY push** (`PUSHED_FIXES > 0`), unconditionally.
The label certifies *a reviewed head*, and a push replaces that head with one
nobody has reviewed. Leaving it on means the merge train's gate reads a pass
that no longer refers to the code it is about to merge — the exact hole the gate
exists to close (PR #1529 review, codex; the PR description had already flagged
it as a known gap, which is a second independent signal).

The cost is real and accepted: an unattended flow stalls whenever the reply pass
edits anything, until a fresh `devx:pr-review-all` re-labels. That is the same
trade the gate makes everywhere else — a stall is cheap and a human clears it
with one label; an unreviewed merge is not.

**`review-blocked` is dropped only on evidence the blockers were addressed** —
the three conditions below. Nothing here ever *adds* a label: clearing returns
the PR to *unverified*, never to passing. Only a re-review can mint
`review-passed`, so a fix that introduces a new blocker is still caught.

## The block

Soft-fail — warn on any error, never block the Step 7 report.
Use REST `DELETE`, **not `gh pr edit --remove-label`** — the latter silently
exits 1 on repos with classic Projects attached (#326 Bug B, the same
deprecation `_gh_pr_edit_safe_label` exists to absorb on the add path).
A 404 means the label was already absent, which is success for this step's
purposes — hence the idempotent `||` branch.

`pr_drop_label` treats a 404 as success — the label was already absent, which is
this step's desired end state, not a failure. Only a real error warns
(PR #1529 review, agy). `-i` keeps the status line that `gh api` otherwise
collapses into a bare non-zero exit, the same technique `gh-pr-merge-train`'s
`approval-gate.md` uses.

```bash
# Drop one label; 0 = gone (or never there), 1 = a real failure worth a warning.
pr_drop_label() {
    _out=$(GH_HOST="$TARGET_HOST" gh api -i -X DELETE \
        "repos/$TARGET_REPO/issues/$PR_NUMBER/labels/$1" 2>/dev/null)
    _st=$(printf '%s\n' "$_out" | sed -n '1s|^HTTP/[0-9.]* *\([0-9][0-9][0-9]\).*|\1|p')
    case "$_st" in
    2?? | 404) return 0 ;;
    *) return 1 ;;
    esac
}

if [ "${PUSHED_FIXES:-0}" -gt 0 ]; then
    # The head moved, so any prior pass no longer describes it.
    pr_drop_label review-passed ||
        echo "[WARN] \`review-passed\` 라벨 제거 실패 — 머지 전 수동 확인 (#1527)"

    if [ "${ACCEPTED_COUNT:-0}" -gt 0 ] && [ "${DECLINED_COUNT:-0}" -eq 0 ]; then
        if pr_drop_label review-blocked; then
            echo "[OK] verdict 라벨 정리됨 — 재리뷰가 \`review-passed\` 를 다시 붙여야 머지 가능 (#1527)"
        else
            echo "[WARN] \`review-blocked\` 라벨 제거 실패 — 머지가 막히면 수동 확인"
        fi
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
