# `.ssot` — Project Policy Single Source of Truth

이 디렉토리는 dotfiles 프로젝트의 **정책 SSOT**를 모은다.
일반 문서 디렉토리가 아니라 AGENTS.md 라우터들이 가리키는 정책 본문 저장소다.

## 원칙

- 한 정책당 한 파일. 다른 곳에서 같은 규칙을 다시 쓰지 않고 여기로 링크한다.
- AGENTS.md (root + nested)는 **얇은 라우터**다. 정책 요약 1–2줄 + `.ssot` 링크만 둔다.
- 결정 분석·검토 대기 문서는 SSOT가 아니다. `docs/archive/`로 이동한다.
- 실행 절차·셋업 순서는 SSOT가 아니다. `docs/playbooks/`에 둔다.

## 인덱스

| 파일 | 정책 영역 |
|------|-----------|
| [`command-guidelines.md`](./command-guidelines.md) | 명령어 / help 인터페이스, 출력 정책, row 함수 SSOT 패턴 |
| [`command-design-pattern.md`](./command-design-pattern.md) | dispatcher + private sub-function 구조, Type 2A/2B, passthrough 규칙, SOLID |
| [`env-vars.md`](./env-vars.md) | cross-skill / cross-tool env var 카탈로그 |
| [`github-project-board.md`](./github-project-board.md) | GitHub Project v2 보드 운영 규칙, closing keyword 정책 |
| [`commit-message-standard.md`](./commit-message-standard.md) | 브랜치 명명·커밋 메시지·work_log 자동화 |

## 변경 절차

1. `.ssot/<file>.md`를 먼저 갱신한다.
2. 본문을 인용하던 AGENTS.md / CLAUDE.md / 스킬 reference 파일들이 여전히 정확한지 확인한다.
3. 새 정책을 추가한 경우 위 인덱스 표에 행을 추가한다.

## 관련 위치

- `docs/playbooks/` — 정책 적용을 위한 실행 절차 (예: 칸반 보드 초기 셋업)
- `docs/archive/` — 더 이상 정책 SSOT가 아닌 결정 분석·검토 문서
- `docs/learnings/` — PR/커밋에서 추출한 재사용 가능한 패턴 노트
- `claude/skills/` — 스킬 SKILL.md / references (실행 가능한 워크플로우 SSOT)
