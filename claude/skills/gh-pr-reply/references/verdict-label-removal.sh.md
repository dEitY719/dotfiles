# 판정 라벨(`review-passed` / `review-blocked`) 무효화 — Step 6 (soft-fail)

`review-passed` 무효화는 `git push` 가 **성공했을 때만** 실행한다
(`PUSHED_FIXES > 0`). `review-blocked` 해제는 이제 push 여부와 무관하게
**Step 5 완주(코멘트 전원 답변) 자체가 조건**이므로 항상 실행한다 (#1634,
아래 "비대칭" 절 참고).

규칙의 SSOT 는 `shell-common/functions/gh_pr_edit_safe.sh` 헤더의
"Verdict-label invalidation — SSOT for issue #1563" 절이다. 여기서는 되풀이하지
않는다. 요약만: 두 라벨은 **특정 head 커밋 하나**에 대한 주장이므로 head 를
전진시킨 스킬이 스스로 무효화해야 한다.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/target-resolution.md` 대로 이미 export 한 상태여야 한다 (#1403).
`ORIGINS` 는 Step 3 이 `references/targeted-rereview.md` 대로 기록한
`<reviewer>:<severity>:<verdict>` 스트림이다.

## 비대칭: 둘 다 무조건 해제, 단 재차단 경로만 다르다

- **`review-passed`** — push 가 있었다는 사실만으로 무조건 제거한다. 리뷰된
  커밋이 더 이상 head 가 아니므로 "이 head 는 리뷰됨"이 거짓이 된다.
- **`review-blocked`** — Step 5 의 "코멘트 전원 답변" 계약을 완수했다는 사실
  만으로 이 스킬이 직접, 무조건 제거한다(#1634) — `PUSHED_FIXES` 나
  ACCEPT/DECLINE 비율과 무관하다. 전부 DECLINE 이라 push 가 없었던 경우(수정
  자체가 불필요하다고 판단한 경우)도 포함된다.

  #1616 이전에는 여기서 전역 카운터(`ACCEPTED_COUNT` / `DECLINED_COUNT`)로
  판단했다. 그 규칙은 *다른* 리뷰어의 비블로킹 제안을 정당하게 거절한 것만으로
  라벨을 붙잡아 뒀다 — PR #1609 가 그 사례다. #1616 은 리뷰어별·심각도별
  게이트(`references/targeted-rereview.md`)로 좁혔지만, 그 게이트조차 리뷰어
  자신의 BLOCKER 항목을 근거를 갖춰 정당하게 DECLINE 한 경우엔 여전히 라벨을
  붙잡아 뒀다 — PR #1630 이 그 사례다. #1634 는 그 잔여 게이트마저 제거한다.

  `PUSHED_FIXES > 0` 일 때는 그 뒤로도 타겟 재검토 lane 을 계속 돌린다 — 이제
  이 라벨을 "떼기 위해서"가 아니라, 독립 재검토가 비블로킹으로 돌아오면
  `review-passed` 를 저비용으로 얻는 승격 경로로만 쓴다. 그 재검토가 여전히
  BLOCKING 을 새로 보고하면 `devx_pr_review_all_apply_label` 이
  `review-blocked` 를 **새 근거로 재적용**한다 — 방금 무조건 뗀 것을 뒤집는
  게 아니라, 독립 검증이 실제로 찾아낸 문제이므로 NF-2(자가 인증 금지) 위반이
  아니다.

## 명령

공유 헬퍼 `_gh_pr_drop_label` 을 쓴다 — REST DELETE 관용구를 스킬마다 복사하지
않기 위한 단일 구현체다. 404(라벨이 애초에 없음)는 **경고가 아니라 정상**으로
흡수되므로 "있는지 먼저 확인"하는 분기가 필요 없다. rc 1 일 때만 원문 에러가
stderr 로 넘어온다.

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_reply_targeted_review.sh"

# review-blocked — 무조건, push 여부와 무관 (#1634).
if _vl_err=$(_gh_pr_drop_label "$PR_NUMBER" review-blocked \
        "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
    echo "[OK] \`review-blocked\` 해제됨 — 코멘트 전원 답변 완료"
else
    echo "[WARN] \`review-blocked\` 제거 실패: ${_vl_err}"
fi

if [ "$PUSHED_FIXES" -gt 0 ]; then
    if _vl_err=$(_gh_pr_drop_label "$PR_NUMBER" review-passed \
            "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
        echo "[OK] \`review-passed\` 무효화됨 — head 가 전진해 이전 판정은 만료"
    else
        echo "[WARN] \`review-passed\` 제거 실패 — 리뷰되지 않은 커밋에 판정이 남아 있다: ${_vl_err}"
    fi

    # review-passed 승격 후보 탐색 — review-blocked 는 이미 위에서 해제됐다.
    DECISION=$(printf '%s\n' "$ORIGINS" |
        _gh_pr_reply_targeted_lane_decide $BLOCKING_REVIEWERS)
fi
```

`2>&1` 로 잡는 것은 헬퍼가 rc 1 에서 흘려보내는 `gh` 원문 에러다 — 성공/404
경로에서는 비어 있다. `$DECISION` 처리(재검토 호출 / 유지 / 전체 재실행 안내)는
`references/targeted-rereview.md` § "Step 6 — 게이트와 lane" 이 SSOT 다.

## 절대 금지

이 스킬은 두 라벨 중 어느 것도 **직접 add 하지 않는다**. 비블로킹 재검토
판정이 실제로 돌아왔을 때 `devx_pr_review_all_apply_label` 이 쓰는 것이
유일한 경로이고, 재검토를 건너뛴 채 통과로 간주하는 분기는 없다(NF-2).

## 호스트 고정

네 번째 인자 `TARGET_HOST` 가 `GH_HOST` 를 고정한다. 넘기지 않으면 dual-host
로그인에서 `gh` 가 `gh repo set-default` 로 폴백해 **에러 없이 엉뚱한 서버의
라벨을 지운다** (#1403 / #1407). `gh api` 는 `--repo` 플래그를 받지 않으므로
repo 는 경로에 들어간다 (#658) — 헬퍼가 대신 처리한다.
