# 구현 모드 자동 판정 (auto)

`--mode` 미지정 시 계획 문서(docs/superpowers/plans/…)를 읽고 판정한다.

## inline (직접 구현) 조건 — 아래를 모두 만족
- 계획의 Task 가 1개(또는 서로 의존 없는 사소한 2개 이하).
- 변경 파일 ≤ 2, 신규 파일 ≤ 1.
- 신규 API 엔드포인트·DB 마이그레이션·계약(openapi) 변경 없음.
- 병렬화 이득 없음(단일 문맥에서 5분 내 처리 가능).

## SDD (Subagent-Driven) 조건 — 하나라도 해당
- Task ≥ 3, 또는 다중 파일·다중 관심사.
- 신규 엔드포인트/마이그레이션/계약 변경 포함.
- 테스트 반복(TDD 루프)·리뷰 게이트가 값어치 있는 규모.

## 경계·로그
- 애매하면 SDD 로 기운다(안전). `--mode` 는 판정을 항상 덮어쓴다.
- 판정 후 반드시 1줄 로그: `mode=<auto→sdd|inline> reason=<Task N·files M·신규엔드포인트 유무>`.
- inline 이어도 Advisor 검증(테스트·typecheck·lint)은 SDD 와 동일하게 수행한다.
