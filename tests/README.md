# Test Suite

dotfiles 프로젝트의 테스트 스위트. bats 쉘 유닛 테스트, pytest 통합 테스트, golden rules 정적 검사로 구성.

## Quick Start

```bash
# 전체 실행 (bats → golden rules → pytest)
./tests/test

# 옵션
./tests/test -v          # verbose
./tests/test -s          # serial (parallel 비활성)
./tests/test -h          # 도움말
```

## 디렉토리 구조

```
tests/
├── test                       # 통합 러너 (bats + golden rules + pytest)
├── AGENTS.md                  # AI 에이전트용 모듈 컨텍스트
├── README.md                  # 이 파일
│
├── bats/                      # 쉘 유닛 테스트 (bats-core)
│   ├── test_helper.bash       # 공통 헬퍼 (환경 격리, run_in_bash/run_in_zsh)
│   ├── lib/                   # git submodules
│   │   ├── bats-core/         #   bats 테스트 프레임워크
│   │   ├── bats-support/      #   출력 헬퍼
│   │   └── bats-assert/       #   assertion 라이브러리
│   ├── init/                  # 초기화 & 로딩 테스트
│   │   ├── sourcing.bats      #   소싱 메커니즘, 함수/alias 로딩
│   │   └── env_vars.bats      #   환경변수 설정 검증
│   ├── functions/             # 핵심 유틸리티 함수 테스트
│   │   ├── git.bats           #   git_log, worktree, ssh_check
│   │   ├── file_cleanup.bats  #   del_file, 기본 패턴
│   │   ├── devx.bats          #   devx 함수, usage, 에러
│   │   └── tmux_spawn.bats    #   tmux_spawn/teardown
│   └── tools/                 # 커스텀 툴 드라이런
│       └── custom_tools.bats  #   syntax, shebang, check_* 개별 검증
│
├── integration/               # pytest 통합 테스트 (cross-shell 패리티)
│   ├── conftest.py            # shell_runner fixture, 환경 격리
│   ├── test_compatibility.py  # bash/zsh 초기화 패리티 (22 tests)
│   ├── test_help_topics.py    # 34개 help 토픽 검증 (136 tests)
│   ├── test_mytool_help.py    # mytool-help 함수 동작 (14 tests)
│   └── test_file_cleanup.py   # del_file 기본 패턴 (6 tests)
│
└── golden_rules/              # 정적 분석 규칙 검사
    └── test_golden_rules.sh   # 5개 골든 룰 (경로, 가드, echo, 이모지, POSIX)
```

## 테스트 레이어

### 1. Bats — 쉘 유닛 테스트

쉘 함수 단위 테스트. 각 테스트는 bash/zsh 서브프로세스에서 격리 실행.

```bash
# 전체 bats 실행
./tests/bats/lib/bats-core/bin/bats tests/bats/init tests/bats/functions tests/bats/tools

# 특정 디렉토리
./tests/bats/lib/bats-core/bin/bats tests/bats/functions/

# 특정 파일
./tests/bats/lib/bats-core/bin/bats tests/bats/functions/git.bats
```

**헬퍼 함수 (`test_helper.bash`):**

```bash
# bash 서브프로세스에서 dotfiles 로드 후 명령 실행
run_in_bash 'declare -f git_log >/dev/null && echo ok'
assert_success
assert_output --partial "ok"

# zsh 서브프로세스
run_in_zsh 'alias my-help'
assert_success
```

**중요:** bats 테스트는 dotfiles를 직접 source하지 않고, 반드시 `run_in_bash`/`run_in_zsh` 서브프로세스 래퍼를 사용해야 합니다. bats 환경과 dotfiles의 alias/함수가 충돌하기 때문입니다.

### 2. Pytest — 통합 테스트

cross-shell 패리티 검증과 help 시스템 동작 테스트. `shell_runner` fixture으로 격리.

```bash
# 전체 pytest 실행
pytest tests/integration/

# 특정 파일
pytest tests/integration/test_help_topics.py -v

# 특정 테스트
pytest tests/integration/test_compatibility.py::TestDotfilesInitialization::test_bash_initialization

# serial 실행 (xdist 비활성)
pytest tests/integration/ -o 'addopts=-v --strict-markers' -p no:xdist
```

**shell_runner fixture (`conftest.py`):**

```python
def test_example(shell_runner):
    result = shell_runner("bash", "echo $SHELL_COMMON")
    assert result.exit_code == 0
    assert "shell-common" in result.stdout
```

### 3. Golden Rules — 정적 분석

소스 코드의 컨벤션 준수를 정적으로 검사.

```bash
bash tests/golden_rules/test_golden_rules.sh
```

| Rule | 검사 내용 |
|------|-----------|
| 1 | main.bash/main.zsh에 하드코딩된 경로 없음 |
| 2 | 커스텀 툴에 direct-exec 가드 존재 |
| 3 | shell-common/functions에서 raw echo 미사용 (ux_lib 사용) |
| 4 | 소스 코드에 이모지 없음 |
| 5 | shell-common에서 POSIX 준수 |

## 환경 변수

| 변수 | 용도 |
|------|------|
| `DOTFILES_TEST_MODE=1` | 테스트 모드. init.sh가 조기 반환하여 설치/부수효과 방지 |
| `DOTFILES_FORCE_INIT=1` | 비대화식 쉘에서도 전체 초기화 강제 |
| `DOTFILES_ROOT` | 리포지토리 루트 경로 (conftest/test_helper가 자동 감지) |
| `SHELL_COMMON` | `$DOTFILES_ROOT/shell-common` 경로 |

커스텀 툴에서 테스트 모드를 감지하려면:

```bash
if [ "${DOTFILES_TEST_MODE:-0}" = "1" ]; then
    return 0  # 외부 작업 스킵
fi
```

## 테스트 추가 가이드

### 새 쉘 함수 추가 시

`tests/bats/functions/`에 `.bats` 파일 생성:

```bash
#!/usr/bin/env bats
load '../test_helper'

setup() { setup_isolated_home; }
teardown() { teardown_isolated_home; }

@test "bash: my_function exists" {
    run_in_bash 'declare -f my_function >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: my_function exists" {
    run_in_zsh 'declare -f my_function >/dev/null && echo ok'
    assert_success
}
```

### 새 help 토픽 추가 시

`tests/integration/test_help_topics.py`의 `HELP_TOPICS` 리스트에 추가.

### 새 커스텀 툴 추가 시

`tests/bats/tools/custom_tools.bats`의 전체 검사(syntax, shebang)가 자동으로 커버합니다. 개별 dry-run 테스트가 필요하면 같은 파일에 추가하세요.

### cross-shell 패리티 테스트

`tests/integration/`에 pytest로 작성:

```python
@pytest.mark.parametrize("shell", ["bash", "zsh"])
def test_my_feature(self, shell_runner, shell):
    result = shell_runner(shell, "my_command")
    assert result.exit_code == 0
```

## tox 통합

```bash
tox -e bats        # bats 쉘 유닛 테스트만
tox -e py313       # pytest 통합 테스트만 (Python 3.13)
tox                # 전체 lint + 포매팅
```

## 골든 룰 (테스트 작성 시)

- **격리**: 사용자 dotfiles에 쓰기 금지. 임시 HOME 사용
- **네트워크 금지**: 외부 네트워크 접근 불가
- **설치 금지**: 패키지 설치 실행 불가
- **안정 출력**: 전체 배너가 아닌 안정적 부분 문자열로 assert
- **드라이런**: 커스텀 툴은 `bash -n` 또는 `help` 모드만 테스트

## 요구 사항

- bash, zsh
- Python 3.10+
- pytest, pytest-xdist (optional, 병렬 실행)
- bats-core (git submodule로 포함됨)

```bash
# Python 의존성 설치
pip install pytest pytest-xdist pexpect

# bats submodule 초기화 (최초 1회)
git submodule update --init --recursive
```

## 트러블슈팅

### bats-core not found

```bash
git submodule update --init --recursive
```

### pytest import error

`tests/integration/` 디렉토리명이 `pytest`와 충돌하지 않는지 확인. Python 패키지명과 같은 디렉토리명 사용 금지.

### 테스트 타임아웃

각 테스트의 기본 타임아웃은 30초. 느린 환경에서는:

```bash
pytest tests/integration/ --timeout=60
```

### shell not found

```bash
which bash zsh
```
