# `review-passed` 게이트 — Step 6 (이슈 #1636, #1616 승계)

`gh:pr-reply` 는 BLOCKER 를 실제로 고친다. 그러니 "고쳐졌다"를 아는 스킬도
이 스킬이다. #1636 부터 `review-passed` 라벨은 **이 스킬이 직접** 붙인다 —
외부 AI CLI 재호출 없이, 자기 판단만으로.

이 문서가 그 절차의 SSOT 다. 구현체는
`shell-common/functions/gh_pr_reply_targeted_review.sh`.

## 여기까지 온 경로

- **#1616 이전** — 해제 규칙은 `ACCEPTED_COUNT > 0 && DECLINED_COUNT == 0`
  이라는 **전역 카운터 한 쌍**이었다. 같은 pass 안에서 *다른* 리뷰어의
  비블로킹 제안을 정당하게 DECLINE 하기만 해도 `review-blocked` 가 그대로
  눌러앉았다. 실제 사례 PR #1609 — codex 가 BLOCKER 2건(둘 다 수정), agy 가
  별도로 비블로킹 FOLLOW-UP 3건(전부 타당하게 거절). 라벨 하나 떼려고 5-lane
  `devx:pr-review-all` 전체 재실행이 필요했다.
- **#1616** — 질문을 리뷰어별·심각도별로 좁히고, 통과 판정은 여전히 외부
  `gh:pr-review --paths` 재호출에 맡겼다(NF-2, 자가 인증 금지).
- **#1636** — 그 재호출을 제거했다. 재호출 자체가 비용·지연·실패 지점이었고,
  `review-passed` 를 재획득하는 **유일한** 경로였기 때문에 실패할 때마다
  `gh:pr-merge-train` 이 반복적으로 막혔다.

## 원칙 두 개

- **심각도로 묻는다.** "이 pass 에 DECLINE 이 있었나"가 아니라 "**BLOCKER
  심각도 항목**이 하나라도 미해결로 남았나"를 묻는다. 비블로킹 FOLLOW-UP 의
  거절은 이 질문과 무관하다.
- **NF-2 는 이 경로에 한해 완화됐다(#1636).** 위 질문에 no 면 이 스킬이
  `review-passed` 를 **스스로** 붙인다. 남는 검증 연결고리는 분업이다 —
  **발견은 외부 AI**(`devx:pr-review-all` 이 여전히 매 PR 마다 fan-out 하고
  `review-blocked` 를 소유), **해소 확인은 `gh:pr-reply`**. fail-closed 방향은
  그대로다: 미해결 BLOCKER 가 하나라도 있으면 `review-passed` 는 없다.
  사용자의 명시적 트레이드오프 결정이며, `references/constraints.md` 가
  그 근거를 함께 적어 둔다.

## Step 3 — origin 토큰 기록 (F-1, #1616 그대로)

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
스트림은 **하나**다 — Step 6 과 Step 7 이 같은 `ORIGINS` 를 읽는다.

## Step 6 — 게이트와 적용 (F-2 / F-3 / F-4)

**Step 5 가 모든 코멘트에 답변을 마친 뒤에** 실행한다. 게이트는 "이 pass 가
BLOCKER 를 남겼나"를 묻는 것이므로, 아직 답하지 않은 코멘트가 있으면 물을
수 없다.

```bash
DECISION=$(printf '%s\n' "$ORIGINS" | _gh_pr_reply_review_passed_gate)
```

`DECISION` 은 정확히 한 토큰이다:

| 토큰 | 의미 | 후속 |
|---|---|---|
| `pass=no-blocker` | BLOCKER 심각도 항목이 애초에 없었음 | `review-passed` 적용 |
| `pass=blockers-resolved:<n>` | BLOCKER `<n>` 건이 전부 ACCEPT / ACCEPT-PARTIAL | `review-passed` 적용 |
| `hold=unresolved-blocker:<r>` | `<r>` 의 BLOCKER 가 DECLINE/QUESTION 으로 남음 | 미적용, `review-blocked` 유지, **쓰기 0회** |

BLOCKER 판정은 `_gh_pr_reply_severity_is_blocking` 을 쓰므로 `BLOCKER` /
`BLOCKING` / `블로커` 가 모두 블로킹으로 센다. `ACCEPT-PARTIAL` 은 해소로
친다(#1616 과 동일) — 부분 수용도 "고쳤다"는 답변이고, 남은 부분은 별도
FOLLOW-UP 으로 다시 제기되는 것이 이 저장소의 흐름이다.

`hold` 은 **첫 번째** 미해결 BLOCKER 에서 즉시 결정되고 그 리뷰어를 이름으로
남긴다. 하나로 충분하다 — NF-2 의 fail-closed 절반은 완화 대상이 아니다.

### 적용 (F-3 / F-4)

```bash
printf '%s\n' "$ORIGINS" |
    _gh_pr_reply_apply_review_passed "$PR_NUMBER" "$TARGET_REPO" "$TARGET_HOST" "$HEAD_SHA"
```

이 함수가 게이트를 직접 돌리고, `pass=` 일 때만 쓴다. 쓰기는 공유 프리미티브
`devx_pr_review_all_write_label` 로 간다 — `devx:pr-review-all` 이 쓰는 것과
**같은 경로**다:

- 반대 라벨 `review-blocked` 를 **먼저 무조건 삭제**한다. #1616 의 "해제"가
  여기서 함께 일어난다.
- add 는 `_gh_pr_edit_safe_label` 로만 한다 — bare `gh pr edit --add-label` 은
  classic Projects 가 붙은 저장소에서 조용히 exit 1 한다(#326).
- `HEAD_SHA` 4번째 인자는 `review-passed` 에 신선도 마커를 남긴다(#1601).
  **push 이후의 head** 여야 한다(NF-1) — 그래야 `gh:pr-merge-train` 의
  `_gh_pr_merge_train_review_passed_stale` 이 현재 head 와 대조해 통과시킨다.
- soft-fail: 라벨 실패는 WARN 한 줄이고 PR 은 무라벨로 남는다. 무라벨은
  머지 게이트에서 "미검증"으로 읽히므로 안전한 방향이다(기존 계약 그대로).

**`devx_pr_review_all_apply_label` 을 쓰지 않는다.** 그 함수는 리뷰어 판정
토큰 스트림을 받는다. 가짜 `lgtm` 줄을 만들어 먹이면 이 스킬의 자체 판단이
리뷰어 CLI 의 의견인 것처럼 코드에 기록된다 — #1636 이 명시적으로 배제한
단 하나의 선택지다. 완화는 코드에서 **보여야** 하고, 위장되면 안 된다.

### Step 7 문구

`_gh_pr_reply_apply_review_passed` 가 결과 한 줄을 그대로 출력한다
(내부적으로 `_gh_pr_reply_review_passed_report` 를 쓴다).

| 상황 | 문구 |
|---|---|
| BLOCKER 없음 | `[OK] 미해결 BLOCKER 없음(BLOCKER 항목 자체가 없음) — review-passed 적용 (외부 재검토 없음, #1636)` |
| BLOCKER 전부 해소 | `[OK] BLOCKER <n>건 전부 해소 — review-blocked 해제, review-passed 적용 (외부 재검토 없음, #1636)` |
| BLOCKER 미해결 | `[BLOCKED] <r> 의 블로커가 미해결 — review-passed 미부여, review-blocked 유지` |
| 라벨 미프로비저닝 | `[WARN] label \`review-passed\` missing in <repo> — provision it first (gh:label-bootstrap)` |
| 그 외 쓰기 실패 | `[WARN] PR #<n> review-passed 적용 실패 — 미검증으로 취급` |

## 제거된 것 (#1636)

- `Skill(gh:pr-review, "--ai <r> --paths <files> <PR> <remote>")` 재호출과
  그 `BASE_SHA..HEAD` 파일 스코프 계산 — 통과 판정에 더 이상 필요 없다.
  `gh:pr-review` 의 `--paths` 플래그 자체는 남아 있고, 사람이 스코프된
  2차 의견을 원할 때 그대로 쓸 수 있다.
- `_gh_pr_reply_targeted_lane_decide` / `_gh_pr_reply_lane_available` /
  `_gh_pr_reply_targeted_lane_report` — 재호출 전용 게이트였다.
  `_gh_pr_reply_review_passed_gate` / `_gh_pr_reply_review_passed_report` 가
  대신한다. `BLOCKING_REVIEWERS`(PR 의 `ai-review` 블록에서 구하던 집합)도
  더 이상 필요 없다: 질문이 "누가 막았나"가 아니라 "미해결 BLOCKER 가
  남았나"로 바뀌었기 때문이다.

## 회귀 테스트

- `tests/bats/functions/gh_pr_reply_targeted_review.bats` — 게이트 단위
- `tests/bats/skills/gh_pr_reply_review_passed_gate.bats` — 이 문서의 미러
  (`_fixtures/gh_pr_reply_review_passed_gate.sh`)
- `tests/bats/functions/devx_pr_review_all_verdict.bats` — 공유 쓰기
  프리미티브(`devx_pr_review_all_write_label`)와 producer 측 억제
