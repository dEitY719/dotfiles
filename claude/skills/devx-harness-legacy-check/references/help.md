devx:harness-legacy-check — AI 하네스 읽기 전용 감사

역할: CLAUDE.md, AGENTS.md, skills, workflows, settings, hooks, MCP를
      5개 병렬 specialist agent로 감사
출력: .claude/reports/harness-legacy-check.md (덮어쓰기)
제한: 파일 수정/삭제 없음 — 분석 리포트 생성 전용
다음: /devx:harness-refactor 로 low-risk 개선 적용

## 워크플로우가 동작하지 않을 때

이 스킬은 내부적으로 Workflow 도구를 사용합니다. 실행되지 않거나 오류가
발생하면 /config 에서 아래 두 항목이 true 인지 확인하세요:

  Dynamic workflows          → true 여야 함
  Ultracode keyword trigger  → true 여야 함

false 로 설정된 항목은 /config 에서 직접 변경할 수 있습니다.
