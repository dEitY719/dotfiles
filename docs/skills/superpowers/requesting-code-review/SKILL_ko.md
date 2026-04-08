---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or before merging to verify work meets requirements
---

# 코드 리뷰 요청

superpowers:code-reviewer 서브에이전트를 디스패치하여 이슈가 확산되기 전에 포착합니다. 리뷰어는 평가를 위해 정밀하게 구성된 컨텍스트를 받습니다 — 당신의 세션 히스토리는 절대 전달되지 않습니다. 이렇게 하면 리뷰어가 당신의 사고 과정이 아닌 작업 결과물에 집중할 수 있고, 당신 자신의 컨텍스트는 후속 작업을 위해 보존됩니다.

**핵심 원칙:** 일찍 리뷰하고, 자주 리뷰하라.

## 리뷰를 요청할 시점

**필수:**
- 서브에이전트 주도 개발에서 각 태스크 완료 후
- 주요 기능 구현 완료 후
- main에 머지하기 전

**선택이지만 가치 있음:**
- 막힐 때 (새로운 관점)
- 리팩토링 전 (기준선 점검)
- 복잡한 버그 수정 후

## 요청 방법

**1. git SHA 확인:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. code-reviewer 서브에이전트 디스패치:**

Task 도구를 superpowers:code-reviewer 타입으로 사용하고, `code-reviewer.md`의 템플릿을 채웁니다

**플레이스홀더:**
- `{WHAT_WAS_IMPLEMENTED}` - 방금 구현한 내용
- `{PLAN_OR_REQUIREMENTS}` - 구현해야 할 사항
- `{BASE_SHA}` - 시작 커밋
- `{HEAD_SHA}` - 종료 커밋
- `{DESCRIPTION}` - 간략한 요약

**3. 피드백에 대한 조치:**
- Critical 이슈는 즉시 수정
- Important 이슈는 다음 작업 전에 수정
- Minor 이슈는 나중을 위해 기록
- 리뷰어가 틀렸다면 반박 (근거와 함께)

## 예시

```
[방금 Task 2 완료: 검증 함수 추가]

You: 다음으로 넘어가기 전에 코드 리뷰를 요청하겠습니다.

BASE_SHA=$(git log --oneline | grep "Task 1" | head -1 | awk '{print $1}')
HEAD_SHA=$(git rev-parse HEAD)

[superpowers:code-reviewer 서브에이전트 디스패치]
  WHAT_WAS_IMPLEMENTED: 대화 인덱스의 검증 및 복구 함수
  PLAN_OR_REQUIREMENTS: docs/superpowers/plans/deployment-plan.md의 Task 2
  BASE_SHA: a7981ec
  HEAD_SHA: 3df7661
  DESCRIPTION: 4가지 이슈 유형을 처리하는 verifyIndex()와 repairIndex() 추가

[서브에이전트 반환]:
  강점: 깔끔한 아키텍처, 실질적인 테스트
  이슈:
    Important: 진행 표시기 누락
    Minor: 보고 간격에 대한 매직 넘버 (100)
  평가: 진행 가능

You: [진행 표시기 수정]
[Task 3으로 계속]
```

## 워크플로우와의 통합

**서브에이전트 주도 개발:**
- 각 태스크 후 리뷰
- 이슈가 누적되기 전에 포착
- 다음 태스크로 넘어가기 전에 수정

**계획 실행:**
- 각 배치(3개 태스크) 후 리뷰
- 피드백 받고, 적용하고, 계속

**임시 개발:**
- 머지 전 리뷰
- 막힐 때 리뷰

## 위험 신호

**절대 하지 말 것:**
- "간단하니까" 리뷰 건너뛰기
- Critical 이슈 무시
- 수정되지 않은 Important 이슈가 있는 상태에서 진행
- 타당한 기술적 피드백에 대한 반박

**리뷰어가 틀렸을 경우:**
- 기술적 근거를 들어 반박
- 작동을 증명하는 코드/테스트 제시
- 명확한 설명 요청

템플릿 참조: requesting-code-review/code-reviewer.md
