# Archive — 이동 사유 로그

`docs/archive/` 는 (1) 더 이상 정책 SSOT 가 아닌 과거 결정 분석, (2) 사후 분석·평가 자료, (3) 도래일이 지난 todo, (4) 외부 노출을 차단해야 하는 내부 자료 를 모은 보관소입니다.

`docs/AGENTS.md` 의 "문서 archive 절차" 에 따라 이동할 때 이 파일 하단에 사유를 한 줄씩 누적합니다.

## 디렉토리·파일 구조

| 항목 | 출처 | 사유 |
|------|------|------|
| `jira-workflow-decision.md` | (기존) | jira 워크플로우 초기 결정 분석 |
| `workflow-git-jira-confluence-automation-guide-validated.md` | (기존) | 자동화 가이드 검증본 보관 |
| `postmortem/` | `docs/postmortem/` | 사후 분석 = 보관소 영역 (#660) |
| `review-2026/` | `docs/review/` | abc-review-C/CX/G 2026 평가 자료 (#660) |
| `company/` | `docs/company/` | JIRA Story draft · OKR · AIE 평가 자료. **외부 노출 금지** — git 추적은 유지하되 archive 하위로 격리 (#660) |
| `diagram/` | `docs/diagram/` | setup-sh-flow 단일 다이어그램, 재참조 빈도 낮음 (#660) |
| `todo-ollama.md` | `docs/todo.txt` | 2026-02-04 Ollama 작업 — 대부분 완료, 잔여 항목 archive (#660) |
| `todo-defer-2026-05.md` | `docs/todo/todo-defer-until-2026-05-plugin-loader-and-ux-library-split.md` | 도래일(2026-05) 지남. 별도 트래킹 이슈로 옮길지 검토 필요 (#660) |

## 이동 로그

- 2026-05-16 (#660): `docs/` 5-디렉토리 재정렬 — `postmortem/`, `review/`, `company/`, `diagram/`, `todo.txt`, `todo/` 6 개 항목을 archive 하위로 통합. 사유: 단발 디렉토리 해체 + 내부 자료 격리 + 도래일 지난 todo 정리.
