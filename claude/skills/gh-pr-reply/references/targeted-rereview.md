# 타겟 재검토 lane — `review-blocked` 저비용 해제 (Step 6, 이슈 #1616)

`gh:pr-reply` 는 BLOCKER 를 실제로 고친다. 그런데 #1616 이전의 해제 규칙은
`ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0` 이라는 **전역 카운터 한 쌍**이었다.
같은 pass 안에서 *다른* 리뷰어의 비블로킹 제안을 정당하게 DECLINE 하기만 해도
`review-blocked` 가 그대로 눌러앉았다.

실제 사례 PR #1609 — codex 가 BLOCKER 2건(둘 다 수정), agy 가 별도로 비블로킹
FOLLOW-UP 3건(전부 타당하게 거절). 제기된 블로커는 전부 처리됐는데도 라벨이
남았고, 라벨 하나 떼려고 5-lane `devx:pr-review-all` 전체 재실행이 필요했다.

이 문서가 그 전역 게이트를 대체하는 절차의 SSOT 다. 구현체는
`shell-common/functions/gh_pr_reply_targeted_review.sh`.

## 원칙 두 개

- **리뷰어별 · 심각도별로 묻는다.** "이 pass 에 DECLINE 이 있었나"가 아니라
  "원래 블로킹했던 그 리뷰어의 **블로킹 심각도 항목**이 전부 ACCEPT 됐나"를
  묻는다. 다른 리뷰어의 FOLLOW-UP 거절은 이 질문과 무관하다.
- **NF-2 — 자가 인증 금지.** 위 질문에 yes 여도 이 스킬은 `review-passed` 를
  스스로 붙이지 않는다. 붙일 자격은 **독립적인 재검토 호출이 실제로 비블로킹
  판정을 돌려줬을 때**에만 생긴다. 재검토를 건너뛰고 통과로 간주하는 경로는
  존재하지 않는다.

## Step 3 — origin 토큰 기록 (F-1)

Step 3 에서 코멘트 하나를 분류할 때마다 출처를 함께 남긴다:

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_reply_targeted_review.sh"

ORIGINS=$(
    _gh_pr_reply_origin_line codex '[BLOCKER]'   ACCEPT
    _gh_pr_reply_origin_line codex '[BLOCKER]'   ACCEPT
    _gh_pr_reply_origin_line agy   '[FOLLOW-UP]' DECLINE
)
```

- `<reviewer>` — 코멘트 작성자에 대응하는 `gh:pr-review` 의 `--ai` 값
  (`agy` / `codex` / `claude` / `opencode` / `hermes`). 그 외는 exit 2.
- `<severity>` — 리뷰어가 본문에 단 태그(`[BLOCKER]` / `[FOLLOW-UP]` /
  `[Suggestion]` …). 대괄호는 렌더링이라 헬퍼가 벗겨낸다.
- `<verdict>` — `ACCEPT` / `ACCEPT-PARTIAL` / `DECLINE` / `QUESTION`.

Step 7 의 리뷰어별 표는 이 스트림을 `_gh_pr_reply_origin_tally` 로 집계한다.

## Step 6 — 게이트와 lane (F-2 … F-7)

`BLOCKING_REVIEWERS` 는 `review-blocked` 를 유발한 라운드에서 **BLOCKING 판정을
낸 리뷰어 집합**이다. PR 코멘트의 `<!-- ai-review:<ai>:<sha> -->` 블록을
`devx_pr_review_all_lane_block` + `devx_pr_review_all_verdict` 로 읽어 구한다 —
이번 pass 의 항목에서 유추하지 않는다.

```bash
DECISION=$(printf '%s\n' "$ORIGINS" | \
    _gh_pr_reply_targeted_lane_decide $BLOCKING_REVIEWERS)
```

`DECISION` 은 정확히 한 토큰이다:

| 토큰 | 의미 | 후속 |
|---|---|---|
| `lane=<r1>[ <r2>]` | 모든 블로킹 리뷰어가 전부 해소됐고 CLI 도 실행 가능 | 아래 F-3 재호출 |
| `skip=unresolved-blocker:<r>` | F-6 — 블로킹 항목이 미해결/거절 | `review-blocked` 유지, **API 호출 0** |
| `skip=cli-unavailable:<r>` | F-7 — CLI 부재 또는 non-internal 환경 | 전체 재실행 안내 |
| `skip=no-blocking-reviewer` | 원래 블로킹한 리뷰어가 없음 | 할 일 없음 |

블로킹 리뷰어가 여럿일 때 **하나라도** 미해결이면 lane 은 아예 돌지 않는다:
해소된 리뷰어를 재검토해봐야 다른 리뷰어가 붙잡고 있는 라벨은 못 뗀다.
이번 pass 에 그 리뷰어의 블로킹 항목이 **하나도 없는** 경우도 미해결로 친다 —
"증거 없음"이 "해결됨"으로 읽히면 안 된다(NF-2 방향).

### F-3 — 재호출은 수정 파일로만 스코프

```bash
FIXED_PATHS=$(git diff --name-only "$BASE_SHA..HEAD")
# 파일마다 `--paths <path>` 를 반복한다 — 공백으로 이어붙인 문자열 하나를
# `--paths` 뒤에 통째로 넘기면(예: `--paths a.sh b.sh`) gh_pr_review_parse 가
# 첫 파일만 소비하고 다음 토큰을 PR 번호로 오인한다(PR #1629 review, codex
# BLOCKER). `--paths` 는 반복 호출마다 누적되도록 이미 구현돼 있으므로
# (gh_pr_review_paths_scope.bats "parse: --paths repeats and accumulates in
# order"), 파일 개수만큼 플래그를 반복하는 쪽이 유일하게 안전한 호출 형태다.
PATHS_ARGS=""
while IFS= read -r _p; do
    [ -n "$_p" ] && PATHS_ARGS="$PATHS_ARGS --paths $_p"
done <<EOF
$FIXED_PATHS
EOF
# 각 lane 리뷰어에 대해 (push 완료 후에):
Skill(gh:pr-review, "--ai <r>$PATHS_ARGS $PR_NUMBER $REMOTE")
```

파일명에 공백이 들어 있으면 이 반복 호출도, `--paths` 값 자체의 내부 저장
방식(공백-이어붙이기 문자열, `gh_pr_review.sh` 의 `paths=` 계약)도 이를
구분하지 못한다 — 알려진 한계다(PR #1629 review, agy FOLLOW-UP + codex
BLOCKER). 이 저장소의 네이밍 컨벤션(`snake_case`, 공백 금지, 최상위
`CLAUDE.md`)상 실제 파일명에 공백이 나타날 일이 없어 낮은 리스크로 판단해
현재는 손대지 않는다 — 컨벤션을 벗어난 파일이 실제로 나타나면 별도 이슈로
`paths` 의 내부 표현을 배열/개행-구분으로 바꾸는 작업이 필요하다.

- `--paths` 는 이슈 #1616 이 `gh:pr-review` 에 추가한 최소 옵션이다. `gh pr diff`
  결과를 파일 단위로 걸러 주므로 PR 전체가 아무리 커도 **small-diff inline
  경로**에 머문다.
- `gh:pr-review` 의 **large-diff delegation 경로(≥800줄)는 절대 타지 않는다.**
  그 경로에는 `<!-- ai-review:<ai>:<head-sha> -->` 를 찍지 않는 별도의 알려진
  버그가 있고(#1616 범위 밖), 마커가 없으면 판정 파서가 `unknown` 으로 읽어
  fail-closed 된다.
- **push 이후에** 호출한다. 그래야 마커의 head-sha 가 새 head 다(NF-1) —
  `devx_pr_review_all_verdict` / `_aggregate` 파서는 수정 없이 그대로 동작한다.
- `--paths` 가 아무 파일과도 매칭되지 않으면 `gh:pr-review` 는 exit 1 로 끊는다.
  빈 diff 를 리뷰시키면 LGTM 이 나오고, 그 LGTM 이 라벨을 떼기 때문이다.

### F-4 / F-5 — 판정을 라벨로

재호출이 남긴 코멘트에서 판정 토큰을 뽑아, `devx:pr-review-all` 과 **같은
쓰기 경로**로 넘긴다. 이 스킬은 라벨을 직접 add 하지 않는다:

```bash
printf '%s\n' "$VERDICTS" | \
    devx_pr_review_all_apply_label "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" "$HEAD_SHA"
```

- 판정 토큰은 **stdin** 으로 넘긴다 — positional 재확장은 zsh 워드 분할 버그로
  첫 lane 만 남기고 잘린다(#1527). 그 함수 헤더가 SSOT.
- 비블로킹(LGTM/CONCERNS) → `review-passed` 적용. 반대 라벨인
  `review-blocked` 는 그 함수가 **먼저 무조건 삭제**하므로 F-4 의 "해제"가
  여기서 함께 일어난다.
- 블로킹 → `review-blocked` 유지(재적용). Step 7 에 F-5 문구를 남긴다.
- 판정을 못 읽으면 label 이 비어 PR 은 **무라벨**로 남는다 — 통과로 승격되는
  경로가 없다는 뜻이다(NF-2).
- `HEAD_SHA` 4번째 인자는 `review-passed` 에 신선도 마커를 함께 남긴다(#1601).

### Step 7 문구

```bash
_gh_pr_reply_targeted_lane_report "$TOKEN"
```

`$TOKEN` 은 `verdict=<blocking|concerns|lgtm|unknown>` 또는 위 `skip=` 토큰
그대로다. 이 함수는 **출력만** 한다 — 라벨을 쓰지 않으므로 리포트 한 줄이
자가 인증으로 승격될 여지가 없다.

| 상황 | 문구 |
|---|---|
| 재검토 비블로킹 | `[OK] 타겟 재검토 통과 — review-blocked 해제, review-passed 적용` |
| 재검토 블로킹 (F-5) | `[BLOCKED] 타겟 재검토도 여전히 BLOCKING — 재수정 필요` |
| 판정 불명 | `[WARN] … 전체 devx:pr-review-all 재실행 필요` |
| 블로커 미해결 (F-6) | `[BLOCKED] <r> 의 블로커가 미해결 — review-blocked 유지, 타겟 재검토 미실행` |
| CLI 불가 (F-7) | `[WARN] <r> 리뷰어 CLI 를 이 환경에서 실행할 수 없음 — 전체 devx:pr-review-all 재실행 필요` |

## 회귀 테스트

- `tests/bats/functions/gh_pr_reply_targeted_review.bats` — 게이트 단위
- `tests/bats/functions/gh_pr_review_paths_scope.bats` — `--paths` 스코프
- `tests/bats/skills/gh_pr_reply_targeted_rereview.bats` — 이 문서의 미러
  (`_fixtures/gh_pr_reply_targeted_rereview.sh`)
