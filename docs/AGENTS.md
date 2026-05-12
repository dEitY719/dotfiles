# Module Context

- **Purpose**: Project documentation, AI agent prompts, learnings, playbooks, archived analyses
- **SSOT 디렉토리**: `.ssot/`(정책), `playbooks/`(실행 절차), `learnings/`(재사용 패턴), `archive/`(과거 결정 분석)
- **AGENTS.md 라우터 정책**: 정책 본문은 `.ssot/*.md`에 두고 AGENTS.md는 요약 + 링크만 유지

# Operational Commands

- **Review**: open in markdown viewer (VS Code, grip)
- **Line count**: `wc -l docs/**/*.md`
- **Markdown lint**: 비활성화 — 자동 실행 금지

# Golden Rules

## Documentation Maintenance

- **DO**: 코드 변경 시 관련 문서 갱신 (특히 AGENTS.md Context Map과 `.ssot/` SSOT)
- **DO**: 일관된 용어 사용
- **DO**: 구체적 예시(코드 스니펫·명령어) 포함
- **DO**: 피처별 문서는 `feature/<feature-name>/`로 묶기
- **DON'T**: TODO 마커를 추적 없이 남기기 (`todo.txt`로 이전)
- **DON'T**: 이유 없이 archive 하지 않기 (이동 사유를 `archive/README` 또는 커밋 메시지에 남길 것)

## 디렉토리 역할 분담 (중복 금지, 링크로 연결)

- **`.ssot/`**: 프로젝트 정책 SSOT — 명령 UX, env vars, 보드 운영, 커밋/work-log 규칙. 인덱스: [`.ssot/README.md`](./.ssot/README.md).
- **`technic/`**: 검증된 스택 중심 기술 문서 (수백 줄). 전체 셋업 + tradeoff.
- **`learnings/`**: 실제 PR/커밋에서 추출한 짧은 재사용 패턴 (50–80줄). 한국어, 동료팀 공유 목적. 출처(PR/commit/issue/리뷰 URL) 표기 필수.
- **`feature/<name>/`**: 피처별 설계·분석 번들 (다수 파일).
- **`playbooks/`**: 실행 절차·셋업 순서·운영 체크리스트.
- **`archive/`**: 더 이상 정책 SSOT가 아닌 과거 결정 분석·검토 대기 문서.
- **`memory/` (Claude 비공개)**: 세션 간 컨텍스트. `learnings/`로 포인터를 두고 본문 중복 금지.

## Language Policy

- **사람-팀원 문서** (`learnings/`, `technic/` narrative, `archive/`): 한국어
- **AI-instruction 문서** (`SKILL.md`, system prompt, machine-read template): 영어
- **`.ssot/` 정책 문서**: 한국어 본문 + 영어 키워드 혼용 (현재 관행)

## Learnings 출처 링크 규칙

`learnings/*.md`는 출처 링크를 포함한다:

- **PR number**: `PR #130` (가장 안정적)
- **Commit hash**: 코드 스니펫 출처
- **Issue number**: 관련 논의/버그
- **Review comment URL**: 봇/사람 리뷰 발화

출처가 없는 로컬 실험은 Context 섹션에 상황을 구체적으로 기록한다.

# Maintenance

## 새 정책을 추가할 때

1. `.ssot/<name>.md`에 본문 작성
2. `.ssot/README.md` 인덱스 표에 행 추가
3. 영향받는 AGENTS.md / CLAUDE.md / 스킬 reference 의 링크를 갱신

## 새 문서를 추가할 때

1. 디렉토리 역할에 맞는 곳에 둔다 (위 "디렉토리 역할 분담" 참조)
2. 피처별이면 `feature/<feature-name>/` 하위
3. 정책이라면 `.ssot/`, 실행 절차라면 `playbooks/`

## 문서 archive 절차

```bash
mv docs/old-guide.md docs/archive/
echo "Archived: replaced by new-guide.md ($(date -I))" >> docs/archive/README.md
```

# Context Map

- **[Parent Context](../AGENTS.md)** — 프로젝트 root + 표준 링크
- **[`.ssot/`](./.ssot/README.md)** — 정책 SSOT 인덱스
- **[Learnings](./learnings/README.md)** — 실제 PR에서 추출한 재사용 패턴
- **[Shell Common](../shell-common/AGENTS.md)** — POSIX 공유 유틸리티
