# Test Audit & Improvement Design

## Overview

dotfiles 프로젝트의 테스트 전수 검사, 의미 없는 테스트 삭제, 부족한 테스트 추가를 위한 설계 문서.

**목표**: 회귀 방지 + CI 게이트 + 살아있는 문서
**접근법**: 레이어별 점진적 확장 (아키텍처 레이어에 맞춰 단계적으로)

## 1. 테스트 구조 재편

현재 플랫 구조를 역할별로 분리한다.

```
tests/
├── AGENTS.md                    # 업데이트
├── test                         # 통합 러너 (pytest + bats)
├── pytest/                      # 기존 pytest 테스트 이동
│   ├── __init__.py
│   ├── conftest.py              # tests/conftest.py를 여기로 이동
│   ├── test_compatibility.py
│   ├── test_help_topics.py
│   ├── test_mytool_help.py      # 정리 후 축소
│   └── test_file_cleanup.py     # bats 이전 후 삭제 예정
├── bats/                        # 새로 추가
│   ├── test_helper.bash         # bats 공통 헬퍼
│   ├── init/                    # 초기화 & 로딩
│   │   ├── sourcing.bats
│   │   └── env_vars.bats
│   ├── functions/               # 핵심 유틸리티 함수
│   │   ├── git.bats
│   │   ├── file_cleanup.bats
│   │   ├── tmux_spawn.bats
│   │   └── devx.bats
│   └── tools/                   # 커스텀 툴 드라이런
│       ├── check_tools.bats
│       └── install_tools.bats
└── golden_rules/                # 기존 bash 테스트
    └── test_golden_rules.sh
```

**역할 분리:**
- **bats/** — 쉘 함수 단위 테스트 (빠르고, 쉘 네이티브)
- **pytest/** — 통합 테스트, cross-shell 패리티 검증
- **golden_rules/** — 정적 분석 규칙 검사

## 2. 의미 없는 테스트 삭제

### 삭제 대상

| 파일 | 대상 | 이유 |
|------|------|------|
| `test_mytool_help.py` | 커스텀 툴 존재/권한 38개 parametrize | bats 드라이런으로 대체, pre-commit hook과 중복 |
| `test_mytool_help.py` | mytool_help 함수/alias 존재 확인 | test_help_topics와 중복 |
| `test_compatibility.py` | help 시스템 관련 중복 테스트 | test_help_topics에 이미 있음 |

### 유지 대상

| 파일 | 이유 |
|------|------|
| `test_help_topics.py` | 34개 help 토픽 전체 검증, 핵심 |
| `test_compatibility.py` | cross-shell 초기화/환경변수 (중복 부분만 제거) |
| `test_golden_rules.sh` | 정적 분석, 대체 불가 |

### bats 이전 후 삭제

| 파일 | 이유 |
|------|------|
| `test_file_cleanup.py` | bats `functions/file_cleanup.bats`로 이전 |

## 3. 새로 추가할 테스트

### 3.1 초기화 & 로딩 (최우선)

#### `tests/bats/init/sourcing.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| main.bash가 shell-common을 소싱 | `source main.bash` 후 `SHELL_COMMON` 변수 존재 |
| main.zsh가 shell-common을 소싱 | `source main.zsh` 후 `SHELL_COMMON` 변수 존재 |
| SOURCED_FILES_COUNT > 0 | 소싱된 파일이 1개 이상 |
| env 파일들이 순서대로 로딩 | path.sh -> proxy.sh -> security.sh 순서 검증 |
| aliases 디렉토리 전체 로딩 | 대표 alias 3-4개 존재 확인 |
| functions 디렉토리 전체 로딩 | 대표 함수 3-4개 존재 확인 |
| 중복 소싱 방지 | 같은 파일 두 번 source해도 SOURCED_FILES_COUNT 불변 |

#### `tests/bats/init/env_vars.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| DOTFILES_ROOT 설정됨 | 올바른 경로 |
| SHELL_COMMON 설정됨 | `$DOTFILES_ROOT/shell-common` |
| PATH에 custom tools 포함 | `which repo_stats` 등 성공 |
| EDITOR 설정됨 | env/editor.sh에서 설정한 값 |
| 격리 환경에서 .local 파일 무시 | proxy.local 등이 없어도 에러 없이 초기화 |

### 3.2 핵심 유틸리티 함수

#### `tests/bats/functions/git.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| gitlog 함수 존재 | `declare -f gitlog` 성공 |
| gitlog 출력 포맷 | git repo 안에서 실행 시 커밋 로그 출력 |
| git_worktree 함수들 존재 | `gwt_create`, `gwt_list`, `gwt_remove` 등 |
| gwt_list 빈 결과 | worktree 없을 때 에러 없이 빈 출력 |
| git_ssh_check 함수 존재 | `declare -f git_ssh_check` 성공 |

#### `tests/bats/functions/file_cleanup.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| del_file 함수 존재 | `declare -f del_file` 성공 |
| 기본 패턴 목록 안정성 | `_cleanup_set_default_patterns` 출력에 `*.bak`, `*.backup`, `*.original` 포함 |
| 대상 파일 없을 때 | 에러 없이 종료 |

#### `tests/bats/functions/devx.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| devx 함수 존재 | `declare -f devx` 성공 |
| dev.sh 없는 디렉토리에서 실행 | 에러 메시지 출력, 비정상 종료 |

#### `tests/bats/functions/tmux_spawn.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| tmux_spawn 함수 존재 | `declare -f tmux_spawn` 성공 |
| tmux 미설치 시 에러 핸들링 | PATH에서 tmux 제거 후 적절한 에러 |

### 3.3 커스텀 툴 드라이런

#### `tests/bats/tools/check_tools.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| 모든 check_* 스크립트 | `--help` 플래그 시 usage 출력, exit 0 |
| check_network --help | 도움말 출력 |
| check_proxy --help | 도움말 출력 |

#### `tests/bats/tools/install_tools.bats`

| 테스트 | 검증 내용 |
|--------|-----------|
| 모든 install_* 스크립트 | `--help` 또는 인자 없이 실행 시 usage 출력 |
| DOTFILES_TEST_MODE=1 존중 | 테스트 모드에서 실제 설치 동작 스킵 |

## 4. bats-core 셋업

### 설치

`bats-core`, `bats-support`, `bats-assert`를 git submodule 또는 시스템 패키지로 설치.

### 공통 헬퍼 (`tests/bats/test_helper.bash`)

```bash
# bats 테스트 공통 헬퍼
# - DOTFILES_ROOT, SHELL_COMMON 설정
# - 임시 HOME 생성 (격리)
# - shell-common 로딩 함수 제공

setup() {
    export DOTFILES_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
    export SHELL_COMMON="$DOTFILES_ROOT/shell-common"
    export DOTFILES_TEST_MODE=1
    export DOTFILES_FORCE_INIT=1
    TEST_TEMP_HOME="$(mktemp -d)"
    export HOME="$TEST_TEMP_HOME"
    export ZDOTDIR="$TEST_TEMP_HOME"
}

teardown() {
    rm -rf "$TEST_TEMP_HOME"
}

load_dotfiles_bash() {
    source "$DOTFILES_ROOT/bash/main.bash"
}

load_dotfiles_zsh() {
    # zsh 테스트는 zsh 서브프로세스로 실행
    zsh -f -c "source $DOTFILES_ROOT/zsh/main.zsh; $1"
}
```

## 5. 테스트 러너 통합

`tests/test` 스크립트를 업데이트하여 pytest와 bats를 모두 실행:

```bash
#!/usr/bin/env bash
# 1. bats 테스트 실행
bats tests/bats/ --recursive

# 2. pytest 테스트 실행
pytest tests/pytest/ -v

# 3. golden rules 실행
bash tests/golden_rules/test_golden_rules.sh
```

## 6. tox.ini 업데이트

bats 테스트 환경을 tox에 추가:

```ini
[testenv:bats]
description = Run bats shell unit tests
skip_install = true
allowlist_externals = bats
commands = bats tests/bats/ --recursive
```

## 7. 테스트 골든 룰 (AGENTS.md 업데이트)

기존 골든 룰에 추가:

- **bats 테스트 격리**: 모든 bats 테스트는 임시 HOME을 사용, 사용자 dotfiles에 쓰기 금지
- **드라이런 원칙**: 커스텀 툴 테스트는 `--help` 또는 `DOTFILES_TEST_MODE=1`로만 실행
- **네트워크 금지**: 테스트에서 네트워크 접근 불가
- **쉘 함수 단위 테스트는 bats**: 새 함수 추가 시 `tests/bats/functions/`에 테스트 작성
- **통합/패리티 테스트는 pytest**: cross-shell 동작 검증은 pytest에 유지
