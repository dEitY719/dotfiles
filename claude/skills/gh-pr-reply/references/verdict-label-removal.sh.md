# 판정 라벨(`review-passed` / `review-blocked`) 무효화 — Step 6 (soft-fail)

`git push` 가 **성공했을 때만** 실행한다 (`PUSHED_FIXES > 0`). push 가 없었거나
건너뛴 경우 head 가 그대로이므로 판정도 그대로 유효하다 — 아무것도 하지 않는다.

규칙의 SSOT 는 `shell-common/functions/gh_pr_edit_safe.sh` 헤더의
"Verdict-label invalidation — SSOT for issue #1563" 절이다. 여기서는 되풀이하지
않는다. 요약만: 두 라벨은 **특정 head 커밋 하나**에 대한 주장이므로 head 를
전진시킨 스킬이 스스로 무효화해야 하고, 붙이는 쪽은 `devx:pr-review-all`
하나뿐이다 — 이 스킬은 **제거만** 한다.

Caller contract: `PR_NUMBER`, `TARGET_REPO`, `TARGET_HOST` 는 Step 1 이
`references/target-resolution.md` 대로 이미 export 한 상태여야 한다 (#1403).
`ACCEPTED_COUNT` / `DECLINED_COUNT` 는 Step 3 분류 결과의 집계로, Step 7 의
최종 요약 표(`references/final-summary.md`)가 쓰는 것과 **같은 카운터**다:

| 변수 | 정의 |
|---|---|
| `ACCEPTED_COUNT` | Step 3 에서 ACCEPT + ACCEPT-PARTIAL 로 분류된 코멘트 수 |
| `DECLINED_COUNT` | Step 3 에서 DECLINE 으로 분류된 코멘트 수 |

## 비대칭: `review-passed` 는 무조건, `review-blocked` 는 조건부

- **`review-passed`** — push 가 있었다는 사실만으로 무조건 제거한다. 리뷰된
  커밋이 더 이상 head 가 아니므로 "이 head 는 리뷰됨"이 거짓이 된다.
- **`review-blocked`** — `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0` 일 때만
  제거한다. 즉 최소 한 건을 실제로 반영했고 거절한 건이 하나도 없을 때 —
  제기된 블로커가 전부 처리됐다는 증거가 이 스킬 안에 있는 유일한 경우다.
  하나라도 DECLINE 이 있으면 블로커가 남았을 수 있으므로 라벨을 **남긴다**.
  남기는 쪽이 안전한 방향이다: 라벨 부재는 "차단 해제"가 아니라 "미검증"이라
  머지 게이트가 어차피 다시 리뷰를 요구한다.

## 명령

공유 헬퍼 `_gh_pr_drop_label` 을 쓴다 — REST DELETE 관용구를 스킬마다 복사하지
않기 위한 단일 구현체다. 404(라벨이 애초에 없음)는 **경고가 아니라 정상**으로
흡수되므로 "있는지 먼저 확인"하는 분기가 필요 없다. rc 1 일 때만 원문 에러가
stderr 로 넘어온다.

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"

if [ "$PUSHED_FIXES" -gt 0 ]; then
    if _vl_err=$(_gh_pr_drop_label "$PR_NUMBER" review-passed \
            "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
        echo "[OK] \`review-passed\` 무효화됨 — head 가 전진해 이전 판정은 만료"
    else
        echo "[WARN] \`review-passed\` 제거 실패 — 리뷰되지 않은 커밋에 판정이 남아 있다: ${_vl_err}"
    fi

    if [ "$ACCEPTED_COUNT" -gt 0 ] && [ "$DECLINED_COUNT" -eq 0 ]; then
        if _vl_err=$(_gh_pr_drop_label "$PR_NUMBER" review-blocked \
                "$TARGET_REPO" "$TARGET_HOST" 2>&1); then
            echo "[OK] \`review-blocked\` 제거됨 — 제기된 블로커를 전부 반영함"
        else
            echo "[WARN] \`review-blocked\` 제거 실패: ${_vl_err}"
        fi
    fi
fi
```

`2>&1` 로 잡는 것은 헬퍼가 rc 1 에서 흘려보내는 `gh` 원문 에러다 — 성공/404
경로에서는 비어 있다.

## 호스트 고정

네 번째 인자 `TARGET_HOST` 가 `GH_HOST` 를 고정한다. 넘기지 않으면 dual-host
로그인에서 `gh` 가 `gh repo set-default` 로 폴백해 **에러 없이 엉뚱한 서버의
라벨을 지운다** (#1403 / #1407). `gh api` 는 `--repo` 플래그를 받지 않으므로
repo 는 경로에 들어간다 (#658) — 헬퍼가 대신 처리한다.
