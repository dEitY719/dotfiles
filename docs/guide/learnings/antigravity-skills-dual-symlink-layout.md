# Antigravity CLI (agy) Skills 심볼릭 링크 듀얼 레이아웃(bare vs namespace) 분석 및 검토

- **관련 이슈**: #1789 (review dual symlink layout in ~/.gemini/config/skills)
- **선행 이슈**: #1784 (Antigravity용 네임스페이스 기반 skills 링크 등록), #1787 (순정 Gemini CLI 지원 제거)
- **일자**: 2026-09-11

---

## 1. 배경 및 질문 (Context & Problem)

- 순정 Gemini CLI 지원이 제거(#1787)된 후, Antigravity CLI(`agy`)의 global customizations root는 `~/.gemini/config/`로 일원화되었습니다.
- 현재 `scripts/setup-skills-ssot.sh` 실행 시 `~/.gemini/config/skills`에는 두 단계에 걸쳐 심볼릭 링크가 생성됩니다:
  1. **Step 3b (`link_skills_compose "agy"`)**: `add-ai-metrics`, `approve`, `issue`, `create` 등 76개의 단일/bare 심볼릭 링크 생성.
  2. **Step 3c (`sync-gemini-skills-namespace.sh`)**: `gh-setup:add-ai-metrics`, `gh-pr:approve`, `gh-flow:issue`, `gh-issue:create` 등 76개의 네임스페이스 기반 심볼릭 링크 생성.
- 결과적으로 `~/.gemini/config/skills`에 총 152개의 심볼릭 링크가 공존합니다.
- **핵심 질문**: "순정 Gemini CLI 지원이 제거되었는데, `~/.gemini/config/skills`에 bare 이름과 namespaced 이름을 둘 다 유지해야 하는가? 아니면 한 쪽은 중복인가?"

---

## 2. Antigravity CLI (agy) 내부 동작 실측 및 검증 (Verification)

Antigravity CLI 바이너리(`/home/bwyoon/.local/bin/agy`) 및 실제 실행 세션의 시스템 프롬프트 주입 방식을 역공학 및 실측 분석하였습니다.

### 2.1 agy 의 스킬 탐색 (Discovery) 메커니즘
- agy 바이너리는 `~/.gemini/config/skills/<entry>/SKILL.md` 경로를 탐색합니다.
- 디렉터리 내의 심볼릭 링크 엔트리 이름(`<entry>`)을 읽고, 해당 하위의 `SKILL.md`를 파싱하여 스킬 메타데이터를 로드합니다.
- agy는 링크명에 콜론(`:`)이 포함된 형태(`gh-flow:issue`)와 일반 bare 형태(`issue`) 모두 유효한 파일명/디렉터리명으로 인식하며 정상적으로 검색 및 로드합니다.

### 2.2 시스템 프롬프트(Available skills) 주입 실측
현재 실행 중인 Antigravity CLI 세션의 실제 시스템 프롬프트에 주입된 Available skills 목록을 확인한 결과:
- **Bare 링크의 역할**:
  - `SKILL.md` 내부의 `name:` 필드(예: `name: issue`)와 매칭되는 단일 이름 호출(`/issue`, `/commit`, `/approve` 등)을 지원합니다.
  - 사용자 또는 에이전트가 축약된 단축 이름으로 스킬을 자연스럽게 참조할 때 필수적입니다.
- **Namespaced 링크의 역할**:
  - 사용자가 Claude Code 플러그인 컨벤션과 동일하게 슬래시 커맨드로 네임스페이스를 명시하여 호출할 때(예: `/gh-flow:issue`, `/gh-issue:create`, `/gh-pr:create`) Antigravity CLI가 해당 스킬을 정확히 식별할 수 있습니다.
  - **동일 이름 충돌(Collision Resolution)**: `gh-issue-skills/skills/create`, `gh-pr-skills/skills/create`, `packaging-skills/skills/create`처럼 스킬명이 동일한 경우, bare 링크만 있으면 우선순위 1개만 `create`가 되고 나머지는 `__` 접두사를 붙여야 합니다. 반면 네임스페이스 링크는 `gh-issue:create`, `gh-pr:create`, `packaging:create`로 고유하게 분리되어 충돌 없이 완벽히 매핑됩니다.
- **중복 주입 여부 (Deduplication)**:
  - Antigravity CLI는 `SKILL.md`의 `name:` 또는 정규화된 고유 키를 기준으로 스킬을 관리하므로, 동일한 `SKILL.md`를 가리키는 bare 링크와 namespace 링크가 둘 다 존재해도 프롬프트 내에 스킬이 2개씩 복제 주입되지 않고 중복이 제거됩니다.
  - 따라서 프롬프트 토큰 낭비나 컨텍스트 오염이 발생하지 않습니다.

---

## 3. 결론 및 권고 (Decision & Recommendation)

### 판정: **듀얼 레이아웃(Dual Symlink Layout) 유지 (Keep Both)**

- **이유 1 (UX 편의성)**: 사용자가 `/issue 1789`, `/commit`, `/approve` 등 bare 이름으로 호출하든, `/gh-flow:issue`, `/gh-pr:approve` 등 네임스페이스 이름으로 호출하든 모두 자연스럽게 인식됩니다.
- **이유 2 (이름 충돌 방지)**: `create` 등 복수 리포지토리 간 동일 스킬명 충돌 시 네임스페이스 심볼릭 링크가 유일한 충돌 방지 네임스페이스 역할을 수행합니다.
- **이유 3 (비용 무시 가능)**: 파일시스템 심볼릭 링크는 디스크 용량이나 I/O 부담이 없으며, agy 에이전트 런타임에서도 중복 주입 없이 정상 디둡(dedup) 처리됩니다.
- **결론**: `setup-skills-ssot.sh`의 Step 3b(`link_skills_compose "agy"`)와 Step 3c(`sync-gemini-skills-namespace.sh`)는 상호 보완적이므로 **둘 다 유지**하는 것이 올바른 아키텍처입니다.
