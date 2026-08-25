# gh:issue-create — Constraints

- `--assignee @me` 는 사용자 요청이 있을 때만 추가.
- 라벨/마일스톤 은 (a) 사용자 명시 또는 (b) Step 2.5 의 SSOT 기반
  자동 적용 일 때만 부착. 자동 적용 결과는 항상 `gh label list` 검증
  통과한 라벨만 유지 — 미존재 라벨 자동 생성 금지.
- 항상 `GH_HOST="$TARGET_HOST"` + `--repo "$TARGET_REPO"` — 암묵적 repo/host
  감지 의존 금지. `gh` 는 `--repo` 가 없으면 git 의 `origin` 이 아니라 자기
  `gh repo set-default` 를 따르므로, dual-host 로그인에서 에러 없이 다른
  서버에 이슈를 만든다 (#1403). 두 값은 Step 1 이 같은 remote URL 에서 뽑은
  쌍이어야 한다 — 절대 따로 구하지 말 것.
- 사용자 지정 remote 가 없으면 즉시 실패.
- Step 2.6/4.5 의존성 자동 링크는 항상 non-fatal — 이슈는 이미 만들어진
  뒤이므로 `addBlockedBy` 실패를 이유로 중단하거나 재시도하지 말고 리포트에
  경고 1줄만 남긴다. 라벨·본문 트레일러로 대체 fallback 하지 말 것 (#1424 NF-1).
- 선행 관계 트리거는 명시 문구 전용 — `#N 참고` / `#N 관련` 같은 단순 언급으로
  링크 생성 금지. 오탐 링크는 누락보다 나쁘다. `owner/repo#N` 은 v1 범위 밖
  이므로 경고 후 스킵 (#1424 NF-2).
- discussion log 를 2~3줄로 압축하지 말 것. `DISCUSSION_MODE=1`
  경로에서도 동일하게 적용된다 — Discussion 본문은 future-self 검색의
  SSOT 다.
- `--as-discussion` 는 명시적 사용자 의도 전용. AI 가 "이건 Discussion
  같음" 자동 판정해서 분기하지 말 것 (#619 Non-Goal). 잘못된 분기 =
  SSOT 분산.
- `--as-discussion` + `--label` / `--assignee` 동시 사용 시 후자를
  버리고 경고 1줄. `DISCUSSION_MODE=1` 일 때 Step 2.5 와 `gh issue
  create` 둘 다 우회.
- 미결이 남은 초안으로 `gh issue create` 를 호출하지 않는다 (Step 3.1 미결 게이트).
  `DISCUSSION_MODE=1` 만 예외 — RFC 는 `Open Questions` 가 산출물의 본질이다. 미결을
  본문에서 지워서 통과시키지 말 것: 결정으로 전환하거나 `--no-ask` 로 자율 결정하고
  `## 확정 사항 (Decisions)` 에 근거를 남긴다 (#1446).
- `--no-ask` 는 게이트를 끄는 플래그가 아니라 "묻지 않고 스스로 정한다" 는 플래그다.
  자율 결정도 `(자율 판단)` 표기와 근거 없이는 통과시키지 않는다.
- "should I create it?" 같은 확인 질문 금지.
