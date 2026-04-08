---
name: subagent-driven-development
source: /home/bwyoon/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/skills/subagent-driven-development/SKILL.md
language: ko
---

# subagent-driven-development 스킬 한국어 번역 가이드

## 개요
작업 단위를 서브에이전트로 위임하고 단계별 리뷰로 통제하는 개발 스킬

## 언제 사용하나
- 중간 이상 복잡도 작업을 빠르게 병렬 처리해야 할 때
- 다수 체크리스트를 안정적으로 실행해야 할 때

## 핵심 절차(번역)
1. 작업을 독립적인 단위로 분해해 서브에이전트에 할당한다.
2. 각 단위 완료 후 스펙 준수/코드 품질 2단계 리뷰를 수행한다.
3. 필요 시 모델 선택을 조정하고 상태를 모니터링해 병목을 해소한다.

## 주의/금지 사항(번역)
- 서브에이전트 산출물 무검증 병합
- 동일 파일 충돌을 고려하지 않은 병렬화
- 작업 정의가 모호한 위임

## 실행 체크리스트
- 작업 시작 전에 이 스킬이 현재 과제에 실제로 필요한지 확인한다.
- 필요하면 해당 스킬의 원문 `SKILL.md`에서 세부 규칙을 다시 확인한다.
- 진행 중에는 체크리스트/게이트 조건을 생략하지 않는다.
- 완료 보고 전에는 관련 검증 명령과 결과를 함께 남긴다.

## 빠른 예시
> "plan의 Task 1~4를 subagent-driven-development 방식으로 태스크별 위임해서 진행해줘."

## 비고
- 이 문서는 팀 학습용 한국어 번역 가이드다.
- 원문 전체의 문장 단위 직역보다, 실무 적용 시 필요한 규칙/절차를 한국어로 명확하게 정리했다.
- 원문 기준 파일: `/home/bwyoon/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/skills/subagent-driven-development/SKILL.md`
