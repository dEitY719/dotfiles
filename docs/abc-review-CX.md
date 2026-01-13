# shell-common/*.sh SOLID & SSOT 리뷰 (CX)

## 1) Reviewer Info

- Reviewer: GPT-5.2 (Codex CLI)
- Date: 2026-01-13
- Scope: `shell-common/**/*.sh` 전체 (총 127개 파일, 16,429 LOC)
- 목적: 동료 리뷰를 위한 개선 포인트/리스크 정리 (구현 여부 결정용)

## 2) 구조 요약 (현재 관찰)

- 로더 동작(중요): `bash/main.bash`, `zsh/main.zsh`에서 `shell-common/{env,aliases,functions,tools/integrations,projects}/*.sh`를 전부 `source`합니다. `tools/custom`는 “실행 전용”이라 로더가 자동 로드하지 않습니다.
- 현재 구조(대체로 의도는 명확):
  - `env/`: 환경변수/경로
  - `aliases/`: 별칭
  - `functions/`: 함수/커맨드
  - `tools/integrations/`: 외부 도구 통합(자동 로드)
  - `tools/custom/`: 설치/진단/유틸 스크립트(명시 실행)
  - `projects/`: 프로젝트별 유틸(자동 로드)
- “계약(Contract)” 불일치 징후:
  - `shell-common/AGENTS.md`는 “POSIX 호환”을 강조하지만, 실제 `shell-common/**/*.sh`에는 bash 전용/의존 구현이 다수 존재합니다(예: `declare -A`, `mapfile`, `[[ ... ]]`, `BASH_SOURCE` 등).
  - 또한 일부 `.local.sh`는 “값 정의”를 넘어 “상태 변경(파일 수정, npm config set 등)”까지 수행합니다.

## 3) SOLID 평가 (각 10점 만점)

- SRP(단일 책임): 5/10
  - 디렉터리 분리는 되어 있으나, “자동 로드 시점”에 파일/시스템 상태 변경을 수행하는 스크립트가 있어 책임 경계가 흐려집니다.
- OCP(개방-폐쇄): 5/10
  - 확장 지점(새 스크립트 추가)은 좋지만, 서비스/설정이 스크립트 내부 배열/하드코딩으로 박혀 있어 확장 시 코드 수정이 빈번합니다.
- LSP(리스코프 치환): 7/10
  - 래퍼/헬퍼는 대체로 원 명령의 기대 동작을 유지하나, 일부는 쉘/OS에 따라 “존재/부재”가 불명확합니다(동일 명령이 bash/zsh에서 다르게 동작할 가능성).
- ISP(인터페이스 분리): 6/10
  - 도움말/진단/설치가 분리된 곳도 있으나, 큰 통합 스크립트(예: DB, LLM, 도커)는 기능 폭이 넓습니다.
- DIP(의존성 역전): 4/10
  - `ux_lib`가 존재하지만 많은 스크립트가 여전히 `echo/printf` + 컬러 변수에 직접 의존하며, 일부는 로드 시 자동 설치/파일 갱신까지 수행합니다.

총점(50점 만점): 27/50

## 3.1) 동료 피드백 반영 (G)

- 원칙 위반(또는 문서-현실 불일치)이 곧 “즉시 수정 필요”를 의미하지는 않습니다. 우선순위는 **운영 리스크/실제 버그 가능성** 중심으로 두는 것이 안전합니다.
- 특히 “자동 로드 시점”에 발생하는 설치/권한/네트워크 의존 부작용과, `.local.sh`의 중복 로딩/상태 변경은 실제 장애·성능 저하로 이어질 수 있어 P0로 유지합니다.
- 반면 경로 하드코딩, 프로젝트 로직 혼입, 디렉터리 계약(aliases/env에 함수) 등은 구조적으로는 개선 여지가 있지만, 현재 사용 패턴에서 문제가 보고되지 않았다면 **점진적 적용(P2~P3)**이 더 현실적일 수 있습니다.
- 대규모 일괄 리팩토링은 버그 유입 가능성이 높으므로, 작은 단위로 변경하고 검증하며 진행하는 접근을 권장합니다.

## 4) 이슈 (심각도별)

### High

#### H1. 자동 로드 시 “설치/권한 필요 작업” 수행 (SRP/DIP 위반 + 운영 리스크)

- 근거:
  - `shell-common/tools/integrations/claude.sh:46`에서 `ensure_jq()`가 `apt-get/brew/yum` 설치까지 수행하고,
  - `shell-common/tools/integrations/claude.sh:78`에서 파일이 source될 때 `ensure_jq`를 자동 호출합니다.
- 문제:
  - 셸 시작 시 sudo/패키지 설치/네트워크 의존 작업이 트리거될 수 있어 예측 불가능/느린 초기화/권한 프롬프트 발생.
  - CI/컨테이너/권한 제한 환경에서 “의도치 않은 설치 시도”가 초기화 실패로 연결될 수 있음.
  - “통합(Integration)”은 정의/래핑에 집중하고, 설치는 `tools/custom/`에서 명시 실행이 더 안전합니다.
- 권장:
  - 자동 호출 제거(또는 최소 “경고만” 출력).
  - `ensure_jq`는 `claude_init` 같은 명시 커맨드 실행 시에만 호출.
  - 설치는 `clinstall`(이미 존재) 또는 `tools/custom/install_*.sh`로 통일.

#### H2. `.local.sh` 로딩 순서/중복 로딩 문제 (SSOT/OCP 위반 + 사이드이펙트 중복)

- 현상 1: 로더는 `*.local.sh`도 glob에 포함해 먼저/같이 source합니다.
  - 예: `bash/main.bash:154` ~ `bash/main.bash:186`
  - 예: `zsh/main.zsh:103` ~ `zsh/main.zsh:148`
- 추가 리스크: 파일명 정렬(glob) 기준으로 `security.local.sh`가 `security.sh`보다 먼저 로드되는 등 “base → local” 순서가 보장되지 않습니다.
- 현상 2: 기본 스크립트가 다시 `.local.sh`를 source합니다.
  - 예: `shell-common/env/proxy.sh:37` ~ `shell-common/env/proxy.sh:40`
  - 예: `shell-common/env/security.sh:32` ~ `shell-common/env/security.sh:34`
  - 예: `shell-common/tools/integrations/npm.sh:127` ~ `shell-common/tools/integrations/npm.sh:132`
- 결과:
  - `.local.sh`가 “값 정의만” 한다면 중복 로딩은 낭비 수준일 수 있지만,
  - 실제로는 “상태 변경”이 있는 `.local.sh`도 존재하여(아래 H3), 중복 실행/순서 역전이 실질 버그로 이어질 수 있습니다.
- 권장(택1, SSOT로 결정 필요):
  - A) 로더에서 `*.local.sh`는 스킵하고, 각 기본 스크립트가 필요 시 “한 번만” 로드. (권장)
  - B) 로더에서 “기본 파일 → local 파일” 순으로 두 단계 로드(예: `*.sh` 중 `.local.sh` 제외 후 로드, 그 다음 `.local.sh` 로드)하고, 기본 스크립트의 재-source 제거.

#### H3. `.local.sh`가 설정 “적용(Apply)”까지 수행 (SSOT/SRP 위반 + 셸 시작 비용/부작용)

- 근거:
  - `shell-common/tools/integrations/npm.local.sh:27` ~ `shell-common/tools/integrations/npm.local.sh:33`에서 `~/.npmrc`를 수정/삭제할 수 있고,
  - `shell-common/tools/integrations/npm.local.sh:72` ~ `shell-common/tools/integrations/npm.local.sh:111`에서 `npm config set`을 수행합니다.
- 문제:
  - `.local.sh`의 역할이 “환경별 값 정의(SSOT)”인지 “적용 로직(절차)”인지 혼재.
  - 셸 시작 시 node/npm 실행이 반복될 수 있어 성능과 예측 가능성이 떨어집니다.
- 권장:
  - `.local.sh`는 “값만 정의”(예: `NPM_DESIRED_*`)로 제한.
  - 적용은 `setup.sh` 또는 `npm_apply_config` 같은 명시 커맨드로 분리.
  - 진단 스크립트(`tools/custom/check_npm.sh`)는 텍스트 패턴 매칭 대신 “변수/명령 결과 기반”으로 판단(SSOT 재사용).

#### H4. 하드코딩된 dotfiles 경로가 다수 존재 (SSOT 위반, 이식성 저하)

- 관찰:
  - `shell-common/**/*.sh`에서 `~/dotfiles` 및 `$HOME/dotfiles/...` 패턴이 광범위(예: 70+ 라인 수준)로 존재합니다.
  - 예: `shell-common/functions/mytool.sh:8`, `shell-common/tools/integrations/codex.sh:33`, `shell-common/tools/integrations/docker.sh:476` 등.
- 문제:
  - 리포지토리 위치가 `~/dotfiles`가 아닐 때 즉시 깨짐.
  - 동일 상수가 여러 곳에 분산(SSOT 위반).
- 우선순위 메모(G 반영):
  - 현재 설치 경로가 고정(`~/dotfiles`)이고 다른 경로 사용 계획이 없다면, 운영 리스크는 상대적으로 낮아 P2로 점진 적용하는 접근도 가능합니다.
- 권장:
  - 실행/로딩 시 이미 세팅되는 `DOTFILES_ROOT`, `SHELL_COMMON`를 “유일한 경로 SSOT”로 사용.
  - 공통 헬퍼(예: `shell_common_resolve()` 또는 `dotfiles_root_resolve()`)를 하나로 두고 모든 래퍼가 이를 사용.
  - `tools/custom/init.sh`의 “동적 DOTFILES_ROOT 탐지” 패턴을 `functions/`와 `tools/integrations/`에도 재사용하도록 일반화.

#### H5. 공유 통합 스크립트에 프로젝트/환경 전용 로직 혼입 (SRP/OCP 위반)

- 예시:
  - `shell-common/tools/integrations/litellm.sh:399` ~ `shell-common/tools/integrations/litellm.sh:400`에서 source 시점에 `_init_litellm_env`를 자동 실행(프로젝트 디렉터리 탐색/환경 변수 export).
  - `shell-common/tools/integrations/mysql.sh`는 `services=(dmc_dev, dmc_test ...)` 등 특정 프로젝트 성격의 설정을 포함.
  - `shell-common/aliases/disk_usage.sh:10`의 `src/database/data/*.sql`은 프로젝트 경로 가정.
- 문제:
  - “공유 레이어”가 특정 프로젝트/개인 환경에 강하게 결합되면, 다른 환경에서 불필요한 로딩/오동작/유지보수 부담이 증가.
- 우선순위 메모(G 반영):
  - 현재 사용 패턴이 단일 프로젝트 중심이고 충돌/혼란이 없다면, “완벽 분리”보다 “문제 발생 시 분리”가 비용 대비 안전할 수 있어 P2로 하향 가능합니다.
- 권장:
  - 프로젝트 전용은 `shell-common/projects/`로 이동(예: litellm, dmc 관련).
  - `tools/integrations/`는 “도구 자체”의 일반 통합에 집중.
  - source 시 자동 실행(디렉터리 탐색, 설정 파일 생성 등)은 “명시 커맨드 실행 시”로 지연.

### Medium

#### M1. 디렉터리 계약 위반: `env/`에 함수, `aliases/`에 함수 포함 (SRP/구조 일관성)

- 근거:
  - `shell-common/env/path.sh:16`에 `clean_paths()` 함수 존재.
  - `shell-common/aliases/core.sh:10`, `shell-common/aliases/directory.sh:11`, `shell-common/aliases/kill.sh:3` 등에서 함수 정의.
- 문제:
  - 로딩 순서/의존성 추적이 어려워지고 “어디에 무엇을 두어야 하는가” 규칙이 약해짐.
- 권장:
  - `aliases/`는 alias만 두고, 함수는 `functions/`로 이동 후 alias로 연결.
  - `env/`는 export만 유지하고, `clean_paths`는 `functions/`로 분리하거나 로더에서 1회 실행하는 정책으로 명확화.
  - (G 반영) 신규/수정 코드부터 규칙을 적용하고, 기존 코드는 “문제 발생 또는 대규모 정리 시”로 미루는 점진 접근이 안전합니다.

#### M2. “Auto-generated from bash/app/*”의 SSOT/재생성 파이프라인 불명확

- 근거: 아래 파일들이 헤더에 “Auto-generated”를 표기합니다.
  - `shell-common/tools/integrations/{gpu,litellm,nvm,pyenv,python,uv,zsh}.sh`
- 문제:
  - 실제 생성 스크립트/검증(예: CI에서 diff 체크)이 없으면 원본과 산출물이 쉽게 드리프트(SSOT 붕괴).
  - “SSOT가 bash/app인지 shell-common인지”가 불명확해 변경 규칙이 혼란스러움.
- 권장:
  - SSOT를 명확히 1곳으로 결정(권장: “공유 기능은 shell-common을 SSOT”).
  - 생성이 필요하다면 `tools/custom/`에 “regen 스크립트”를 두고, `tox` 또는 CI에서 재생성 결과 diff가 없음을 보장.
  - (G 반영) 실제 드리프트/유지보수 비용이 관측되지 않는다면, 파이프라인 구축은 “선택”으로 두고 필요 시에만 도입하는 것이 안전합니다.

#### M3. 출력/UX 의존성 일관성 부족 (DIP 위반 + 유지보수 비용)

- 관찰:
  - `ux_lib`가 존재하지만 다수 스크립트가 `echo`/`printf` 및 컬러 변수 직접 조합으로 출력합니다.
  - 예: `shell-common/functions/git.sh:78` ~ `shell-common/functions/git.sh:100`, `shell-common/tools/integrations/docker.sh:39` 등.
- 문제:
  - UX 일관성 저하 + 출력 스타일 변경 시 파편화.
- 권장:
  - “출력은 ux_lib만 사용”을 실제 코드로 강제(예: `ux_blank`, `ux_code`, `ux_kv` 같은 최소 API 추가 후 기존 스크립트 점진 교체).
  - (G 반영) 기능 리스크가 아니라 UX 품질 성격이므로, 신규/수정 시에만 점진 적용하는 편이 안전합니다.

#### M4. 쉘/OS 호환성 계약이 문서와 다름 (SSOT: “지원 범위” 불일치)

- 예:
  - `shell-common/tools/integrations/postgresql.sh`는 `mapfile`, `declare -A`, bash 정규식 등 bash 전용 구현을 포함하지만 상단에 zsh/공유를 명확히 차단하지 않습니다(`shell-common/tools/integrations/postgresql.sh:11` ~ `shell-common/tools/integrations/postgresql.sh:40` 참고).
  - `shell-common/functions/zsh.sh`는 `find -printf` 사용 등 GNU 의존이 있어 macOS에서 실패 가능성이 있습니다(`shell-common/functions/zsh.sh:50`).
- 권장:
  - “shell-common은 bash+zsh 공통(비-POSIX)”로 규정할지, “진짜 POSIX”로 갈지 결정.
  - bash-only는 `tools/integrations/*`에서 명시 가드(`[ -n "$BASH_VERSION" ] || return 0`)로 조용히 스킵.
  - GNU 의존은 OS 감지 또는 대체 구현 제공.
  - (G 반영) 실제 지원 대상(예: Linux + bash/zsh)이 명확하고 다른 환경 이슈가 없다면, 문서를 현실에 맞게 조정하는 선택지도 있습니다.

### Low

#### L1. 네이밍/스코프 관례가 혼재 (일관성/검색성 저하)

- 예:
  - 함수명이 `snake_case`와 `kebab-case`가 혼재(예: `shell-common/tools/integrations/uv.sh:36`의 `uv-install()`).
  - 일부 alias 파일에서 `PORT`, `PID` 같은 전역 변수를 사용(`shell-common/aliases/kill.sh:9` ~ `shell-common/aliases/kill.sh:14`).
- 권장:
  - 함수는 `snake_case`, 사용자 커맨드는 alias로 `kebab-case`를 제공하는 규칙을 일관되게 적용.
  - 함수 내부 변수는 `local`로 한정.

## 5) Action Items (우선순위)

- [ ] P0: 셸 초기화 시 자동 설치/권한 작업 제거 (`shell-common/tools/integrations/claude.sh:78` 등)
- [ ] P0: `.local.sh` 로딩 정책 SSOT 확정 및 중복 로드 제거(로더/기본 스크립트 중 한쪽으로 정리)
- [ ] P0: `.local.sh`는 “값 정의만” 하도록 정리하고, 적용은 명시 커맨드로 분리(`npm.local.sh` 우선)
- [ ] P2: dotfiles 경로 SSOT를 `DOTFILES_ROOT`/`SHELL_COMMON`로 통일(하드코딩 제거; 신규/수정부터 점진 적용)
- [ ] P2: 프로젝트 전용 로직은 충돌/혼란 발생 시 `projects/`로 이동(완벽 분리보다 “문제 발생 시 분리” 우선)
- [ ] P3: `env/`/`aliases/`의 “함수 포함” 문제 정리(대규모 정리 시 또는 문제 발생 시)
- [ ] 선택: “Auto-generated” 파이프라인 정식화(재생성 스크립트 + diff 체크; 드리프트가 관측될 때)
- [ ] 선택: `ux_lib` 중심 출력으로 점진 정리(UX 개선 필요 시)
- [ ] 선택: OS별 GNU 의존 제거/가드(find -printf 등; 실제 지원 범위 확정 후)

## 6) 결론

- 현재 `shell-common/`은 “공유 레이어”라는 큰 방향성은 매우 좋지만, 실제 구현은 (1) 초기화 시점의 사이드이펙트, (2) `.local.sh` 로딩 정책, (3) dotfiles 경로 하드코딩으로 인해 SOLID/SSOT 관점 리스크가 커져 있습니다.
- 동료 피드백(G) 기준으로는 “초기화 부작용 제거(P0)”와 “로딩/설정 SSOT 확정(P0)”에 우선 집중하고, 그 외 구조 개선은 실제 문제/수요가 있을 때 점진적으로 진행하는 편이 안전합니다.
