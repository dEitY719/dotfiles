# gh:issue-create — Constraints

- `--assignee @me` 는 사용자 요청이 있을 때만 추가.
- 라벨/마일스톤 은 (a) 사용자 명시 또는 (b) Step 2.5 의 SSOT 기반
  자동 적용 일 때만 부착. 자동 적용 결과는 항상 `gh label list` 검증
  통과한 라벨만 유지 — 미존재 라벨 자동 생성 금지.
- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지.
- 사용자 지정 remote 가 없으면 즉시 실패.
- discussion log 를 2~3줄로 압축하지 말 것. `DISCUSSION_MODE=1`
  경로에서도 동일하게 적용된다 — Discussion 본문은 future-self 검색의
  SSOT 다.
- `--as-discussion` 는 명시적 사용자 의도 전용. AI 가 "이건 Discussion
  같음" 자동 판정해서 분기하지 말 것 (#619 Non-Goal). 잘못된 분기 =
  SSOT 분산.
- `--as-discussion` + `--label` / `--assignee` 동시 사용 시 후자를
  버리고 경고 1줄. `DISCUSSION_MODE=1` 일 때 Step 2.5 와 `gh issue
  create` 둘 다 우회.
- "should I create it?" 같은 확인 질문 금지.
