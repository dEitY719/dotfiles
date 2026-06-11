# devx:harness-refactor — Help

## Usage

/devx:harness-refactor

harness-legacy-check 감사 리포트를 바탕으로 low-risk 하네스 개선을 적용하는
워크플로우를 생성하고 실행한다.

## 사전 조건

현재 세션에 `/harness-legacy-check` 실행 결과가 있어야 한다.
없으면 스킬이 중단하고 먼저 실행할 것을 안내한다.

## 실행 흐름

1. 세션에서 harness-legacy-check 리포트 확인
2. low-risk 항목 분류 (references/classification-rules.md 기준)
3. claude/workflows/harness-refactor.js 새로 작성 (이전 파일 덮어쓰기)
4. 워크플로우 실행
5. [OK]/[FAIL] 결과 요약 보고

## 결과

`claude/workflows/harness-refactor.js` 가 갱신되고 워크플로우가 실행된다.
이전 파일은 git log 에 보존된다.
