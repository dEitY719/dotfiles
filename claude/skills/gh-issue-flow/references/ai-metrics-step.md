# gh:issue-flow — Step 2.6: Post AI Metrics to Issue (soft-fail)

Runs only if Step 2.5.1 succeeded. Post a flow-level aggregate metrics
comment on the **linked GitHub Issue**. The PR body already carries the
per-step `<!-- ai-metrics:gh-pr -->` block written by `gh:pr`; this step
adds the total across all six sub-skills to the Issue so the Issue thread
is the single place to review full AI effort. (The post-PR quality gate
and deferred pr-reply are folded into Step 2.4 `devx:pr-review-all`, so its
row already covers that effort — there is no separate gate/schedule row.)
This step soft-fails — warn on any error but never block the flow.

a. Compute: `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`
   Track per-step timing by recording `STEP_TS=$(date +%s)` at the
   start of each sub-skill and computing its elapsed at the end:
   - `IMPL_MIN` — elapsed for Step 2.1 (gh:issue-implement)
   - `COMMIT_MIN` — elapsed for Step 2.2 (gh:commit)
   - `PR_MIN` — elapsed for Step 2.3 (gh:pr)
   - `REVIEW_MIN` — elapsed for Step 2.4 (devx:pr-review-all — the quality
     gate + deferred pr-reply scheduling)
   - `CONFLICT_MIN` — elapsed for Step 2.5 (gh:pr-resolve-conflict)
   - `OUTDATED_MIN` — elapsed for Step 2.5.1 (gh:pr-resolve-outdated)
   Any variable not yet computed defaults to `?` in the template.
b. Issue type: parse the conventional-commit prefix from the issue title
   fetched in Step 2.1 (e.g. `feat`, `fix`, `refactor`).
c. Human time: look up the issue type in `gh-issue-create`'s
   `references/metrics-baseline.md` (in the same skills directory).
   For `feat`, infer size from the implementation scope.
d. Token estimate: character count of (issue body + implementation file
   reads) ÷ 4, rounded to nearest 500. Minimum 1 000.
e. Post the aggregate comment on the linked issue (body template below).
   Skip the post entirely when `GH_DISABLE_AI_METRICS=1` (issue #399);
   the five sub-skills already honour the same env var, so a disabled
   run leaves zero ai-metrics artifacts on the issue or PR.
f. On failure: print `[WARN] ai-metrics comment failed (<reason>) — continuing.`

```bash
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    gh api "repos/$TARGET_REPO/issues/$ISSUE_NUMBER/comments" \
      -X POST \
      -f body="### gh-issue-flow 완료

| 단계 | AI 소요 |
|------|---------|
| gh-issue-implement | ~${IMPL_MIN:-?} min |
| gh-commit | ~${COMMIT_MIN:-?} min |
| gh-pr | ~${PR_MIN:-?} min |
| devx-pr-review-all (gate + pr-reply) | ~${REVIEW_MIN:-?} min |
| gh-pr-resolve-conflict | ~${CONFLICT_MIN:-?} min |
| gh-pr-resolve-outdated | ~${OUTDATED_MIN:-?} min |
| **합계** | **~$ELAPSED min** |

예상 사람 시간: ~$HUMAN_H h · 토큰: ~$TOKENS

---
<details>
<summary>🤖 AI Metrics · 📊 ~$TOKENS tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-issue-flow -->
📊 ~$TOKENS tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-issue-flow -->

</details>"
fi
```
