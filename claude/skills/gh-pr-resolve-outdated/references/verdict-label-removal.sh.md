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
없다). `gh:pr-resolve-conflict` Step 5 도 **같은 함수**를 부른다 — 두 스킬이
물리적으로 같은 동작(clean rebase + `--force-with-lease` push)을 하므로 로직도
하나다(#1700).

내부적으로 다음 **두 조건이 모두** 참일 때만 유지+재발급한다 — patch-id 가
동일**하고**, 그 PR 에 `<!-- review-verdict:review-passed:<old-head> -->`
마커가 신선하게 남아 있을 때(#1601 의 `_gh_pr_merge_train_review_passed_stale`
가 rc 0) — 그 외에는 전부 공유 헬퍼 `_gh_pr_drop_label` 로 삭제한다(REST DELETE
관용구 — `gh pr edit --remove-label` 이 classic Projects 보드 repo 에서 GraphQL
deprecation 으로 **조용히 실패**하는 문제(#326 Bug B)를 피한다).

두 번째 조건이 없으면 한 번도 리뷰된 적 없는 PR 이 우연히 patch-id 가
일치한다는 이유만으로 `review-passed` 를 새로 얻는 자가인증이 된다(PR #1699
review, codex BLOCKER) — 유지+재발급 경로는 라벨을 **새로 발급**하지 않고, 이미
발급됐던 판정을 새 SHA 로 **재확인**할 뿐이다.

**#1700 이전에는 이 두 번째 조건이 "지금 라벨이 붙어 있나"
(`_gh_pr_resolve_outdated_has_label`)였다.** 그게 버그였다 — 라벨은 다섯 개
drop 경로 중 아무나 떼어 갈 수 있는 파괴 가능한 상태라, **먼저 뗀 쪽이 나중
쪽의 재확인 자격까지 없애 버렸다**(실증 PR #1687: patch-id 완전 동일인데 복구
경로 없음). 마커는 어느 경로도 지우지 않으므로 그 경쟁 조건이 사라진다. 자가인증
가드는 오히려 **강해진다** — 마커의 존재 자체가 "실제로 발급된 적 있음"의
직접 증거이고, 마커 없는 PR 은 freshness 검사가 rc 2(ABSENT)로 떨어뜨린다.
`has_label` 은 함수로 남아 있지만 이제 **진단 보고 전용**이다(아래 토큰의
`prior=` 필드). 라벨 추가와 marker 게시는
`devx_pr_review_all_write_label` 을 거치지 않고 직접 한다 — 그 헬퍼는
반대쪽 `review-blocked` 를 첫 동작으로 삭제하므로, 아래 "`review-blocked`
는 절대 건드리지 않는다" 규칙을 어기게 된다(PR #1699 review, codex
BLOCKER).

`OLD_BASE_SHA` / `OLD_HEAD_SHA` 는 Step 3(rebase 전)이 캡처해 둔 값,
`NEW_BASE_SHA` / `NEW_HEAD_SHA` 는 이 Step 이 push 성공 직후 새로 읽는다.
Step 3/4 어디에서도 이 네 변수를 실제로 할당하는 코드가 없다면 아래 호출은
매번 patch-id 를 읽지 못해 무조건 삭제 경로만 타게 된다(PR #1699 review,
codex BLOCKER) — 그래서 호출 직전에 항상 명시적으로 할당한다. `OLD_BASE_SHA`
가 이미 존재하는 로컬 ref(`git merge-base` 결과)에서만 나오므로 obj store 에
없을 걱정은 없다 — Step 3 의 `git fetch` 이전에 캡처하지만, merge-base 자체가
이미 로컬에 있는 두 커밋만 비교하기 때문이다.

이 저장소의 다른 모든 `--worktree` 스니펫과 마찬가지로, `<path>` 는 실행
세션이 그 자리에 실제 경로 문자열을 대입하는 **자리표시자**이지 셸 변수가
아니다(agy 가 이전 리뷰에서 `$WORKTREE_PATH` 라는 정의된 적 없는 변수를
지적함 — PR #1699 review) — 그래서 Step 3/4 처럼 두 형태를 나란히 보여주고,
`--worktree` 로 호출됐는지는 실행 세션이 이미 알고 있으므로 그중 맞는 하나를
그대로 실행한다:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_resolve_outdated.sh"

OLD_HEAD_SHA="$BACKUP_SHA"
NEW_BASE_SHA=$(git rev-parse "$REMOTE/$BASE")
NEW_HEAD_SHA=$(git rev-parse HEAD)
_vl_result=$(_gh_pr_resolve_outdated_reconcile_review_passed \
    "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" \
    "$OLD_BASE_SHA" "$OLD_HEAD_SHA" "$NEW_BASE_SHA" "$NEW_HEAD_SHA")
```

`--worktree <path>` 모드에서는 세 `git` 호출 모두 `git -C "<path>" ...` 로,
마지막 인자로 `"<path>"` 를 추가한다:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_resolve_outdated.sh"

OLD_HEAD_SHA="$BACKUP_SHA"
NEW_BASE_SHA=$(git -C "<path>" rev-parse "$REMOTE/$BASE")
NEW_HEAD_SHA=$(git -C "<path>" rev-parse HEAD)
_vl_result=$(_gh_pr_resolve_outdated_reconcile_review_passed \
    "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" \
    "$OLD_BASE_SHA" "$OLD_HEAD_SHA" "$NEW_BASE_SHA" "$NEW_HEAD_SHA" "<path>")
```

두 형태 모두 결과는 같은 방식으로 읽는다:

```bash
case "$_vl_result" in
    *"label=granted"*"marker=reposted"*)
        echo "[OK] \`review-passed\` 유지됨 — rebase 는 diff 내용 변경 없음(patch-id 동일), 새 SHA 로 재확인"
        ;;
    *"label=granted"*"marker=failed"*)
        # 라벨 추가는 성공했지만 새 SHA 로의 marker 재게시가 실패한 경우 —
        # `devx_pr_review_all_write_label` 의 marker=failed 와 동일한 의미:
        # 다음 #1601 freshness 재검증에서 자연히 stale 로 self-heal 되지만,
        # 지금 이 tick 에서는 눈에 보이는 WARN 을 남긴다(soft-fail, 실패해도
        # Step 5 의 검증/보고는 그대로 진행).
        echo "[WARN] \`review-passed\` 유지는 됐으나 새 SHA marker 재게시 실패 — 다음 tick 에 stale 로 self-heal 됨"
        ;;
    *)
        echo "[OK] \`review-passed\` 무효화됨(또는 애초에 없었음) — 최신 판정 없음"
        ;;
esac
```

토큰은 patch-id 상태와 결과를 **각각** 보고한다(#1700 F-4):
`patch-id=<identical|changed|unreadable>` 와 `label=<granted|dropped>` 가
독립된 필드다. `label=granted` 에는 `prior=<present|absent>` 가 따라붙어,
평범한 #1698 유지(`present`)와 다른 경로가 이미 떼어 간 뒤의 #1700
재부여(`absent`)를 구분해 준다. `patch-id=identical label=dropped` 는
"내용은 같았지만 재확인 근거(마커)가 없었다"는 뜻이다 — 예전 판은 이 경우까지
`patch-id=changed` 로 뭉개 보고해서, 운영자가 "내용이 바뀌었으니 재리뷰가
필요하다"로 오독했다(#1700 결함 4).

Soft-fail 이다: 실패해도 Step 5 의 검증/보고는 그대로 진행한다.

## 호스트 고정

세 번째 인자 `TARGET_HOST` 가 `GH_HOST` 를 고정한다. 넘기지 않으면 dual-host
로그인에서 `gh` 가 `gh repo set-default` 로 폴백해 **에러 없이 엉뚱한 서버의
라벨을 지운다/붙인다** (#1403 / #1407). `gh api` 는 `--repo` 플래그를 받지 않으므로
repo 는 경로에 들어간다 (#658) — 공유 헬퍼가 대신 처리한다.
