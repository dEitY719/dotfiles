---
name: devx:harness-refactor
description: >-
  harness-legacy-check 감사 리포트를 바탕으로 low-risk 하네스 개선을 적용하는
  워크플로우를 생성하고 실행한다. claude/workflows/harness-refactor.js 를 현재
  감사 결과에 맞게 새로 작성한 뒤 Workflow 도구로 실행한다.
  Use when the user runs /devx:harness-refactor, "harness 리팩토링해줘",
  "harness-refactor 실행해줘", "하네스 정리해줘", or after reviewing a
  harness-legacy-check report and wanting to apply the findings.
metadata:
  model_recommendation:
    tier: sonnet
    reason: "audit report classification + JS workflow generation + multi-agent orchestration"
    claude: prefer
    non_claude: advisory-only
---

# devx:harness-refactor

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` verbatim and stop.

## Role

harness-legacy-check 감사 리포트를 읽고 low-risk 항목만 골라
`claude/workflows/harness-refactor.js` 를 새로 작성한 뒤 실행한다.
이전 harness-refactor.js 는 새 파일로 덮어쓴다 (git log 에 이전 계획 보존).

## Step 1: 감사 리포트 확인

현재 세션에서 harness-legacy-check 출력을 찾는다.

- 없으면: "harness-legacy-check 결과가 없습니다. 먼저 /harness-legacy-check 를 실행해 주세요." 출력 후 중단.
- 있으면: Step 2 진행.

## Step 2: Low-risk 항목 분류

리포트 항목을 워크플로우 포함 여부로 분류한다.
분류 기준: `references/classification-rules.md` 참조.

## Step 3: harness-refactor.js 생성

`claude/workflows/harness-refactor.js` 를 새로 작성한다.
파일 구조 및 설계 원칙: `references/workflow-template.md` 참조.

Step 2 에서 금지 항목으로 분류된 것은 Final Report 의
"Human Approval Required" 섹션에만 기록.

## Step 4: 워크플로우 실행

```
Workflow({ scriptPath: 'claude/workflows/harness-refactor.js' })
```

## Step 5: 완료 보고

```
[OK] devx:harness-refactor — 완료
  변경 파일: N개  |  생성 references/: N개  |  아카이브: N개
  Human review 필요: N개 (Final Report "Human Approval Required" 참조)
  다음: git diff 확인 후 /gh:commit
```

실패 시: `[FAIL] devx:harness-refactor — <이유>`
