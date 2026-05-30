# Step 5 — `conflict` 라벨 제거 (soft-fail)

Applies **only when `mergeable == MERGEABLE`**.

Check if `labels[].name` contains `"conflict"`. If so, remove via REST DELETE
(not `gh pr edit --remove-label`) — the latter can silent-fail on repos with
classic Projects attached due to GraphQL deprecation (#326 Bug B, same pattern
as `_gh_pr_edit_safe_label` fallback). 404 = label already absent → the
`||` branch surfaces a soft-fail warning, idempotent for the caller.

```bash
gh api -X DELETE "repos/{owner}/{repo}/issues/$PR_NUMBER/labels/conflict" \
    --repo "$TARGET_REPO" \
    >/dev/null 2>&1 \
  && echo "[OK] \`conflict\` 라벨 제거됨" \
  || echo "[WARN] \`conflict\` 라벨 제거 실패 — GitHub Actions 가 cover."
```

`{owner}/{repo}` placeholder + `--repo "$TARGET_REPO"` 조합을 쓰는 이유:
Step 1 의 `TARGET_REPO` 는 `git remote get-url` 결과(URL 형태)일 수
있어 `repos/$TARGET_REPO/...` 직접 보간 시 경로가 깨질 수 있다. `gh api`
의 `--repo` 플래그는 URL 과 `owner/repo` 양쪽 입력을 모두 안전하게
파싱한다.

If the label is absent, the `||` branch absorbs the 404 as a soft-fail
warning (idempotent).
