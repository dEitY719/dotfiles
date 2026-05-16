# Module Context

- **Purpose**: Project documentation, AI agent prompts, learnings, playbooks, archived analyses
- **5-디렉토리 구조 (#660)**: `.ssot/` (정책) · `requirement/` (제품 요구사항) · `guide/` (사람 가이드) · `feature/` (피처별 설계) · `archive/` (보관소)
- **AGENTS.md 라우터 정책**: 정책 본문은 `.ssot/*.md` 에 두고 AGENTS.md 는 요약 + 링크만 유지

# Operational Commands

- **Review**: open in markdown viewer (VS Code, grip)
- **Line count**: `wc -l docs/**/*.md`
- **Markdown lint**: 비활성화 — 자동 실행 금지

# Golden Rules

## Documentation Maintenance

- **DO**: 코드 변경 시 관련 문서 갱신 (특히 AGENTS.md Context Map 과 `.ssot/` SSOT, 그리고 `requirement/product-requirements.md` 의 D/F/NF 표)
- **DO**: 일관된 용어 사용
- **DO**: 구체적 예시(코드 스니펫·명령어) 포함
- **DO**: 피처별 문서는 `feature/<feature-name>/` 로 묶기
- **DO**: 사람-팀원 가이드는 `guide/` 하위에 두기 (`guide/learnings/`, `guide/playbooks/`, `guide/technic/`, `guide/superpowers-ko/`)
- **DON'T**: TODO 마커를 추적 없이 남기기 (`archive/todo-ollama.md` 처럼 별도 파일로 분리)
- **DON'T**: 이유 없이 archive 하지 않기 (이동 사유를 `archive/README.md` 또는 커밋 메시지에 남길 것)
- **DON'T**: `docs/` 루트에 산문 파일 새로 만들지 않기 — 항상 5 개 디렉토리 중 하나로 분류 (AGENTS.md 제외)

## 디렉토리 역할 분담 (5-tier, #660)

| 디렉토리 | 역할 | 인덱스 |
|---------|------|--------|
| **`.ssot/`** | 프로젝트 정책 SSOT — 명령 UX, env vars, 보드 운영, 커밋/discussion 규칙 | [`.ssot/README.md`](./.ssot/README.md) |
| **`requirement/`** | 제품 요구사항 entry SSOT — D (확정 결정) / F (기능) / NF (비기능) / O (미해소) 4-섹션 | [`requirement/product-requirements.md`](./requirement/product-requirements.md) |
| **`guide/`** | 사람-팀원 가이드 — setup, team-git, learnings, playbooks, technic, superpowers-ko 한글 가이드 | [`guide/README.md`](./guide/README.md) |
| **`feature/`** | 피처별 설계·분석 번들 — 한 디렉토리 = 한 피처. superpowers-plans/specs 포함 | (디렉토리 직접 탐색) |
| **`archive/`** | 보관소 — 사후 분석, 평가 자료(company), 다이어그램, 도래일 지난 todo. 외부 노출 차단 영역 포함 | [`archive/README.md`](./archive/README.md) |

추가 컨텍스트:

- **`memory/` (Claude 비공개)**: 세션 간 컨텍스트. `guide/learnings/` 로 포인터를 두고 본문 중복 금지.

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

## 문서 archive 절차

```bash
mv docs/old-guide.md docs/archive/
echo "- $(date -I): old-guide.md — <이동 사유> (#<issue>)" >> docs/archive/README.md
```

# Context Map

- **[Parent Context](../AGENTS.md)** — 프로젝트 root + 표준 링크
- **[`.ssot/`](./.ssot/README.md)** — 정책 SSOT 인덱스
- **[`requirement/`](./requirement/product-requirements.md)** — 제품 요구사항 entry SSOT
- **[`guide/`](./guide/README.md)** — 사람-팀원 가이드 통합 인덱스
- **[`archive/`](./archive/README.md)** — 보관소 (이동 로그 포함)
- **[Shell Common](../shell-common/AGENTS.md)** — POSIX 공유 유틸리티
