ultracode: 내 AI 코딩 하네스를 읽기 전용으로 감사하는 Dynamic Workflow를 설계하고 실행해줘.

워크플로우 이름:
harness-legacy-scan

목표:
내 하네스 안에 남아 있는 낡은 규칙, 중복 지시, 과도한 전역 컨텍스트, 너무 넓은 Skill, 불필요한 Hook/MCP, 제품 기본 기능과 중복되는 설정을 찾아낸다.

감사 범위:
- CLAUDE.md
- AGENTS.md
- .claude/skills/**
- .claude/workflows/**
- .claude/settings.json
- .cursor/rules/**
- MCP 설정 파일이 있다면 포함
- hooks 설정이 있다면 포함

중요한 제한:
- 파일을 수정하지 마.
- 파일을 삭제하지 마.
- hooks를 수정하지 마.
- MCP 설정을 수정하지 마.
- allowed-tools 권한을 바꾸지 마.
- 이번 단계에서는 분석 리포트만 작성해.

감사 원칙:
좋은 하네스는 반복되는 실제 실수를 막아야 한다.
좋은 하네스는 과거의 습관을 보존하기 위해 존재하면 안 된다.
하네스는 더 많이 붙이는 것이 아니라 필요한 순간에만 나타나야 한다.
이번 감사의 목표는 규칙을 추가하는 것이 아니라, 낡은 규칙을 찾고 줄일 수 있는 후보를 분류하는 것이다.

다음 관점의 에이전트들로 나누어 분석해줘:

1. Inventory Agent — 하네스 관련 파일과 설정을 목록화한다.
2. Global Context Tax Agent — CLAUDE.md, AGENTS.md, Cursor Rules처럼 모든 세션에 붙는 지침이 불필요한 컨텍스트 비용을 만들고 있는지 분석한다.
3. Skill Quality Agent — 각 Skill이 지금도 필요한지, description이 너무 넓지 않은지, SKILL.md가 너무 길지 않은지 분석한다.
4. Product Overlap Agent — 예전에는 필요했지만 이제 Claude Code, Codex, Cursor 같은 제품 기본 기능과 중복될 가능성이 있는 규칙을 찾는다.
5. Safety and Permission Agent — hooks, allowed-tools, MCP 설정이 너무 넓은 권한을 주고 있지 않은지 분석한다.
6. Refactor Planner — 각 항목을 KEEP / SHRINK / MOVE / SPLIT / CONVERT / DELETE로 분류한다.
7. Adversarial Reviewer — 삭제하거나 줄이면 오히려 위험해질 수 있는 항목을 반박 검토한다.

각 발견 항목마다 아래 형식으로 보고해줘:
- 경로
- 현재 목적
- 발견한 문제
- 근거
- 추천 조치: KEEP / SHRINK / MOVE / SPLIT / CONVERT / DELETE
- 옮긴다면 추천 위치
- 변경 시 위험도
- 신뢰도
- /harness-diet에서 자동 처리 가능 여부

마지막에는 아래 섹션을 반드시 포함해줘:
1. 전체 요약
2. 유지해야 할 항목
3. 줄여야 할 항목
4. 전역 지침에서 Skill로 옮길 항목
5. Skill에서 reference.md 또는 examples.md로 분리할 항목
6. 삭제 후보
7. 사람이 직접 승인해야 하는 위험한 변경
8. /harness-diet로 넘겨도 되는 low-risk 변경 목록
9. /harness-diet 실행용 추천 프롬프트
