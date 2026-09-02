# `--review-pass` / `--review-block` — Manual Verdict Override (issue #1726)

The Step 6 gate (`references/review-passed-gate.md`) is the only path that
writes `review-passed` from this skill's own judgment, and it fail-closes:
no `review-passed` while a BLOCKER-severity item is unresolved, and none
without `ai-review` marker evidence. That is correct for the automatic
path, but it also means a PR the user has manually verified — through
channels this skill cannot see, e.g. a human re-read of the diff — has no
way back to `review-passed` short of editing the label by hand outside the
skill, which `references/constraints.md` forbids everywhere else.

These two flags are that way back: an **explicit, user-invoked** override,
not a second automatic path. The caller is asserting the verdict directly;
this skill does not evaluate anything.

## Recognizing the flags

`--review-pass` and `--review-block` may appear anywhere among the
positional args (`references/target-resolution.md`'s `<pr-number>
[remote]`), e.g. `/gh:pr-reply 123 --review-pass` or `/gh:pr-reply
--review-pass 123 upstream`. Strip them before parsing the remaining args
positionally — same treatment `-h`/`--help` already gets.

Both flags together is a usage error: print `--review-pass and
--review-block are mutually exclusive` and stop before Step 1 runs. Neither
label is touched.

## Step 1.5 — override and stop

Runs immediately after Step 1 (target resolution — needs `PR_NUMBER`,
`TARGET_REPO`, `TARGET_HOST`) and **before** Step 2. When either flag was
given, this replaces Steps 2–7 entirely: no comment fetch, no evaluation,
no fixes, no reply pass, no push, no ai-metrics comment.

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh"

HEAD_SHA=$(GH_HOST="$TARGET_HOST" gh pr view "$PR_NUMBER" \
    --repo "$TARGET_REPO" --json headRefOid -q .headRefOid)

# LABEL is "review-passed" for --review-pass, "review-blocked" for --review-block.
WRITE=$(devx_pr_review_all_write_label "$LABEL" "$PR_NUMBER" "$TARGET_REPO" \
    "$TARGET_HOST" "$HEAD_SHA")

devx_pr_review_all_report_write_result "$WRITE" "$PR_NUMBER" "$TARGET_REPO" "$LABEL" \
    "[OK] 수동 오버라이드: \`$LABEL\` 적용됨 (반대 라벨 제거 포함, 게이트 미평가, #1726)" \
    "[WARN] PR #$PR_NUMBER 수동 오버라이드 적용 실패 — 라벨 상태 확인 필요"
```

This is the same primitive `references/verdict-label-removal.sh.md`'s
"직접 add 금지" section names as the write-side of the automatic gate
(`devx_pr_review_all_write_label` → the shared REST-DELETE-then-POST
sequence, freshness marker included for `review-passed`). Reusing it here
means the override gets the same opposite-label cleanup, the same
`_gh_pr_edit_safe_label` add path (classic-Projects safe, #326), and the
same `#1601` freshness marker `gh:pr-merge-train` checks — no bespoke
label-write code, no drift from the automatic path's semantics.

## Step 7 (report)

Skipped along with the rest of Steps 2–7. Print only the one-line result
above, then stop. No summary table.

## Why this does not weaken NF-2 further

`references/constraints.md` already documents one relaxation of "never
self-certify" (#1636 — the automatic gate, still evidence- and
BLOCKER-gated). This is a second, narrower one: it requires the human
operator to explicitly type the flag on this exact invocation. It carries
no automatic trigger, no cron path, and no default — a plain `/gh:pr-reply
<N>` with neither flag runs the normal gated flow unchanged.
