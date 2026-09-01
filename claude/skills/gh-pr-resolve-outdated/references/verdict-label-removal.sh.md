# Step 5 — `review-passed` 재조정 (soft-fail, #1698)

Step 4 의 `git push --force-with-lease` 가 **성공했을 때만** 실행한다. Step 2 의
already-clean no-op(exit 0), `CONFLICTING` 위임(exit 3), 리베이스 충돌 중단
(exit 4), push 거부(exit 6) 경로에서는 head 가 그대로이므로 판정도 그대로
유효하다 — 아무것도 하지 않는다.

규칙의 SSOT 는 `shell-common/functions/gh_pr_edit_safe.sh` 헤더의
"Verdict-label invalidation — SSOT for issue #1563" 절이다. 요약: `review-passed`
는 **특정 head 커밋 하나**가 리뷰를 통과했다는 주장이다. force-push 는 그 커밋을
새 SHA 로 갈아치우므로, 콘텐츠가 실제로 바뀐 리베이스라면 주장이 거짓이 된다.
PR #1529 가 정확히 이 경로로 리뷰된 커밋 위에 force-push 하고도 라벨을 그대로 뒀다.

**#1698 이전에는 이걸 무조건 삭제로 처리했다** — 충돌 없이 SHA만 바뀌고 diff
내용은 100% 동일한 순수 rebase 에서도 라벨이 사라져, 리뷰할 새 내용이 하나도
없는데 `devx:pr-review-all` 풀 재리뷰(외부 CLI 4종)가 매번 필요했다(2026-09-01,
`gh:pr-merge-train` 세션에서 PR 4건 동시 발생). 지금은 rebase 전/후 diff 의
`git patch-id --stable` 를 비교해, 동일하면 라벨을 유지하고 새 SHA 로 freshness
marker 만 재발급한다 — 콘텐츠가 실제로 바뀐 경우엔 여전히 무조건 삭제한다.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/github-target.md` 대로 이미 export 한 상태여야 한다 (#1403).
`OLD_BASE_SHA` / `OLD_HEAD_SHA` 는 Step 3 이 fetch 전에 캡처해 둔 값(`BACKUP_SHA`
가 곧 `OLD_HEAD_SHA`), `NEW_BASE_SHA` / `NEW_HEAD_SHA` 는 이 Step 이 push 성공
직후 새로 읽는다.

## `review-blocked` 는 절대 건드리지 않는다

이 스킬은 base 를 따라잡을 뿐, 리뷰어가 제기한 블로커가 처리됐는지에 대한
**증거를 하나도 갖고 있지 않다**. 리베이스 뒤에 `review-blocked` 가 남아 있는
것은 버그가 아니라 안전한 방향이다. `gh:pr-reply` 는 Step 5(코멘트 전원 답변)를
완주하면 이 라벨을 무조건 뗀다(#1634) — 하지만 그건 그 스킬이 실제로 리뷰
코멘트에 답변했다는 별도의 증거를 갖고 있기 때문이다. 이 스킬은 그 증거가
없으므로 손대지 않는다.

`review-passed` / `review-blocked` 를 처음 **발급**하는 것도 이 스킬의 일이
아니다 — 유일한 발급자는 `devx:pr-review-all`(과 그 위임을 받는 `gh:pr-reply`,
#1636)이다. 아래의 "패치가 동일할 때" 경로가 하는 일은 발급이 아니라, 이미 발급된
판정을 새 SHA 에 대해 **재확인**하는 것뿐이다 — patch-id 가 다르면 그 재확인은
일어나지 않고 기존처럼 삭제된다.

## 명령

패치-id 비교와 라벨 재조정은 `shell-common/functions/gh_pr_resolve_outdated.sh`
의 `_gh_pr_resolve_outdated_reconcile_review_passed` 가 담당한다 — 이 문서는
로직을 다시 구현하지 않고 그 함수를 호출한다(#1524 규칙: 문서와 구현이 갈라질 수
없다). 내부적으로 다음 **두 조건이 모두** 참일 때만 유지+재발급한다 — patch-id
가 동일**하고**, `review-passed` 가 **지금** 그 PR 에 실제로 붙어 있을 때
(`_gh_pr_resolve_outdated_has_label`) — 그 외에는 전부 공유 헬퍼
`_gh_pr_drop_label` 로 삭제한다(REST DELETE 관용구 — `gh pr edit
--remove-label` 이 classic Projects 보드 repo 에서 GraphQL deprecation 으로
**조용히 실패**하는 문제(#326 Bug B)를 피한다). 두 번째 조건이 없으면 한
번도 리뷰된 적 없는 PR 이 우연히 patch-id 가 일치한다는 이유만으로
`review-passed` 를 새로 얻는 자가인증이 된다(PR #1699 review, codex
BLOCKER) — 유지+재발급 경로는 라벨을 **새로 발급**하지 않고, 이미 있는
라벨을 새 SHA 로 **재확인**할 뿐이다. 라벨 추가와 marker 게시는
`devx_pr_review_all_write_label` 을 거치지 않고 직접 한다 — 그 헬퍼는
반대쪽 `review-blocked` 를 첫 동작으로 삭제하므로, 아래 "`review-blocked`
는 절대 건드리지 않는다" 규칙을 어기게 된다(PR #1699 review, codex
BLOCKER).

`OLD_BASE_SHA` / `OLD_HEAD_SHA` 는 Step 3(rebase 전)이 캡처해 둔 값,
`NEW_BASE_SHA` / `NEW_HEAD_SHA` 는 이 Step 이 push 성공 직후 새로 읽는다.
Step 3/4 어디에서도 이 네 변수를 실제로 할당하는 코드가 없다면 아래 호출은
매번 patch-id 를 읽지 못해 무조건 삭제 경로만 타게 된다(PR #1699 review,
codex BLOCKER) — 그래서 호출 직전에 항상 명시적으로 할당한다:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_resolve_outdated.sh"

if [ -n "${WORKTREE_PATH-}" ]; then
    OLD_HEAD_SHA="$BACKUP_SHA"
    NEW_BASE_SHA=$(git -C "$WORKTREE_PATH" rev-parse "$REMOTE/$BASE")
    NEW_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
    _vl_result=$(_gh_pr_resolve_outdated_reconcile_review_passed \
        "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" \
        "$OLD_BASE_SHA" "$OLD_HEAD_SHA" "$NEW_BASE_SHA" "$NEW_HEAD_SHA" "$WORKTREE_PATH")
else
    OLD_HEAD_SHA="$BACKUP_SHA"
    NEW_BASE_SHA=$(git rev-parse "$REMOTE/$BASE")
    NEW_HEAD_SHA=$(git rev-parse HEAD)
    _vl_result=$(_gh_pr_resolve_outdated_reconcile_review_passed \
        "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" \
        "$OLD_BASE_SHA" "$OLD_HEAD_SHA" "$NEW_BASE_SHA" "$NEW_HEAD_SHA")
fi

case "$_vl_result" in
    *"label=kept"*)
        echo "[OK] \`review-passed\` 유지됨 — rebase 는 diff 내용 변경 없음(patch-id 동일), 새 SHA 로 재확인"
        ;;
    *)
        echo "[OK] \`review-passed\` 무효화됨(또는 애초에 없었음) — 최신 판정 없음"
        ;;
esac
```

Soft-fail 이다: 실패해도 Step 5 의 검증/보고는 그대로 진행한다.

## 호스트 고정

세 번째 인자 `TARGET_HOST` 가 `GH_HOST` 를 고정한다. 넘기지 않으면 dual-host
로그인에서 `gh` 가 `gh repo set-default` 로 폴백해 **에러 없이 엉뚱한 서버의
라벨을 지운다/붙인다** (#1403 / #1407). `gh api` 는 `--repo` 플래그를 받지 않으므로
repo 는 경로에 들어간다 (#658) — 공유 헬퍼가 대신 처리한다.
