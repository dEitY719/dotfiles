---
name: writing-skills
source: /home/bwyoon/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/skills/writing-skills/SKILL.md
language: ko
---

# writing-skills 스킬 한국어 번역 가이드

## 개요
새 스킬 작성/개선을 TDD 방식으로 검증하며 완성하는 스킬

## 언제 사용하나
- 새로운 SKILL.md를 만들거나 기존 스킬 품질을 높여 배포할 때

## 핵심 절차(번역)
1. 스킬 문서 작성을 RED-GREEN-REFACTOR로 운영한다.
2. baseline 실패(스킬 없음)와 적용 후 성공(스킬 있음)을 비교 검증한다.
3. 합리화 루프홀을 표/레드플래그로 명시적으로 봉쇄한다.
4. CSO(검색 최적화) 관점으로 name/description/키워드를 설계한다.

## 주의/금지 사항(번역)
- 실패 시나리오 없이 스킬 작성
- 설명(description)에 워크플로우를 과도하게 요약
- 검증 없이 "잘 동작할 것"으로 배포

## 실행 체크리스트
- 작업 시작 전에 이 스킬이 현재 과제에 실제로 필요한지 확인한다.
- 필요하면 해당 스킬의 원문 `SKILL.md`에서 세부 규칙을 다시 확인한다.
- 진행 중에는 체크리스트/게이트 조건을 생략하지 않는다.
- 완료 보고 전에는 관련 검증 명령과 결과를 함께 남긴다.

## 빠른 예시
> "새 스킬을 writing-skills 절차로 만들자. baseline 실패 시나리오부터 설계해줘."

## 비고
- 이 문서는 팀 학습용 한국어 번역 가이드다.
- 원문 전체의 문장 단위 직역보다, 실무 적용 시 필요한 규칙/절차를 한국어로 명확하게 정리했다.
- 원문 기준 파일: `/home/bwyoon/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/skills/writing-skills/SKILL.md`
