# Step 5 — `review-passed` 재조정 (soft-fail, #1698 / #1700)

Step 4 의 `git push --force-with-lease` 가 **성공했을 때만** 실행한다. push 가
거부됐거나(원격이 앞서 나감) 리베이스가 중단된 경로에서는 head 가 그대로이므로
판정도 그대로 유효하다 — 아무것도 하지 않는다.

규칙의 SSOT 는 `shell-common/functions/gh_pr_edit_safe.sh` 헤더의
"Verdict-label invalidation — SSOT for issue #1563" 절이다. 요약: 두 판정
라벨은 **특정 head 커밋 하나**에 대한 주장이라, 리베이스 force-push 는 리뷰된
커밋을 통째로 갈아치우므로 `review-passed` 를 거짓으로 만든다. 실제로 PR #1529
에서 이 스킬과 `gh:pr-resolve-outdated` 가 각각 리뷰된 커밋 위로 force-push 하고도
라벨을 그대로 뒀다.

## #1700 — 왜 무조건 삭제를 그만뒀나

#1698 은 이 재조정을 `gh:pr-resolve-outdated` 에만 넣었다. 근거는 "충돌 해소는
정의상 내용을 바꾼다" 였는데, **그 전제가 틀렸다**. 이 스킬의 Step 3 은 충돌이
**하나도 없이** 끝날 수 있다 — GitHub 이 PR 을 `CONFLICTING` 으로 표시해 이
스킬이 호출됐더라도, 그 사이 base 가 다시 움직였거나 판정 자체가 낡았으면
`git rebase` 는 그냥 exit 0 한다. 그 결과물은 `gh:pr-resolve-outdated` 가 이미
처리하는 것과 **물리적으로 같은 모양**(같은 diff, 새 SHA)인데 라벨 처리만
달랐다.

그래서 어느 스킬이 그 PR 을 먼저 집느냐가 결과를 갈랐고, 더 나쁘게는 **먼저 뗀
쪽이 나중 쪽의 재확인 자격까지 파괴**했다 — 재확인 조건이 "지금 라벨이 붙어
있나"였기 때문이다. 실증: PR #1687 은 patch-id 가 완전히 동일한 rebase 뒤 4초
만에 라벨을 잃고, 복구 경로 없이 외부 CLI 4종 전체 재리뷰만 남았다(이슈 #1700).

#1700 이후 재확인의 근거는 라벨이 아니라 **`review-verdict` 마커**다. 마커는
어느 경로도 지우지 않으므로 이 경쟁 조건 자체가 사라진다.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/github-target.md` 대로 이미 export 한 상태여야 한다 (#1403).
`OLD_BASE_SHA` 는 Step 2 가 `git fetch` **이전에** 캡처해 둔 값이고,
`BACKUP_SHA`(Step 1)가 곧 rebase 이전 head 다. `NEW_BASE_SHA` / `NEW_HEAD_SHA`
는 이 Step 이 push 성공 직후 새로 읽는다.

## `review-blocked` 는 절대 건드리지 않는다

이 스킬은 리뷰어가 제기한 블로커가 처리됐는지에 대한 **증거를 하나도 갖고 있지
않다** — 파일 충돌을 푼 것과 리뷰 지적을 반영한 것은 무관하다. 리베이스 뒤에
`review-blocked` 가 남아 있는 것은 버그가 아니라 안전한 방향이다. `gh:pr-reply`
는 Step 5(코멘트 전원 답변)를 완주하면 이 라벨을 무조건 뗀다(#1634) — 하지만
그건 그 스킬이 실제로 리뷰 코멘트에 답변했다는 별도의 증거를 갖고 있기
때문이다. 이 스킬은 그 증거가 없으므로 손대지 않는다.

라벨을 처음 **발급**하는 것도 이 스킬의 일이 아니다 — `review-passed` /
`review-blocked` 의 유일한 발급자는 `devx:pr-review-all`(과 그 위임을 받는
`gh:pr-reply`, #1636)이다. 아래 경로가 하는 일은 발급이 아니라, 마커가
증명하는 **이미 발급된 판정**을 새 SHA 에 대해 재확인하는 것뿐이다. 마커가
없는 PR — 즉 한 번도 리뷰된 적 없는 PR — 은 patch-id 가 우연히 일치해도
freshness 검사가 rc 2(ABSENT)를 돌려주므로 삭제 경로로 떨어진다(PR #1699
codex BLOCKER 의 자가인증 가드는 그대로 유효하다).

## 명령

패치-id 비교와 라벨 재조정은 `gh:pr-resolve-outdated` 와 **같은 함수**가
담당한다 — `shell-common/functions/gh_pr_resolve_outdated.sh` 의
`_gh_pr_resolve_outdated_reconcile_review_passed`. 두 스킬이 물리적으로 같은
동작(clean rebase + `--force-with-lease` push)을 하므로 로직도 하나여야 한다;
복제하면 #1700 이 고친 갭이 그대로 되살아난다(#1524 규칙). 함수는 원래 파일에
그대로 두고 직접 source 한다 — 이 저장소가 이미 쓰는 교차 파일 source 관례다
(그 파일 자신이 `gh_pr_merge_train.sh` / `gh_pr_edit_safe.sh` 를 같은 방식으로
가져온다). 삭제는 그 함수 안에서 공유 헬퍼 `_gh_pr_drop_label` 로 간다(REST
DELETE 관용구 — `gh pr edit --remove-label` 이 classic Projects 보드 repo 에서
GraphQL deprecation 으로 **조용히 실패**하는 문제(#326 Bug B)를 피한다).

이 저장소의 다른 모든 `--worktree` 스니펫과 마찬가지로, `<path>` 는 실행
세션이 그 자리에 실제 경로 문자열을 대입하는 **자리표시자**이지 셸 변수가
아니다 — `--worktree` 로 호출됐는지는 실행 세션이 이미 알고 있으므로 아래 두
형태 중 맞는 하나를 그대로 실행한다:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_resolve_outdated.sh"

NEW_BASE_SHA=$(git rev-parse "$REMOTE/$BASE")
NEW_HEAD_SHA=$(git rev-parse HEAD)
_vl_result=$(_gh_pr_resolve_outdated_reconcile_review_passed \
    "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" \
    "$OLD_BASE_SHA" "$BACKUP_SHA" "$NEW_BASE_SHA" "$NEW_HEAD_SHA")
```

`--worktree <path>` 모드에서는 두 `git` 호출 모두 `git -C "<path>" ...` 로,
마지막 인자로 `"<path>"` 를 추가한다:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_resolve_outdated.sh"

NEW_BASE_SHA=$(git -C "<path>" rev-parse "$REMOTE/$BASE")
NEW_HEAD_SHA=$(git -C "<path>" rev-parse HEAD)
_vl_result=$(_gh_pr_resolve_outdated_reconcile_review_passed \
    "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" \
    "$OLD_BASE_SHA" "$BACKUP_SHA" "$NEW_BASE_SHA" "$NEW_HEAD_SHA" "<path>")
```

다섯 번째 인자가 `BACKUP_SHA` 인 점에 주의한다 — `gh:pr-resolve-outdated` 가
`OLD_HEAD_SHA` 라고 부르는 값과 **같은 값**이고, 이 스킬은 Step 1 에서 이미
그 이름으로 캡처해 둔다. 헬퍼는 위치 인자만 보므로 이름 차이는 무관하다.

## 결과 읽기

```bash
case "$_vl_result" in
    *"label=granted"*"marker=reposted"*)
        echo "[OK] \`review-passed\` 유지됨 — rebase 는 diff 내용 변경 없음(patch-id 동일), 새 SHA 로 재확인"
        ;;
    *"label=granted"*"marker=failed"*)
        # 라벨은 붙었지만 새 SHA 로의 marker 재게시가 실패한 경우 —
        # 다음 #1601 freshness 재검증에서 자연히 stale 로 self-heal 되지만,
        # 지금 이 tick 에서는 눈에 보이는 WARN 을 남긴다.
        echo "[WARN] \`review-passed\` 유지는 됐으나 새 SHA marker 재게시 실패 — 다음 tick 에 stale 로 self-heal 됨"
        ;;
    *"label=failed"*)
        # 라벨 추가 자체가 실패한 경우 — 라벨은 붙지 않았고 marker 재게시는
        # 아예 시도되지 않았다(`marker=skipped`). 위 WARN 과 달리 "유지됐다"고
        # 말하면 안 된다(PR #1703 리뷰, agy FOLLOW-UP).
        echo "[WARN] \`review-passed\` 재확인 실패 — 라벨 추가 자체가 실패해 아무것도 부여되지 않음"
        ;;
    *)
        echo "[OK] \`review-passed\` 무효화됨(또는 애초에 없었음) — 최신 판정 없음"
        ;;
esac
```

토큰은 patch-id 상태와 결과를 **각각** 보고한다(#1700 F-4):
`patch-id=<identical|changed|unreadable>` 와 `label=<granted|dropped|failed>` 가
독립된 필드다. 유지/재부여 경로에는 `prior=<present|absent>` 가 따라붙어,
평범한 #1698 유지(`present`)와 다른 경로가 이미 떼어 간 뒤의 #1700
재부여(`absent`)를 구분해 준다. `patch-id=identical label=dropped` 는
"내용은 같았지만 재확인 근거가 없었다"는 뜻이고, 이 조합을
`patch-id=changed` 로 뭉개 보고하던 것이 #1700 이 고친 오독의 원인이다.
그 "근거 없음" 에는 마커 부재/stale 뿐 아니라 **지금 `review-blocked` 가 붙어
있는 경우**도 포함된다(PR #1703 리뷰, codex BLOCKER) — 같은 head 에 나중에
내려진 블로커 판정이 예전 `review-passed` 마커를 지우지는 않으므로, 마커만
보고 재부여하면 서로 모순되는 두 판정이 한 PR 에 공존하게 된다. 읽기만 할 뿐
`review-blocked` 를 붙이거나 떼지는 않는다 — 위 "절대 건드리지 않는다" 규칙은
쓰기에 대한 것이다.

`label=failed` 는 `marker=failed` 와 다르다: 후자는 라벨은 붙었는데 마커만
못 올린 경우이고, 전자는 라벨 추가 자체가 실패해 마커 게시까지 도달하지 못한
경우(`marker=skipped`)다.

Soft-fail 이다: 실패해도 Step 5 의 검증/보고는 그대로 진행한다.

## 호스트 고정

세 번째 인자 `TARGET_HOST` 가 `GH_HOST` 를 고정한다. 넘기지 않으면 dual-host
로그인에서 `gh` 가 `gh repo set-default` 로 폴백해 **에러 없이 엉뚱한 서버의
라벨을 지운다/붙인다** (#1403 / #1407). `gh api` 는 `--repo` 플래그를 받지 않으므로
repo 는 경로에 들어간다 (#658) — 공유 헬퍼가 대신 처리한다.
