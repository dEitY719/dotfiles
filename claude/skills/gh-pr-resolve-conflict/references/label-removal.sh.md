# Step 5 — `conflict` 라벨 제거 (soft-fail)

Applies **only when `mergeable == MERGEABLE`**.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/github-target.md` 대로 이미 export 한 상태여야 한다 (#1403).

Check if `labels[].name` contains `"conflict"`. If so, remove via REST DELETE
(not `gh pr edit --remove-label`) — the latter can silent-fail on repos with
classic Projects attached due to GraphQL deprecation (#326 Bug B, same pattern
as `_gh_pr_edit_safe_label` fallback). 404 = label already absent → the
`||` branch surfaces a soft-fail warning, idempotent for the caller.

```bash
GH_HOST="$TARGET_HOST" gh api -X DELETE \
    "repos/$TARGET_REPO/issues/$PR_NUMBER/labels/conflict" \
    >/dev/null 2>&1 \
  && echo "[OK] \`conflict\` 라벨 제거됨" \
  || echo "[WARN] \`conflict\` 라벨 제거 실패 — GitHub Actions 가 cover."
```

`gh api` 는 `--repo` 플래그를 받지 않으므로 repo 는 경로에 넣는다 (#658).
Step 1 이 `_gh_parse_owner_repo_url` 로 뽑은 `TARGET_REPO` 는 항상
`owner/repo` 형태라 `repos/$TARGET_REPO/...` 보간이 안전하다. 리터럴
`{owner}/{repo}` 를 남기면 `gh` 가 git remote 대신 자기 `gh repo set-default`
로 폴백하고, dual-host 로그인에서는 **에러 없이 엉뚱한 서버의 라벨을
지운다** (#1403 / #1407). `GH_HOST="$TARGET_HOST"` 가 그 서버를 고정한다.

If the label is absent, the `||` branch absorbs the 404 as a soft-fail
warning (idempotent).
