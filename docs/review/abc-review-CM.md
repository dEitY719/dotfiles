# abc-review-CM

## 목적

- 현재 `dotfiles` 프로젝트 구조와 로딩 메커니즘을 검토하여 **SOLID 원칙** 및 **SSOT(Single Source Of Truth)** 위배 여부를 파악하고, 향후 유지보수와 확장성을 높이기 위한 구체적인 개선 방안을 제시한다.

## 현황 요약

- **공통 영역**: `shell-common/` (env, aliases, functions, tools, projects)
- **Bash 전용**: `bash/` (env, util, `main.bash` 등)
- **Zsh 전용**: `zsh/` (env, app, `main.zsh` 등)
- **로드 순서**: `bash/main.bash`와 `zsh/main.zsh`는 각각
    1) 인터랙티브 가드
    2) 환경 변수(`DOTFILES_ROOT`, `SHELL_COMMON`) 설정
    3) UX 라이브러 로드
    4) env → aliases → functions → integration → projects → shell‑specific 로드
- **테스트·품질**: `tox`(ruff, mypy, shellcheck, shfmt) + `pytest`

## SOLID 위배 사례

| 원칙                                      | 위배 위치                                              | 설명                                                                                                                                                                                             |
| ----------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **SRP (Single Responsibility Principle)** | `bash/main.bash` / `zsh/main.zsh`                      | 한 파일이 **가드**, **경로 초기화**, **UX 라이브러 로드**, **모듈 자동 로드**, **PATH 정리**, **툴 초기화** 등 다목적 역할을 수행한다. 각각을 별도 모듈로 분리하면 책임이 명확해진다.            |
| **OCP (Open‑Closed Principle)**           | 모듈 로딩 루프 (`for dir in "${DOTFILES_BASH_DIR}"/*`) | 새로운 디렉터리를 추가할 때 `SKIP_DIRS` 배열을 수정해야 한다. 로딩 로직을 플러그인‑형식으로 추출하면 기존 코드를 건드리지 않고 확장 가능해진다.                                                  |
| **DIP (Dependency Inversion Principle)**  | 경로 탐지 로직 (`_SCRIPT_PATH`, `_ZSH_SCRIPT_DIR`)     | `main.bash`와 `main.zsh`가 **구체적인 파일 시스템**에 직접 의존한다. 경로 탐지를 `shell-common/util/path_resolver.sh`와 같은 추상 레이어로 이동시켜 상위 스크립트는 인터페이스만 사용할 수 있다. |
| **ISP (Interface Segregation Principle)** | UX 라이브러 호출 (`ux_header`, `ux_success` 등)        | 현재는 `ux_lib`가 전체 스크립트에서 **전역 의존**으로 사용된다. UI‑전용 함수와 로깅·에러 처리 함수를 별도 파일로 나누면, 가벼운 스크립트는 UI 없이도 동작할 수 있다.                             |

## SSOT 위배 사례

1. **`DOTFILES_ROOT` / `SHELL_COMMON` 정의가 두 군데**
      - `bash/main.bash`와 `zsh/main.zsh` 각각에 동일한 경로 탐지 로직이 존재한다.
      - 경로가 변경되면 두 파일을 모두 수정해야 하므로 **단일 진실의 원천**이 아니다.
2. **UX 라이브러 경로 하드코딩**
      - `bash/main.bash`와 `zsh/main.zsh` 모두 `source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"` 를 직접 사용한다.
      - 추후 라이브러 위치가 바뀔 경우 두 군데를 동시에 업데이트해야 함.
3. **`opencode` PATH 추가**가 `bash/main.bash`에만 존재하고 `zsh/main.zsh`에는 없으며, 다른 스크립트에서도 같은 로직을 재작성한다.
      - 동일한 PATH 조작을 여러 파일에 흩어놓음으로써 **중복된 진실**이 생성된다.

## 주요 개선 방안

### 1. 공통 초기화 모듈 도입

- `shell-common/util/init_common.sh` 를 신규 생성하고 아래 책임을 담는다.
    - 인터랙티브 가드 (`[[ $- == *i* ]]`)
    - `DOTFILES_ROOT`, `SHELL_COMMON` 자동 탐지
    - UX 라이브러 로드
    - `opencode` PATH 추가 (옵션 변수 `ENABLE_OPENCODE` 로 제어)
- `bash/main.bash`와 `zsh/main.zsh`는 오직 **모듈 로드**와 **쉘‑전용 설정**만 담당하도록 축소한다.

### 2. 로딩 메커니즘 플러그인화

- `shell-common/util/loader.sh` 로드 함수를 정의한다.
    - `load_category "env"`, `load_category "aliases"` 등 호출 방식으로 변경
    - `SKIP_DIRS` 를 파일(`loader_skip.conf`)에 선언해 두면 로더 자체는 수정 없이 확장 가능

### 3. 경로 탐지 중앙화

- `path_resolver.sh` 에서 `resolve_dotfiles_root` 함수를 제공하고, `bash/main.bash`와 `zsh/main.zsh`는 `source "${SHELL_COMMON}/util/path_resolver.sh"` 후 `DOTFILES_ROOT=$(resolve_dotfiles_root)` 형태로 사용한다.
- 이렇게 하면 **단일 진실**이 유지되고 테스트도 쉬워진다.

### 4. UX 라이브러 인터페이스 분리

- `ux_lib/ux_output.sh` (색·프린트), `ux_lib/ux_error.sh` (에러·트랩) 등 기능별로 파일을 나눈다.
- 경량 스크립트는 `source "${SHELL_COMMON}/tools/ux_lib/ux_output.sh"` 만 호출해도 동작한다.

### 5. `opencode` PATH 관리 표준화

- `shell-common/tools/integrations/opencode.sh` 를 만든다.
- 해당 파일을 `tools/integrations` 로드 단계에서 자동 로드하도록 하면, Bash/Zsh 모두 동일한 로직을 공유한다.

### 6. 테스트·CI 보강

- `tests/test_path_resolution.py` (Python) 혹은 `tests/test_path_resolver.sh` (Shell) 를 추가해 `resolve_dotfiles_root` 가 다양한 심볼릭·실제 경로에서 올바르게 동작하는지 검증한다.
- 로더 플러그인 로직에 대한 **unit test** 를 `tests/test_loader.sh` 로 추가해 `SKIP_DIRS` 파일을 변경했을 때 로드 결과가 예상대로 유지되는지 확인한다.

## 기대 효과

| 개선 항목                | 기대 효과                                                 |
| ------------------------ | --------------------------------------------------------- |
| 책임 분리 (SRP)          | `main.bash`·`main.zsh` 파일 크기 40% 감소, 가독성 향상    |
| 경로 중앙화 (SSOT)       | 경로 변경 시 1 파일만 수정, CI 파이프라인 오류 감소       |
| 플러그인 로더 (OCP/DIP)  | 새로운 모듈 추가 시 로더 코드 수정 불필요, 확장성 증대    |
| UX 인터페이스 분리 (ISP) | 경량 스크립트에서 불필요한 의존 제거, 실행 속도 약간 개선 |
| 테스트 추가              | 회귀 방지, 향후 리팩터링 안전성 확보                      |

## 결론 및 액션 아이템

1. `shell-common/util/init_common.sh`, `loader.sh`, `path_resolver.sh` 파일을 **설계·구현** (담당: `devx`).
2. 기존 `bash/main.bash`와 `zsh/main.zsh`를 **리팩터링**하여 위 모듈만 호출하도록 변경 (담당: `devx`).
3. `opencode` 통합을 `tools/integrations/opencode.sh` 로 이동하고 로더에 포함 (담당: `devx`).
4. 신규 테스트 파일 3개(`test_path_resolver.sh`, `test_loader.sh`, `test_opencode_integration.sh`) 작성 및 `tox`에 포함 (담당: `qa`).
5. 리뷰 후 **PR** 를 열어 코드베이스에 반영하고, `tox` 및 CI가 통과하면 **배포**.

---

_작성자: CodeMate (자동 분석)_
_생성일: $(date '+%Y-%m-%d')_

# 대답하지 말고 기다려.
