# Maintenance Scripts

Dotfiles 유지보수를 위한 1회성/주기적 도구 모음

## 📁 포함된 스크립트

### analyze_shebangs.py
- **목적**: Shell 스크립트 shebang 일관성 분석
- **사용**: `python3 analyze_shebangs.py`
- **출력**: Bash 전용 기능 감지 및 올바른 shebang 권장
- **보고서 위치**: `docs/analysis/`

### check_bash_status.sh
- **목적**: Bash 파일 회귀 테스트 (Shell 버전)
- **사용**: `bash check_bash_status.sh`
- **기능**:
  - Syntax checking (bash -n)
  - Source testing (isolated/chain 모드)
  - Trace 로깅 (bash -x)
  - 상세 로그 파일 생성

### check_bash_status.py
- **목적**: Bash 파일 회귀 테스트 (Python 버전)
- **사용**: `python3 check_bash_status.py`
- **요구사항**: `pip install rich`
- **기능**:
  - Shell 버전과 동일한 테스트
  - Progress bar 및 rich formatting
  - 더 읽기 쉬운 출력 형식

### check_codex_skills_budget.py
- **목적**: Codex skill description 컨텍스트 예산 (~5440자) 초과 감지 (issue #216) + 개별 skill description 의 로더 하드 리밋 (1024자) 초과 감지 (issue #785)
- **사용**: `python3 check_codex_skills_budget.py [--budget N] [--top N] [--all] [--quiet] [--per-skill-max N]`
- **요구사항**: Python stdlib 만 (외부 의존성 없음)
- **기능**:
  - `claude/skills/*/SKILL.md` frontmatter 의 `description` 길이 합산
  - 가장 긴 설명 Top N 노출 (기본 10개)
  - 개별 skill 이 `--per-skill-max` (기본 1024자) 초과 시 종료 코드 1 — 로더가 해당 skill 을 silently drop 하기 전에 사전 차단
  - 총합 예산 초과 시 종료 코드 1, 트리밍 또는 `.codex-allowlist` 사용 안내

### check_gh_skill_host_pinning.py
- **목적**: `gh:*` 스킬의 `GH_HOST` pinning 계약 (issue #1403 / PR #1404) 위반 감지 (issue #1407)
- **사용**: `python3 check_gh_skill_host_pinning.py [--skills-dir PATH] [--prefix gh-] [--quiet]`
- **요구사항**: Python stdlib 만 (외부 의존성 없음)
- **기능**:
  - `claude/skills/gh-*/**/*.md` 의 실행 가능한 `gh` 호출을 전수 스캔 (backslash 연속 행은 논리 행으로 결합)
  - host 미고정 (`GH_HOST=` 접두사도 `--hostname` 도 없음) 시 위반
  - repo 미고정 (`--repo` 부재) 시 위반 — `gh gist` / `gh auth` 등 repo 스코프가 아닌 서브커맨드는 예외
  - `gh api` 는 `--repo` 플래그가 없으므로 경로에 `$TARGET_REPO` 를 요구하고, 리터럴 `{owner}/{repo}` placeholder 는 위반으로 잡는다 (암묵 해석 = #1403 의 조용한 오호스트 경로)
  - 위반 1건 이상이면 종료 코드 1, skills 디렉토리 부재 시 2
- **회귀 가드**: `tests/integration/test_gh_skill_host_pinning.py` 가 이 스크립트를 실 트리에 대해 돌린다

### check_split_skill_repos.py
- **목적**: #1410 으로 분리해 나간 스킬 레포가 등록값과 맞는지, 원본과 드리프트했는지 감시 (issue #1671)
- **사용**: `python3 check_split_skill_repos.py [--check contract|drift|all] [--repo-root PATH] [--owner NAME] [--quiet]`
- **요구사항**: Python stdlib 만 (외부 의존성 없음) + 네트워크 (`git clone --depth 1`)
- **기능**:
  - 대상 레포를 `claude/plugin/{marketplaces,plugins}.json` 에서 유도 — 손으로 유지하는 표 없음 (NF-2)
  - F-1: 원격 `.claude-plugin/marketplace.json` 이 등록된 `<plugin>@<marketplace>` 를 실제로 제공하는지 검사
  - F-2: 분리본과 `claude/skills/` 원본을 SKILL.md + `references/` 합집합의 정규화 라인 집합으로 비교 — 네임스페이스 재작성·100줄 상한 분할은 오탐이 되지 않는다
  - 스킬 짝짓기는 이름이 아니라 내용 유사도로 하고, 짝을 못 찾으면 조용히 넘기지 않고 보고
  - 위반/드리프트 1건 이상이면 종료 코드 1, 등록 SSOT 를 못 읽으면 2
- **회귀 가드**: `tests/integration/test_split_skill_repos.py` 가 순수 로직을 픽스처로 오프라인 검증 (네트워크는 `RemoteSource` 뒤에 격리 — NF-1)
- **정기 실행**: `.github/workflows/split-skill-repo-audit.yml` (주 1회) / 수동은 `mise run audit-split-repos`

## 💡 사용 시나리오

### Shebang 검증
- 새로운 shell 스크립트 추가 후 shebang 검증
- 대규모 리팩토링 후 일관성 확인
- Bash/POSIX 호환성 검토

### Bash 파일 회귀 테스트
- Bash 파일 수정 후 동작 검증
- 대규모 리팩토링 후 회귀 방지
- 새로운 .bash 파일 추가 후 통합 테스트

### Codex skill 예산 감시
- 신규 skill 추가 / description 갱신 후 합계 점검
- 트렁케이션 경고 발견 시 origin 추적
- `.codex-allowlist` 운영 결정 자료로 활용

## 🔗 관련 문서

- [Shebang 분석 보고서](../../docs/analysis/SHEBANG_ANALYSIS_REPORT.md)
- [검증된 수정 가이드](../../docs/analysis/VERIFIED_PRIORITY_FIXES.md)
