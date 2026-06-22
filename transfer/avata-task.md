# Avatar Task — 입력 초안

> 이 파일은 Avatar Studio UI 입력용 초안이다. Task 6개를 먼저 생성한 뒤 각 Role picker에서 연결한다.
>
> - **skills** = Agent Factory 등록 스킬(`skill_id`)
> - **text** = 미등록 외부 도구·사내 시스템·서술형 설명

---

## Task 1 — 이슈 분석 및 기능 구현

> 연결 Role: `AI 보조 구현자`

- **이름**: 이슈 분석 및 기능 구현
- **context**: GitHub 이슈를 받아 요구사항을 파악한 뒤 TDD 방식으로 설계·구현하고 커밋·PR 생성까지 수행한다. 시작=이슈 접수(요구사항·수용 조건 명시), 산출=기능 구현 커밋 + PR + 통과한 테스트. PR이 리뷰 요청 상태가 되면 완료.
- **skills**
  - `gh:issue-flow` — 이슈 분석→구현→커밋→PR 단계 자동화 수행
  - `gh:issue-implement` — 이슈 본문 해석 후 파일 수정·테스트 구현 수행
  - `superpowers:test-driven-development` — TDD 사이클(Red→Green→Refactor) 유도 수행
- **text**
  - Claude Code (AI coding agent) — 구현·리팩터링 보조 시 사용
  - Codex CLI — 독립 2차 검토·대안 구현 시 사용
  - GitHub Issues — 요구사항 추적·맥락 확인 시 사용

---

## Task 2 — PR 리뷰 코멘트 처리

> 연결 Role: `AI 보조 구현자`

- **이름**: PR 리뷰 코멘트 처리
- **context**: 자동 리뷰어(Gemini Code Assist, Copilot)와 팀원의 PR 코멘트를 평가해 타당한 것은 코드에 반영하고 각 코멘트에 답변을 남긴다. 시작=PR에 리뷰 코멘트 등록, 산출=반영된 코드 변경 + 모든 코멘트 답변. 열린 코멘트가 0이 되면 완료.
- **skills**
  - `gh:pr-reply` — 코멘트 평가·반영·답변 자동화 수행
  - `code-review` — 추가 자체 리뷰·개선점 발굴 수행
- **text**
  - GitHub PR — 인라인 코멘트 확인 및 코드 반영 시 사용

---

## Task 3 — 요구사항 분석 및 기술 설계

> 연결 Role: `설계·검증 담당`

- **이름**: 요구사항 분석 및 기술 설계
- **context**: PRD·이슈·Discussion을 읽어 기술 요구사항(TRD)과 구현 계획을 수립한다. 설계 결정은 ADR로 기록하고 작업 단위는 GitHub 이슈로 분해한다. 시작=PRD 또는 기능 요청, 산출=TRD 문서 + 이슈 목록(또는 구현 계획). 이슈가 생성되면 완료.
- **skills**
  - `devx:prd-to-trd` — PRD→TRD 변환·기술 요구사항 분해 수행
  - `devx:trd-to-issues` — TRD→GitHub 이슈 분해 수행
  - `deep-research` — 기술 조사·선례 분석·비교 수행
- **text**
  - GitHub Issues/Discussions — 요구사항 추적·의사결정 기록 시 사용
  - docs/ 디렉터리(ADR·스펙 문서) — 설계 결정 기록 시 사용

---

## Task 4 — E2E 검증 및 PR 머지

> 연결 Role: `설계·검증 담당`

- **이름**: E2E 검증 및 PR 머지
- **context**: 구현 완료 후 실제 앱을 구동해 골든 패스·엣지 케이스를 직접 테스트하고 회귀가 없으면 PR을 머지한다. 시작=PR이 CI 통과 상태, 산출=검증 완료 확인 + 머지된 PR. 머지 완료 시 종료.
- **skills**
  - `verify` — 앱 구동·골든 패스·엣지 케이스 동작 확인 수행
  - `gh:pr-merge` — 승인 후 전략(rebase/squash) 선택 및 머지 수행
- **text**
  - 로컬 dev server (http://127.0.0.1:9090) — 브라우저 E2E 테스트 시 사용
  - `bun run dev:frontend` — fake backend + Vite dev 서버 구동 시 사용

---

## Task 5 — 스킬 작성 및 리팩터링

> 연결 Role: `개발 워크플로우·환경 관리자`

- **이름**: 스킬 작성 및 리팩터링
- **context**: 반복 수행 업무를 superpowers 스킬로 문서화하거나 기존 스킬을 개선한다. 시작=반복 패턴 발견 또는 기존 스킬 불편사항, 산출=신규 또는 개선된 스킬 파일 + PR. 스킬 PR이 머지되면 완료.
- **skills**
  - `skill:create` — 신규 스킬 파일 초안 작성 수행
  - `skill:refactor` — 기존 스킬 구조 개선 수행
  - `write:task-history` — 작업 이력·의사결정 문서화 수행
- **text**
  - superpowers 플러그인 레포 — 스킬 PR 제출 시 사용
  - .claude/settings.json — hooks·permissions 설정 시 사용

---

## Task 6 — 개발 환경 설정 및 마이그레이션

> 연결 Role: `개발 워크플로우·환경 관리자`

- **이름**: 개발 환경 설정 및 마이그레이션
- **context**: mise·uv·Docker 기반 개발 환경을 설정하거나 레거시 도구에서 마이그레이션한다. dotfiles·Claude Code 플러그인을 최신 상태로 유지한다. 시작=환경 설정 필요 또는 마이그레이션 요청, 산출=업데이트된 dotfiles 커밋 + 설정 가이드.
- **skills**
  - `devx:mise-migrate` — 레거시 Python venv→mise+uv 마이그레이션 수행
  - `update-config` — Claude Code settings.json 설정 수행
  - `devx:restart` — 환경 재시작·검증 수행
- **text**
  - dotfiles 레포 (`~/dotfiles`) — 개인 환경 설정 관리 시 사용
  - WSL2 Ubuntu — 개발 환경 기반으로 사용
  - Docker Compose (fake/prod 프로파일) — 로컬 서비스 구동 시 사용
