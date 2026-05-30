# verify — 본문 템플릿

라이브 검증 추적 이슈에 사용한다. 코드 변경이 아니라 검증 시도·차단·
재개·재현가능성 자체를 SSOT 로 관리한다. 장시간 e2e, 사람 개입이 필요한
staged rollout, context 단절을 가로지르는 다회 시도가 대표 케이스다.

## 타이틀

```
verify[(<scope>)]: <한 줄 요약 — "무엇의 무슨 검증을 추적하는가">
```

예) `verify(dev-deploy): #1240 Sparkling Autofill e2e 검증 추적 — #1245 + #1247 연쇄 회귀 차단·재개 SSOT`

## 본문 골격

> Verification Tracking Issue — 본 이슈는 신규 fix 의 *적용·관찰·재현
> 가능성* 자체를 SSOT 로 추적한다. 코드 변경이 아니라 사람·환경·workflow
> 조작 결과를 모은다. 세션 단절 (context 유실) 시 다음 세션이 본 이슈만
> 읽고 정확한 다음 단계로 이어갈 수 있어야 한다.

```markdown
## TL;DR
<1~3줄>

## Verification Goal
<통과 기준의 측정 가능한 정의 (status 200, env 6줄, 응답 필드 N개 등)>

## 시도 이력
### N차 시도 (날짜·시각 KST) — <한 줄 요약>
<무엇을 했고, run/PR 링크, 결과>

## 현재 상태 (Current Blocker)
<지금 이 순간 진행을 막는 사유. 차단 해제 조건 명시>

## 재개 절차
<다음 세션이 그대로 따를 수 있는 self-contained bash + 기대 출력>

## 진행 사항 추적
<코멘트 추가 규칙: 새 시도 결과, 새 follow-up issue 링크, 환경 변경>

## 참고 (References)
<SSOT 문서, 관련 issue/PR, 환경, 사고에서 학습한 운영 주의사항>
```

## 섹션별 작성 가이드

- **TL;DR** — 무엇의 무슨 검증을 왜 추적하는지 1~3줄. 본체 fix issue
  번호를 명시해 cross-issue 연결을 잃지 않는다.
- **Verification Goal** — "통과" 를 측정 가능하게 정의한다. 모호한
  "정상 동작" 금지 — status code, 응답 필드 수, env 변수 N줄처럼 다음
  세션이 기계적으로 판정할 수 있는 기준으로 적는다.
- **시도 이력** — 시간 순 누적. 매 시도마다 `### N차 시도 (KST 시각)`
  헤더 + 무엇을 했고 run/PR 링크 + 결과 (통과/차단/부분). 과거 시도를
  지우지 않는다 — 미래 회귀 분석 자산이다.
- **현재 상태 (Current Blocker)** — 지금 진행을 막는 단 하나의 사유와
  그 해제 조건. 차단이 없으면 "다음 실행 대기" 로 적는다.
- **재개 절차** — 다음 세션이 본 이슈만 읽고 그대로 실행할 수 있는
  self-contained bash + 기대 출력. 이전 세션 conversation context 에
  의존하는 표현 (그 PR, 아까 만든 env 등) 금지.
- **진행 사항 추적** — 코멘트 추가 규칙. 새 시도 결과·새 follow-up
  issue 링크·환경 변경은 코멘트로, 본문은 §현재 상태 (Current Blocker) /
  §재개 절차만 갱신.
- **참고 (References)** — SSOT 문서, 관련 issue/PR, 환경 정보, 사고에서
  학습한 운영 주의사항.

## 작성 노트

- 본 템플릿은 *코드 변경이 아닌 검증 자체의 SSOT* 를 위해 사용한다.
  unit/integration 테스트 코드 추가는 `test`, 제품 동작 변경이 섞이면
  `feat` / `fix` / `refactor`.
- §재개 절차 는 다음 세션이 본 이슈만 읽고 정확한 다음 명령을 실행할 수
  있도록 self-contained 해야 한다 — 이전 세션의 conversation context 에
  의존 금지.
- 새 시도는 코멘트로 추가하고, 본문은 §현재 상태 (Current Blocker) /
  §재개 절차 만 갱신한다.
  본문이 길어져도 §시도 이력 은 시간 순으로 누적 보관 — 미래 회귀 분석 자산.
- 검증이 통과해 close 할 때 마지막 코멘트에 evidence (SHA, run URL,
  env 출력 raw, 응답 200 의 결과) 를 첨부한다.
- 사용자 친화 prose 가 아니라 *AI 가 읽을 self-contained instruction*
  으로 작성한다. 명령은 그대로 실행 가능해야 한다.
