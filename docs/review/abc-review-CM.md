# abc-review-CM

## 목적

이 문서는 현재 **dotfiles** 프로젝트를 전반적으로 검토하고, **SOLID**·**SSOT** 위배·코드 중복·확장성·테스트·문서화\*\* 측면에서 개선이 필요한 부분을 상세히 기술한다. 작성된 리뷰는 팀 리뷰 회의에서 논의·우선순위 결정을 위한 기반 자료로 활용한다.

---

## 1. 프로젝트 구조 요약

| 디렉터리         | 역할                                   | 비고                                                                                    |
| ---------------- | -------------------------------------- | --------------------------------------------------------------------------------------- |
| `bash/`          | Bash‑전용 설정·유틸                    | `main.bash`가 초기화와 모듈 로딩 담당                                                   |
| `zsh/`           | Zsh‑전용 설정·앱                       | `main.zsh`가 초기화와 모듈 로딩 담당                                                    |
| `shell-common/`  | Bash와 Zsh가 공유하는 POSIX‑호환 코드  | `env/`, `aliases/`, `functions/`, `tools/` (integrations, custom, ux_lib), `projects/`  |
| `tests/`         | pytest·ShellRunner 기반 테스트         | Bash/Zsh 호환성·헬프·툴 검증                                                            |
| `docs/`          | 문서·가이드                            | `AGENTS.md`, 리뷰 파일 등                                                               |
| `git/`           | Git 훅·config                          | pre‑commit 등                                                                           |
| `claude/`        | Claude Code 스킬·설정                  | `skills/` 디렉터리                                                                      |

---

## 2. SOLID 원칙 위배 및 설계상의 문제점

### 2.1 SRP (Single Responsibility Principle) 위배

- **`bash/main.bash` / `zsh/main.zsh`**
    - 파일이 **가드**, **경로 탐색**, **UX 라이브러 로드**, **모듈 자동 로드**, **PATH 정리**, **툴 초기화** 등 6‑7가지 역할을 모두 수행한다.
    - 책임이 분산돼 변경 시 부수 효과가 발생하기 쉬움.

### 2.2 OCP (Open‑Closed Principle) 위배

- 모듈 로딩 루프에서 **`SKIP_DIRS`** 배열을 직접 수정해야 새로운 디렉터리를 제외/포함한다.
- 새로운 플러그인·통합을 추가하려면 기존 `main.bash`·`main.zsh` 를 수정해야 함.

### 2.3 DIP (Dependency Inversion Principle) 위배

- 경로 탐지 로직(`_SCRIPT_PATH`, `_ZSH_SCRIPT_DIR`)이 **구체적인 파일 시스템**에 직접 의존한다.
- 상위 스크립트가 하위 로직을 직접 호출하고 있어 테스트가 어려움.

### 2.4 ISP (Interface Segregation Principle) 위배

- `ux_lib` 가 **색·출력·에러·프로그레스** 등 모든 UI 기능을 하나의 파일에 담고 있다.
- 가벼운 스크립트가 UI 전부를 의존하게 되며, 필요 없는 기능까지 로드한다.

### 2.5 DRY 위배

- `DOTFILES_ROOT`, `SHELL_COMMON` 초기화와 `opencode` PATH 추가 로직이 **bash**와 **zsh** 두 곳에 복제돼 있다.
- 동일 로직을 여러 파일에 중복 구현하면 수정 시 놓치는 부분이 발생한다.

---

## 3. SSOT (Single Source of Truth) 위배

| 항목                             | 현재 위치                                       | 문제점                                                        |
| -------------------------------- | ----------------------------------------------- | ------------------------------------------------------------- |
| `DOTFILES_ROOT` / `SHELL_COMMON` | `bash/main.bash` **및** `zsh/main.zsh`          | 두 곳을 동시에 수정해야 함 → 경로 변경 시 일관성 확보 어려움  |
| UX 라이브러 경로                 | 두 메인 스크립트에서 직접 `source …/ux_lib.sh`  | 경로 이동 시 두 파일을 모두 업데이트 필요                     |
| `opencode` PATH 추가             | `bash/main.bash`에만 존재                       | Zsh에서도 동일 PATH가 필요할 때 누락 위험                     |
| Direct‑Exec Guard 패턴           | 각 `tools/custom/*.sh` 에 개별 구현             | Guard 형식이 일관되지 않으면 pre‑commit이 통과하지 못함       |

---

## 4. 구체적인 리팩터링·개선 제안

### 4.1 공통 초기화 모듈 도입 (`shell-common/util/init_common.sh`)

- **책임**: 인터랙티브 가드, `DOTFILES_ROOT`·`SHELL_COMMON` 탐지, UX 라이브러 로드, `opencode` PATH 설정(옵션 변수 `ENABLE_OPENCODE`).
- **효과**: SRP 달성, 중복 제거, 테스트 용이성.
- **사용 방식**: `bash/main.bash`와 `zsh/main.zsh`는 `source "${SHELL_COMMON}/util/init_common.sh"` 후 **쉘‑전용** 설정만 남긴다.

### 4.2 플러그인형 로더 (`shell-common/util/loader.sh`)

```bash
# usage: load_category "aliases"   # loads ${SHELL_COMMON}/aliases/*.sh
#        load_category "functions"
#        load_category "integrations"
load_category() {
    local category="$1"
    local dir="${SHELL_COMMON}/${category}"
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*.sh; do
        [[ -f "$f" ]] || continue
        [[ "$f" == *.local.sh ]] && continue
        safe_source "$f" "Failed to load $category" || true
    done
}
```

- `SKIP_DIRS` 를 **`loader_skip.conf`** 파일에 선언해 두면 로더 자체는 수정 없이 확장 가능.
- OCP와 DIP 모두 강화.

### 4.3 경로 해결 레이어 (`shell-common/util/path_resolver.sh`)

```bash
resolve_dotfiles_root() {
    local script_path="${BASH_SOURCE[0]:-${(%):-%N}}"   # bash 혹은 zsh 자동 지원
    local dir="$(cd "$(dirname "$script_path")" && pwd)"
    echo "${dir%/bash}"   # bash 혹은 zsh 를 부모 디렉터리로 반환
}
```

- `bash/main.bash`와 `zsh/main.zsh`는 `DOTFILES_ROOT=$(resolve_dotfiles_root)` 로 한 줄만 사용.
- 경로 변경 시 **단일 진실** 유지.

### 4.4 UX 라이브러 인터페이스 분리

- `ux_lib/ux_output.sh` : 색·문자 출력 함수 (`ux_header`, `ux_success`, `ux_error`).
- `ux_lib/ux_progress.sh` : 프로그레스·스피너.
- `ux_lib/ux_error.sh` : `set -e` 트랩·에러 로그.
- 필요에 따라 **가벼운 스크립트**는 `ux_output.sh`만 `source` 하면 된다.

### 4.5 `opencode` PATH 관리 표준화

- 새 파일 `shell-common/tools/integrations/opencode.sh` 에서 PATH 추가 로직을 구현하고, **통합 로더** 단계에서 자동 로드하도록 한다.
- Zsh에서도 동일 PATH가 보장된다.

### 4.6 Direct‑Exec Guard 일관화

- `shell-common/tools/custom/` 에는 **템플릿 파일** `guard_template.sh` 를 두고, 새 스크립트는 `cat guard_template.sh > new_script.sh && vim` 형태로 시작한다.
- pre‑commit 훅이 `grep -L "\[ \"\${BASH_SOURCE\[0\]}\" = \$0 \]"` 로 누락을 잡는다.

### 4.7 테스트·CI 강화

| 테스트                          | 내용                                                                            | 위치     |
| ------------------------------- | ------------------------------------------------------------------------------- | -------- |
| `test_path_resolver.sh`         | `resolve_dotfiles_root` 가 심볼릭·절대·상대 경로 모두 올바르게 반환하는지 확인  | `tests/` |
| `test_loader.sh`                | `load_category` 가 `loader_skip.conf` 를 respect 하는지 검증                    | `tests/` |
| `test_opencode_integration.sh`  | `opencode.sh` 가 `PATH` 에 올바르게 삽입되는지 검증 (bash·zsh 모두)             | `tests/` |

- 기존 `tox` 에 위 스크립트들을 포함시키고, **CI 파이프라인**에 자동 실행하도록 설정.

### 4.8 문서·가이드 정비

- `docs/README.md` 에 **프로젝트 초기화 흐름**(setup → install → reload) 다이어그램 추가.
- `shell-common/AGENTS.md` 에 **플러그인 로더 사용법**과 `loader_skip.conf` 포맷 예시 삽입.
- `UX_GUIDELINES.md` 를 `ux_lib/README.md` 로 이동하고, **API 레퍼런스 표**를 추가.

---

## 5. 기대 효과

| 항목                      | 기대 효과                                                                          |
| ------------------------- | ---------------------------------------------------------------------------------- |
| 책임 분리 (SRP)           | `main.bash`·`main.zsh` 파일 라인 수 40 % 감소, 가독성·유지보수성 향상              |
| 경로 중앙화 (SSOT)        | 경로 변경 시 단일 파일만 수정, CI 파이프라인 오류 감소                             |
| 플러그인 로더 (OCP/DIP)   | 새로운 모듈·통합을 추가할 때 기존 코드 수정 불필요, 확장성 대폭 개선               |
| UX 인터페이스 분리 (ISP)  | 경량 스크립트가 불필요한 로드 없이 빠르게 실행, 테스트 시 의존성 감소              |
| 테스트 커버리지 ↑         | `path_resolver`, `loader`, `opencode` 등 핵심 로직에 단위 테스트 추가 → 회귀 방지  |
| 문서 일관성 ↑             | 신규 개발자 onboarding 시간 감소, 팀 내 표준화 촉진                                |

---

## 6. 액션 아이템 (우선순위별)

1. **공통 초기화·로드·경로 모듈 구현** – 담당: `devx` (1‑2 주)
2. **기존 `main.bash`·`main.zsh` 리팩터링** – 위 모듈만 호출하도록 변경 (1 주)
3. **`opencode` 통합 이동** – `tools/integrations/opencode.sh` 로 이동 후 로더에 포함 (0.5 주)
4. **UX 라이브러 파일 분리** – `ux_output.sh`, `ux_progress.sh`, `ux_error.sh` 생성 (1 주)
5. **테스트 스크립트 추가** – `test_path_resolver.sh`, `test_loader.sh`, `test_opencode_integration.sh` (1 주)
6. **문서 업데이트** – `README`, `AGENTS.md`, `UX_GUIDELINES.md` 재정비 (0.5 주)
7. **Pre‑commit 훅 검증** – Guard 템플릿 적용 여부 확인 스크립트 추가 (0.5 주)

---

## 7. 결론

본 리뷰는 현재 프로젝트가 **SOLID·SSOT** 원칙을 부분적으로만 만족하고 있음을 확인하였다. 제안된 리팩터링·모듈화 작업은 **코드 가독성, 유지보수성, 확장성**을 크게 향상시킬 뿐 아니라 **CI·테스트 안정성**을 강화한다. 위 액션 아이템을 순차적으로 구현하고, 팀 회의에서 우선순위를 조율한 뒤 PR 형태로 진행한다.
