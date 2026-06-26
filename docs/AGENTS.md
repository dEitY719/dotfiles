# Module Context

- **Purpose**: Project documentation, AI agent prompts, learnings, playbooks, archived analyses
- **6-디렉토리 구조 (#660 5-tier + #1027 `adr/` 하이브리드)**: `.ssot/` (정책) · `requirement/` (제품 요구사항) · `adr/` (아키텍처 결정 로그) · `guide/` (사람 가이드) · `feature/` (피처별 설계) · `archive/` (보관소)
- **AGENTS.md 라우터 정책**: 정책 본문은 `.ssot/*.md` 에 두고 AGENTS.md 는 요약 + 링크만 유지

# Operational Commands

- **Review**: open in markdown viewer (VS Code, grip)
- **Line count**: `wc -l docs/**/*.md`
- **Markdown lint**: 비활성화 — 자동 실행 금지
- **파일명 린트**: `mise run lint-docs` — docs 파일명 kebab-case 검사 (`adr/`·`requirement/` 강제, 나머지 warn-only, #1027)

# Golden Rules

## Documentation Maintenance

- **DO**: 코드 변경 시 관련 문서 갱신 (특히 AGENTS.md Context Map 과 `.ssot/` SSOT, 그리고 `requirement/product-requirements.md` 의 D/F/NF 표)
- **DO**: 일관된 용어 사용
- **DO**: 구체적 예시(코드 스니펫·명령어) 포함
- **DO**: 피처별 문서는 `feature/<feature-name>/` 로 묶기
- **DO**: 사람-팀원 가이드는 `guide/` 하위에 두기 (`guide/learnings/`, `guide/playbooks/`, `guide/technic/`, `guide/superpowers-ko/`)
- **DON'T**: TODO 마커를 추적 없이 남기기 (`archive/todo-<topic>.md` 처럼 별도 파일로 분리)
- **DON'T**: 이유 없이 archive 하지 않기 (이동 사유를 `archive/README.md` 또는 커밋 메시지에 남길 것)
- **DON'T**: `docs/` 루트에 산문 파일 새로 만들지 않기 — 항상 6 개 디렉토리 중 하나로 분류 (AGENTS.md 제외)
- **DO**: 굵직한 아키텍처 결정은 `adr/NNNN-<kebab>.md` 로 일원화 (제품 요구사항 내 경량 결정은 `requirement/` D-섹션)
- **DO**: `requirement/`·`feature/`·`adr/` 문서는 front-matter `status:` 메타데이터 포함

## 디렉토리 역할 분담 (6-tier, #660 + #1027)

| 디렉토리 | 역할 | 인덱스 |
|---------|------|--------|
| **`.ssot/`** | 프로젝트 정책 SSOT — 명령 UX, env vars, 보드 운영, 커밋/discussion 규칙 | [`.ssot/README.md`](./.ssot/README.md) |
| **`requirement/`** | 제품 요구사항 entry SSOT — D (확정 결정) / F (기능) / NF (비기능) / O (미해소) 4-섹션. D-섹션 = **경량 inline 결정** | [`requirement/product-requirements.md`](./requirement/product-requirements.md) |
| **`adr/`** | 아키텍처 결정 로그 (#1027) — 프로젝트 전체에 파급되는 **굵직한 결정**의 불변 기록. `NNNN-<kebab>.md` | [`adr/README.md`](./adr/README.md) |
| **`guide/`** | 사람-팀원 가이드 — setup, team-git, learnings, playbooks, technic, superpowers-ko 한글 가이드 | [`guide/README.md`](./guide/README.md) |
| **`feature/`** | 피처별 설계·분석 번들 — 한 디렉토리 = 한 피처. superpowers-plans/specs 포함 | (디렉토리 직접 탐색) |
| **`archive/`** | 보관소 — 사후 분석, 평가 자료(company), 다이어그램, 도래일 지난 todo. 외부 노출 차단 영역 포함 | [`archive/README.md`](./archive/README.md) |

**`adr/` vs `requirement/` D-섹션 경계**: 여러 모듈에 파급되는 굵직한 결정은 `adr/`,
제품 요구사항 맥락의 경량 결정은 `requirement/` D-섹션 (상세: [`adr/README.md`](./adr/README.md)).

추가 컨텍스트:

- **`memory/` (Claude 비공개)**: 세션 간 컨텍스트. `guide/learnings/` 로 포인터를 두고 본문 중복 금지.

## 문서 메타데이터·파일명 규칙 (#1027)

- **front-matter `status:`** — `requirement/`·`feature/`·`adr/` 문서는 YAML front-matter
  `status: draft | review | approved | deprecated` 로 현재 유효 SSOT 여부를 표시한다.
- **파일명 kebab-case** — docs 파일명은 kebab-case (`README.md`/`AGENTS.md` 면제).
  `mise run lint-docs` (SSOT: `scripts/lint_docs_filenames.sh`)가 검사 — 현재 **강제(FAIL)**
  범위는 `adr/`·`requirement/`, 나머지는 warn-only (레거시 정리는 별도 이슈).
- **ADR 상호링크** — `feature/` 문서에서 중대한 기술 전환이 일어나면 본문에 관련
  ADR 번호를 링크한다: `Ref: [ADR-0001](../../adr/0001-hybrid-docs-policy.md)`.

## Language Policy

- **사람-팀원 문서** (`guide/learnings/`, `guide/technic/`, `guide/playbooks/`, `archive/`): 한국어
- **AI-instruction 문서** (`claude/skills/*/SKILL.md`, system prompt, machine-read template): 영어
- **`.ssot/` 정책 문서**: 한국어 본문 + 영어 키워드 혼용 (현재 관행)
- **`requirement/product-requirements.md`**: 한국어 (entry SSOT 성격)

## Learnings 출처 링크 규칙

`guide/learnings/*.md` 는 출처 링크를 포함한다:

- **PR number**: `PR #130` (가장 안정적)
- **Commit hash**: 코드 스니펫 출처
- **Issue number**: 관련 논의/버그
- **Review comment URL**: 봇/사람 리뷰 발화

출처가 없는 로컬 실험은 Context 섹션에 상황을 구체적으로 기록한다.

# Maintenance

## 새 정책을 추가할 때

1. `.ssot/<name>.md` 에 본문 작성
2. `.ssot/README.md` 인덱스 표에 행 추가
3. 영향받는 AGENTS.md / CLAUDE.md / 스킬 reference 의 링크를 갱신
4. 필요 시 `requirement/product-requirements.md` 의 D-XX 표에 결정 반영

## 새 문서를 추가할 때

1. 디렉토리 역할에 맞는 곳에 둔다 (위 "디렉토리 역할 분담" 참조)
2. 피처별이면 `feature/<feature-name>/` 하위
3. 정책이라면 `.ssot/`, 실행 절차라면 `guide/playbooks/`, 학습 자료라면 `guide/learnings/` 또는 `guide/technic/`
4. 사후 분석·평가 자료라면 `archive/` 하위 (격리 필요 시 `archive/company/`)
5. 굵직한 아키텍처 결정이라면 `adr/NNNN-<kebab>.md` (front-matter `status:` 포함, 인덱스 표 갱신)

# Context Map

- **[Parent Context](../AGENTS.md)** — 프로젝트 root + 표준 링크
- **[`.ssot/`](./.ssot/README.md)** — 정책 SSOT 인덱스
- **[`requirement/`](./requirement/product-requirements.md)** — 제품 요구사항 entry SSOT
- **[`adr/`](./adr/README.md)** — 아키텍처 결정 로그 (#1027)
- **[`guide/`](./guide/README.md)** — 사람-팀원 가이드 통합 인덱스
- **[`archive/`](./archive/README.md)** — 보관소 (이동 로그 포함)
- **[Shell Common](../shell-common/AGENTS.md)** — POSIX 공유 유틸리티
