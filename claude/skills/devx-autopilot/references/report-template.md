# Report Templates

## 성공 ([OK])
    [OK] devx:autopilot 완료 — <spec 파일명>
    - 이슈:   #<N>  <issue-url>
    - 모드:   <sdd|inline>  (<reason>)
    - 구현:   <task N 완료 | inline 커밋 M>  · 검증 <테스트 결과·typecheck·lint>
    - PR:     #<PR>  <pr-url>  (Closes #<N>)
    - simplify: <적용 K건 | 이미 clean>
    - pr-reply: <응답 R건 | 아직 코멘트 없음(뒤늦은 봇 리뷰는 /gh-pr-reply 재실행)>
    Next: PR #<PR> 리뷰·머지 (autopilot 은 머지하지 않음)

## 실패 ([FAIL]) — 하드 실패 지점에서 정지
    [FAIL] devx:autopilot 정지 — Step <k> (<단계명>)
    - 완료: Step 0..<k-1> (<요약>)
    - 원인: <에러 요지>
    - 재개: <수동 재개 명령 — 예: 수정 후 `/devx:autopilot` 재실행 또는 해당 원자 스킬>
    남은 흔적: 커밋된 spec/plan · SDD 원장(.superpowers/sdd/) · 생성된 이슈 #<N>

## 스킵 ([SKIP])
    [SKIP] <단계> — <사유(예: pr-reply: 코멘트 없음)>
