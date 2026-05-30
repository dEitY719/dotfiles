# Step 5 — ai-metrics PR comment (soft-fail)

After the report, post a PR comment with ai-metrics (soft-fail — warn on
error, never block). `CONFLICT_FILES` is the count of files that had
`UU`/`AA`/`DU` conflicts in Step 3. When `GH_DISABLE_AI_METRICS=1`,
skip the comment entirely (issue #399):

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
HUMAN_H=$(echo "scale=2; $CONFLICT_FILES * 0.5" | bc)
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="---
<details>
<summary>🤖 AI Metrics · 📊 ~${TOKENS:-3000} tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-pr-resolve-conflict -->
📊 ~${TOKENS:-3000} tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-pr-resolve-conflict -->

</details>
컨플릭트 해결: ~$ELAPSED min · 사람: ~$HUMAN_H h ($CONFLICT_FILES files × 0.5 h)"
fi
```

On failure: `[WARN] ai-metrics comment failed — continuing.`
