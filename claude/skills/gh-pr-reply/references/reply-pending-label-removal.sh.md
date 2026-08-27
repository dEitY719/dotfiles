# Step 6 — `reply-pending` 라벨 제거 (무조건, soft-fail)

Runs on **every** completion of this skill — 인라인 호출이든 지연 예약 호출이든,
수정 커밋이 있었든 없었든. 조건 분기 없음.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/target-resolution.md` 대로 이미 export 한 상태여야 한다 (#1403).

## 왜 무조건인가 (#1524)

`devx:pr-review-all` 의 `defer` 브랜치가 이 라벨을 붙인다. 붙어 있는 동안
`gh:pr-merge-train` 은 경과 시간과 무관하게 그 PR 을 건너뛴다 — 즉 **떼지 않으면
그 PR 은 영원히 머지되지 않는다**. 답변 패스가 끝났다는 사실을 아는 지점은 여기
하나뿐이므로, 제거도 여기 하나뿐이다.

`inline` 브랜치에서 온 호출은 애초에 라벨이 붙은 적이 없다. 그 경우 DELETE 는
404 를 돌려주고, `||` 가지가 그것을 soft-fail 경고로 흡수한다 — 멱등이므로
분기해서 "있는지 먼저 확인"할 이유가 없다.

## 명령

`gh pr edit --remove-label` 이 아니라 REST DELETE 다: 전자는 classic Projects
보드가 붙은 repo 에서 GraphQL deprecation 때문에 **조용히 실패**한다 (#326 Bug B,
`_gh_pr_edit_safe_label` 의 fallback 과 같은 이유).

```bash
GH_HOST="$TARGET_HOST" gh api -X DELETE \
    "repos/$TARGET_REPO/issues/$PR_NUMBER/labels/reply-pending" \
    >/dev/null 2>&1 \
  && echo "[OK] \`reply-pending\` 라벨 제거됨 — merge-train 이 이 PR 을 다시 본다" \
  || echo "[WARN] \`reply-pending\` 라벨 제거 실패/부재 — 붙은 적이 없었다면 정상(404)."
```

`gh api` 는 `--repo` 플래그를 받지 않으므로 repo 는 경로에 넣는다 (#658).
리터럴 `{owner}/{repo}` 를 남기면 `gh` 가 git remote 대신 `gh repo set-default`
로 폴백해서 **에러 없이 엉뚱한 서버의 라벨을 지운다** (#1403 / #1407).
`GH_HOST="$TARGET_HOST"` 가 그 서버를 고정한다.
