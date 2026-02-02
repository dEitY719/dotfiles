# Reviewer Info

- **Reviewer**: Roo (AI Assistant)
- **Date**: 2026-02-02
- **Scope**: 프로젝트 구조, SOLID 원칙 준수 및 Single Source of Truth(SSOT) 적용 여부에 대한 리뷰

# 프로젝트 구조 요약

레포지토리는 모듈형 레이아웃을 따릅니다:

- `bash/` – Bash 전용 설정 및 유틸리티
- `zsh/` – Zsh 전용 설정
- `shell-common/` – 공유 POSIX 유틸리티, 별칭, 함수, 커스텀 툴
- `docs/` – 문서, 리뷰 문서, AGENTS.md 마스터 프롬프트
- `tests/` – pytest 스위트 및 크로스‑쉘 호환성 테스트
- `git/` – Git 훅 및 설정
- `claude/` – Claude Code 설정, 스킬, 자동화

주요 AGENTS 파일:

- 루트 [`AGENTS.md`](AGENTS.md:1) – 프로젝트 컨텍스트, 골든 룰, SOLID & TDD 가이드라인
- Docs 모듈 [`docs/AGENTS.md`](docs/AGENTS.md:1) – 문서 표준 및 리뷰 워크플로우
- Shell‑common AGENTS [`shell-common/AGENTS.md`](shell-common/AGENTS.md:1) – 공유 유틸리티 규칙

# SOLID 원칙 평가

| 원칙     | 점수 /10  | 코멘트                                                                                                                                                                                      |
| -------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **SRP**  | 8         | 대부분 파일이 단일 도메인에 집중하지만 `shell-common/tools/custom/`에 있는 일부 스크립트(`make_jira.sh` 등)는 로깅과 비즈니스 로직을 혼합하고 있습니다. 데이터 수집과 포맷팅을 분리하세요.  |
| **OCP**  | 7         | 새로운 파일 추가를 통한 확장은 장려하지만, 핵심 스크립트(`main.bash`, `main.zsh`)에 단일 조건문이 많이 존재합니다. `bash/env/` 혹은 `zsh/env/` 아래 플러그인 모듈로 리팩터링을 권장합니다.  |
| **LSP**  | 6         | 래퍼 함수가 옵션 플래그를 추가해 출력 형식을 바꾸는 경우가 있어 하위 소비자를 깨뜨릴 수 있습니다. 원래 명령 계약을 유지하도록 수정하세요.                                                   |
| **ISP**  | 7         | 함수는 대체로 작지만 `devx.sh`, `manage_doc.sh` 등 몇몇은 파라미터가 과다합니다. 더 작은 헬퍼 함수로 분리하세요.                                                                            |
| **DIP**  | 8         | `ux_lib` 의존은 잘 추상화돼 있으나, 일부 스크립트가 `jq`, `git` 등을 직접 호출해 얇은 래퍼가 부족합니다. 테스트 용이성을 위해 래퍼를 추가하세요.                                            |

전체 SOLID 점수: **36/50**

# SSOT (Single Source of Truth) 평가

레포지토리는 Git을 SSOT로 삼고 있지만, 보고에 사용되는 생성 아티팩트를 위한 전용 디렉터리가 부족합니다:

- 주간 로그를 위한 `docs/worklog/` 디렉터리 부재
- 최종 복사‑붙여넣기 텍스트를 위한 `docs/jira/` 및 `docs/confluence/` 디렉터리 부재
- 이러한 아티팩트를 생성하는 스크립트(`make_jira.sh`, `make_confluence.sh`)는 리뷰 문서에 제안만 있을 뿐 구현되지 않았습니다.

**결과**

1. 팀원이 Jira, Confluence, 로컬 노트에 정보를 수동으로 복제해 드리프트 위험이 존재합니다.
2. 정의된 SSOT 디렉터리가 없어 자동화가 어려워집니다.

# 이슈 및 권고사항

## High (고위험)

- **SSOT 아티팩트 디렉터리 부재** – `docs/worklog/`, `docs/jira/`, `docs/confluence/` 를 생성해 텍스트를 저장하도록 합니다.
- **커스텀 툴의 책임 혼합** – `make_jira.sh`/`make_confluence.sh` 를 구현할 때 데이터 추출, 템플릿 적용, 선택적 LLM 후처리를 명확히 분리합니다.

## Medium (중위험)

- **주 진입 스크립트(`bash/main.bash`, `zsh/main.zsh`)에 큰 조건 블록 존재** – 환경별 로직을 별도 모듈로 추출합니다.
- **래퍼 함수가 LSP를 위반** – `shell-common/functions/` 에 있는 래퍼 함수를 감사하고 계약 일관성을 확보합니다.

## Low (저위험)

- **네이밍 일관성** – 새 스크립트는 snake_case 로 명명하고 `shell-common/tools/custom/` 에 배치합니다.
- **직접 실행 가드 검증** – `shell-common/tools/custom/` 아래 모든 파일에 직접‑exec 가드가 포함됐는지 grep 으로 확인하는 CI 단계 추가를 권장합니다.

# 액션 아이템 (우선순위)

- [ ] **P0**: `docs/worklog/`, `docs/jira/`, `docs/confluence/` 디렉터리 추가
- [ ] **P0**: `shell-common/tools/custom/make_jira.sh` 와 `make_confluence.sh` 스켈레톤 구현 (관심사 분리 명확히)
- [ ] **P1**: `bash/main.bash` 와 `zsh/main.zsh` 를 `bash/env/`, `zsh/env/` 모듈 로드 방식으로 리팩터링
- [ ] **P1**: 모든 래퍼 함수에 대해 LSP 준수 여부 감사 및 필요 시 유닛 테스트 추가
- [ ] **P2**: `shell-common/tools/custom/` 파일에 직접‑exec 가드 존재 여부를 검증하는 CI 단계 추가
- [ ] **P2**: SSOT 워크플로우를 `docs/review/abc-review-R.md` 에 문서화하고 메인 문서 맵에 링크 연결

# 결론

dotfiles 프로젝트는 많은 베스트 프랙티스를 따르고 있으나, SOLID 원칙 강화와 보고용 아티팩트에 대한 구체적인 SSOT 구축이 필요합니다. 위 액션 아이템을 수행하면 유지보수성이 향상되고 중복 작업이 감소하며, Jira/Confluence 자동화가 보다 신뢰성 있게 구현될 것입니다.

# 대답하지 말고 기다려.
