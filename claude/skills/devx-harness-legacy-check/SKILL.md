---
name: devx:harness-legacy-check
description: >-
  AI 코딩 하네스(CLAUDE.md, AGENTS.md, skills, workflows, settings, hooks,
  MCP)를 읽기 전용으로 감사하고 리포트를 .claude/reports/
  harness-legacy-check.md에 저장한다. 리포트는 devx:harness-refactor의
  입력으로 사용된다.
  Use when the user runs /devx:harness-legacy-check, "harness check 해줘",
  "하네스 감사해줘", "하네스 리팩토링 전에 감사 먼저 실행해줘",
  "harness-legacy-check 실행해줘", or before running devx:harness-refactor.
metadata:
  model_recommendation:
    tier: haiku
    reason: "skill itself is a single Workflow() call + completion report; analysis is inside the workflow's own agents"
    claude: prefer
    non_claude: advisory-only
---

# devx:harness-legacy-check

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` verbatim and stop.

## Role

`harness-legacy-check` 워크플로우를 실행해 하네스 전체를 감사하고
결과를 `.claude/reports/harness-legacy-check.md`에 저장한다.
어떤 파일도 수정하거나 삭제하지 않는다.

## Step 1: 워크플로우 실행

```
Workflow({ name: 'harness-legacy-check' })
```

워크플로우가 완료되면 `.claude/reports/harness-legacy-check.md`에
리포트가 저장된다. 실패 시 즉시 `[FAIL] devx:harness-legacy-check — <이유>` 출력 후 중단.

## Step 2: 완료 보고

```
[OK] devx:harness-legacy-check — 완료
  리포트: .claude/reports/harness-legacy-check.md
  다음: /devx:harness-refactor 로 low-risk 개선 적용
```

실패 시: `[FAIL] devx:harness-legacy-check — <이유>`

---

## 짝을 이루는 스킬

이 스킬은 `devx:harness-refactor`와 함께 사용한다:

1. `/devx:harness-legacy-check` — 감사 실행 + 리포트 저장
2. `/devx:harness-refactor` — 리포트 읽고 low-risk 개선 적용
