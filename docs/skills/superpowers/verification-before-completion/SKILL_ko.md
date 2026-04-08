---
name: verification-before-completion
source: /home/bwyoon/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/skills/verification-before-completion/SKILL.md
language: ko
---

# verification-before-completion 스킬 한국어 번역 가이드

## 개요
완료/성공 주장 전에 반드시 최신 검증 증거를 확인하게 하는 스킬

## 언제 사용하나
- 작업 완료 보고, PR 생성, 커밋 직전, 테스트 성공 선언 직전

## 핵심 절차(번역)
1. 주장마다 증명 명령을 식별한다.
2. 명령을 실제 실행하고 출력/종료코드를 확인한다.
3. 증거가 있을 때만 완료/성공 문구를 사용한다.

## 주의/금지 사항(번역)
- "될 것 같다" 추정 보고
- 부분 검증으로 전체 성공 주장
- 이전 실행 결과 재사용

## 실행 체크리스트
- 작업 시작 전에 이 스킬이 현재 과제에 실제로 필요한지 확인한다.
- 필요하면 해당 스킬의 원문 `SKILL.md`에서 세부 규칙을 다시 확인한다.
- 진행 중에는 체크리스트/게이트 조건을 생략하지 않는다.
- 완료 보고 전에는 관련 검증 명령과 결과를 함께 남긴다.

## 빠른 예시
> "마무리 전에 verification-before-completion 체크로 테스트/빌드 증거를 확인하고 보고해줘."

## 비고
- 이 문서는 팀 학습용 한국어 번역 가이드다.
- 원문 전체의 문장 단위 직역보다, 실무 적용 시 필요한 규칙/절차를 한국어로 명확하게 정리했다.
- 원문 기준 파일: `/home/bwyoon/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/skills/verification-before-completion/SKILL.md`
