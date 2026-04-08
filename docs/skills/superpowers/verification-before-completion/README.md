# verification-before-completion

## 한 줄 설명
완료/성공 주장 전에 반드시 최신 검증 증거를 확인하게 하는 스킬

## 이 스킬이 해결하는 문제
- 작업 흐름에서 자주 발생하는 실수(순서 누락, 검증 생략, 범위 과대화)를 줄인다.
- 팀 단위 협업에서 의사결정 기준과 보고 형식을 통일한다.

## 핵심 포인트
- 주장마다 증명 명령을 식별한다.
- 명령을 실제 실행하고 출력/종료코드를 확인한다.
- 증거가 있을 때만 완료/성공 문구를 사용한다.

## 팀 적용 가이드
- PR/리뷰/디버깅/계획 수립 시 이 문서의 체크리스트를 먼저 확인한다.
- 개인 선호보다 스킬의 게이트 조건(승인, 검증, 옵션 제시)을 우선 적용한다.
- 예외가 필요하면 근거를 남기고 팀에 공유한다.

## Example usage
```text
"마무리 전에 verification-before-completion 체크로 테스트/빌드 증거를 확인하고 보고해줘."
```

## 산출물
- 한국어 가이드: `SKILL_ko.md`
- 원문: `/home/bwyoon/.claude/plugins/cache/superpowers-dev/superpowers/5.0.7/skills/verification-before-completion/SKILL.md`

## 추천 학습 순서
1. `SKILL_ko.md`를 먼저 읽어 전체 흐름을 파악한다.
2. 실제 적용 전에 원문 `SKILL.md`의 세부 규칙(금지/예외)을 재확인한다.
3. 작은 작업에서 1~2회 반복 적용 후 팀 표준으로 확장한다.
