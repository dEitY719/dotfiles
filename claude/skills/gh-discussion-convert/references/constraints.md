# Constraints — gh:discussion-convert operating rules

- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지.
- 사용자 지정 remote 가 없으면 즉시 실패. Silent `origin` fallback 금지.
- Non-Ideas 카테고리는 정책상 변환 대상이 아니다. `--force-category`
  는 SSOT 갱신 없이 가드 자체를 제거하는 것이 아니라 1 회용 우회 전용.
- Steps 5 (createIssue) 이후 mutation 들 (6/7/8) 은 best-effort.
  하나 실패해도 새 Issue 는 이미 backlink 를 가진 채 존재하므로
  롤백 시도 금지 — 사람이 보강하도록 경고만 출력한다.
- 두 번 호출해도 새 Issue 가 두 개 생기지 않는다 (Step 4 idempotency
  check). 단, Discussion 본문이 backlink 마커 인덱싱 전에 호출되면
  중복이 가능 — 그래도 인간 검토가 마지막 방어선.
- "should I convert?" 같은 확인 질문 금지. Skill 실행이 컨펌이다.
