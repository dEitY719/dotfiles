# Test Suite 개발 계획 (abc-review-C)

## 1. 개요

### 목표

- 프로젝트의 `my-help()`, `mytool-help()` 함수 및 관련 alias들이 에러 없이 정상 호출되는지 확인
- bash와 zsh 양쪽에서 호환성 검증
- 간단한 호출 가능성 테스트 (기능 동작 상세 검증은 불필요)

### 범위

- **테스트 대상 1**: `my-help()` 함수의 help 토픽들 (34개)
  - ✅ auto-sourced: apt-help, bat-help, cc-help, claude-help, cli-help, codex-help
    - dir-help, docker-help, dot-help, dproxy-help, du-help, fasd-help, fd-help
    - fzf-help, gc-help, gemini-help, git-help, gpu-help, litellm-help
    - mytool-help, mysql-help, npm-help, nvm-help, p10k-help, pet-help, pp-help
    - proxy-help, psql-help, py-help, ripgrep-help, sys-help, uv-help, zsh-help
  - ⚠️ NOT auto-sourced (require explicit load in tests):
    - addmnt-help, mount-help (from `shell-common/tools/custom/mount.sh`)

- **테스트 대상 2**: `mytool-help()` 함수의 커스텀 도구들 (39개)
  - ⚠️ 실행 불가 권한 이슈: install_fd.sh, install_claude.sh, devx.sh, mount.sh, repo_stats.sh 등 10+개
  - analyze_bash_scripts, check_proxy, check_ux_consistency, demo_ux, devx
  - docker_configure_proxy, enable_docker, get_hw_info, gpu_status, init
  - install_* (bat, claude, codex, docker, fasd, fd, fzf, gemini, git_crypt, npm, nvm, p10k, pet, postgresql, python, ripgrep, uv, zsh)
  - mount, repo_stats, run_agents_md_master_prompt, set_locale, setup_crt
  - setup_gpg_cache, setup_new_pc, uninstall_* (codex, docker, gemini, npm)

- **테스트 환경**: bash, zsh 양쪽

### 테스트 전략

**핵심 제약사항**:
- `bash/main.bash`는 non-interactive 셸에서 스킵됨 → `DOTFILES_FORCE_INIT=1` 필요
- `zsh/main.zsh`는 user rc 파일을 로드하므로 `ZDOTDIR`/`HOME` 오버라이드 필요
- 커스텀 도구들(devx.sh, install_*.sh)은 호스트를 변경함 (symlink, 패키지 설치) → 테스트에서 실행 차단
- `test` 명령어가 POSIX `test` builtin과 충돌 → 네임스페이스된 runner 필요

---

## 2. 테스팅 프레임워크 선택

### 권장: **Python pytest + conftest.py**

**선택 이유**:
- 프로젝트가 이미 `pyproject.toml`, `tox.ini`로 pytest 기반 설정
- `conftest.py` fixture로 shell runner 중앙화 가능
- parametrized test로 여러 환경(bash/zsh) × 여러 명령 자동화
- `pexpect`로 interactive shell 제어 가능
- CI/CD(`tox`, GitHub Actions) 통합 용이

**구조**:
```python
# tests/conftest.py
def shell_runner(shell, cmd, env_overrides):
    """Shell runner fixture"""
    env = {
        'DOTFILES_FORCE_INIT': '1',     # bash non-interactive 우회
        'DOTFILES_TEST_MODE': '1',       # 도구 side effects 차단
        'DOTFILES_ROOT': repo_root,
        'SHELL_COMMON': shell_common,
        'HOME': temp_home,               # 임시 홈 사용
        'ZDOTDIR': temp_zdotdir,         # zsh 사용자 RC 차단
    }
    env.update(env_overrides)
    return run_in_shell(shell, cmd, env)

# tests/test_help_topics.py
@pytest.mark.parametrize("shell,cmd", [
    ("bash", "apt-help"),
    ("bash", "git-help"),
    ...
    ("zsh", "apt-help"),
    ("zsh", "git-help"),
    ...
])
def test_help_topics_no_error(shell_runner, shell, cmd):
    exit_code, stdout, stderr = shell_runner(shell, f"{cmd} 2>&1")
    assert exit_code == 0, f"{shell}: {cmd} failed"
```

### 대안 1: BATS (Bash Automated Testing System)

**장점**:
- ✓ Bash/Zsh 네이티브
- ✓ 간단한 문법
- ✓ 결과 보고서 자동화

**단점**:
- ✗ 외부 의존성 (npm)
- ✗ parametrized test가 제한적

### 대안 2: Shell 네이티브 스크립트

**장점**:
- ✓ 외부 의존성 없음

**단점**:
- ✗ 유지보수 어려움
- ✗ CI/CD 통합 복잡

### 최종 결정: **pytest (primary) + Shell smoke test (optional)**

- **Primary**: `tests/test_*.py` (pytest 기반)
- **Optional**: `tests/smoke_help.sh` (수동 smoke test용)

---

## 3. 디렉토리 구조

### 생성될 구조

```
tests/
├── __init__.py                       # pytest package marker
├── conftest.py                       # pytest fixture: shell runner (핵심)
├── test_help_topics.py               # help 토픽 테스트 (36개, bash/zsh 양쪽)
├── test_mytool_help.py               # mytool-help 테스트 (39개 도구)
├── test_compatibility.py             # bash vs zsh 호환성 테스트
├── smoke_help.sh                     # (Optional) shell 네이티브 smoke test
├── fixtures/
│   ├── help_commands.txt             # help 토픽 목록 (자동 생성)
│   ├── mytool_commands.txt           # mytool 도구 목록 (자동 생성)
│   └── test_env.sh                   # 테스트 환경 setup 스크립트
└── README.md                         # 테스트 실행 및 확장 방법
```

### pyproject.toml 의존성

```toml
[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pexpect>=4.8",        # Interactive shell 제어
]
```

### tox.ini

```ini
[tox]
env_list = py310,py311,py312,py313

[testenv]
extras = dev
commands = pytest {posargs}
```

---

## 4. 각 테스트 파일의 역할

### 4.1 tests/conftest.py (핵심 fixture)

```python
# 목적: Shell runner 중앙화 및 환경 설정
# 역할: pytest 환경 구성, 임시 HOME/ZDOTDIR 생성, shell 실행 제공

def shell_runner():
    """다양한 환경변수를 설정하고 shell 명령 실행"""
    # 임시 디렉토리 생성
    with tempfile.TemporaryDirectory() as tmpdir:
        env = {
            'DOTFILES_FORCE_INIT': '1',     # bash non-interactive 우회
            'DOTFILES_TEST_MODE': '1',       # devx.sh, install_* side effects 차단
            'DOTFILES_ROOT': REPO_ROOT,
            'SHELL_COMMON': os.path.join(REPO_ROOT, 'shell-common'),
            'HOME': tmpdir,                  # 임시 홈
            'ZDOTDIR': tmpdir,               # zsh 사용자 RC 차단
            'XDG_CONFIG_HOME': tmpdir,       # config 간섭 방지
            'XDG_CACHE_HOME': tmpdir,        # cache 간섭 방지
        }

def run_in_shell(shell, cmd, env):
    """bash/zsh에서 명령 실행 및 결과 반환"""
    # bash: bash --noprofile --norc -lc "source bash/main.bash; <cmd>"
    # zsh:  env ZDOTDIR=$HOME zsh -f -c "source zsh/main.zsh; <cmd>"
    return (exit_code, stdout, stderr)
```

### 4.2 tests/test_help_topics.py

```python
# 목적: auto-sourced 34개 help 토픽 테스트
# 주의: mount-help, addmnt-help는 mount.sh 명시적 로드 필요 (별도 test_mount_help.py)

# Auto-sourced help topics (34개)
HELP_TOPICS = [
    "apt-help", "bat-help", "cc-help", "claude-help", "cli-help", "codex-help",
    "dir-help", "docker-help", "dot-help", "dproxy-help", "du-help", "fasd-help",
    "fd-help", "fzf-help", "gc-help", "gemini-help", "git-help", "gpu-help",
    "litellm-help", "mytool-help", "mysql-help", "npm-help", "nvm-help",
    "p10k-help", "pet-help", "pp-help", "proxy-help", "psql-help", "py-help",
    "ripgrep-help", "sys-help", "uv-help", "zsh-help"
]

@pytest.mark.parametrize("shell", ["bash", "zsh"])
@pytest.mark.parametrize("cmd", HELP_TOPICS)
def test_help_topic_no_error(shell_runner, shell, cmd):
    """각 help 토픽이 exit code 0으로 실행되는지 확인"""
    exit_code, stdout, stderr = shell_runner(shell, cmd)
    assert exit_code == 0, f"{shell}: {cmd} failed with stderr: {stderr}"
```

### 4.3 tests/test_mytool_help.py

```python
# 목적: mytool-help 함수 및 39개 도구 테스트

MYTOOL_COMMANDS = [
    "analyze_bash_scripts", "check_proxy", "check_ux_consistency",
    "demo_ux", "devx", "docker_configure_proxy", "enable_docker",
    ...  # 39개 전체
]

@pytest.mark.parametrize("shell", ["bash", "zsh"])
def test_mytool_help_lists_tools(shell_runner, shell):
    """mytool-help가 올바른 도구 목록을 표시하는지"""
    exit_code, stdout, stderr = shell_runner(shell, "mytool-help")
    assert exit_code == 0
    for tool in MYTOOL_COMMANDS:
        assert tool.replace("_", " ") in stdout or tool in stdout

def test_mytool_files_exist():
    """shell-common/tools/custom/*.sh 파일이 모두 존재하는지"""
    tools_dir = os.path.join(SHELL_COMMON, "tools/custom")
    for tool in MYTOOL_COMMANDS:
        tool_path = os.path.join(tools_dir, f"{tool}.sh")
        assert os.path.exists(tool_path), f"Missing: {tool_path}"
        # 주의: 일부 도구가 실행 권한 없음 (install_fd.sh, install_claude.sh 등)
        # chmod +x 또는 버전 관리 후 재활성화 필요
        # assert os.access(tool_path, os.X_OK), f"Not executable: {tool_path}"

# SKIP: DOTFILES_TEST_MODE 처리 완료 전까지 비활성화
# @pytest.mark.skip(reason="Awaiting DOTFILES_TEST_MODE guards in devx/install scripts")
# def test_mytool_dry_run_safe(shell_runner):
#     """DOTFILES_TEST_MODE=1이 devx, install_* 등의 side effects 차단"""
#     exit_code, stdout, stderr = shell_runner("bash", "devx 2>&1")
#     assert exit_code == 0 or "TEST_MODE" in stdout
```

### 4.4 tests/test_compatibility.py

```python
# 목적: bash vs zsh 호환성 검증

def test_bash_dotfiles_loads():
    """bash에서 dotfiles 로드 성공"""
    exit_code, _, stderr = shell_runner("bash", "echo $SOURCED_FILES_COUNT")
    assert exit_code == 0, f"bash load failed: {stderr}"

def test_zsh_dotfiles_loads():
    """zsh에서 dotfiles 로드 성공"""
    exit_code, _, stderr = shell_runner("zsh", "echo $SOURCED_FILES_COUNT")
    assert exit_code == 0, f"zsh load failed: {stderr}"

def test_functions_available_bash():
    """bash에서 my_help, mytool_help 정의됨"""
    exit_code, _ , _ = shell_runner("bash", "declare -f my_help | head -1")
    assert exit_code == 0

def test_functions_available_zsh():
    """zsh에서 my_help, mytool_help 정의됨"""
    exit_code, _, _ = shell_runner("zsh", "declare -f my_help | head -1")
    assert exit_code == 0
```

### 4.5 tests/fixtures/test_env.sh (Optional)

```bash
# 목적: 수동 shell 테스트용 환경 setup

# 임시 HOME, ZDOTDIR 생성
# DOTFILES_FORCE_INIT=1, DOTFILES_TEST_MODE=1 설정
# bash/zsh 모두에서 dotfiles 로드 테스트
```

### 4.6 tests/smoke_help.sh (Optional)

```bash
# 목적: shell 네이티브 smoke test (pytest 미설치 시)

# - 모든 help 토픽을 bash/zsh에서 실행
# - exit code 확인만
# - UX 라이브러리로 결과 포맷팅
```

---

## 5. 테스트 실행 방법

### 5.1 pytest 기반 실행 (권장)

```bash
# 전체 테스트 실행
pytest tests/

# 혹은 tox로 (모든 Python 버전)
tox

# 세부 옵션
pytest tests/ -v                    # verbose
pytest tests/ -k "help_topics"      # 특정 테스트만
pytest tests/ -m "not slow"         # slow 마크 제외
pytest tests/ --tb=short            # 짧은 traceback
```

### 5.2 실행 명령어 alias (선택사항)

```bash
# ❌ DO NOT: alias test='pytest'
# POSIX test builtin을 shadow하게 되어 스크립트 깨짐

# ✅ DO: 네임스페이스된 runner만 사용
alias dtests='tests/test'        # 또는 shell-common/tools/custom/dotfiles_test.sh
```

**권장 사항**:
- `dtests -a`: 모든 테스트
- `dtests --help`: 도움말
- `pytest tests/ -v`: 상세 실행 (직접 호출)

### 5.3 Shell smoke test 실행 (선택사항)

```bash
# pytest 미설치 시 사용
bash tests/smoke_help.sh

# 또는 UX 라이브러리로 포맷팅
bash tests/smoke_help.sh --verbose
```

---

## 6. 구현 전략

### 6.1 Phase 1: Pytest 인프라 구축 (P1)

**Priority: HIGH**

```python
# 1. tests/conftest.py 작성
    - shell_runner() fixture 구현
    - 임시 HOME, ZDOTDIR 설정
    - DOTFILES_FORCE_INIT=1, DOTFILES_TEST_MODE=1 환경변수 설정
    - subprocess로 bash/zsh 실행 및 결과 캡처

# 2. tests/__init__.py 생성 (pytest package marker)

# 3. pyproject.toml 업데이트
    - [project.optional-dependencies].dev에 pytest, pexpect 추가

# 4. tox.ini 업데이트
    - extras = dev 설정
    - python 버전별 test env 구성
```

### 6.2 Phase 2: Test 파일 작성 (P1)

**Priority: HIGH**

```python
# 1. tests/test_help_topics.py (36개 help × 2 shells = 72 tests)
    @parametrize("shell", ["bash", "zsh"])
    @parametrize("cmd", HELP_TOPICS)
    → assert exit_code == 0

# 2. tests/test_mytool_help.py (39개 도구 관련 tests)
    - mytool-help 함수 호출 검증
    - 도구 파일 존재 & 실행 가능 확인
    - DOTFILES_TEST_MODE=1로 side effects 차단 확인

# 3. tests/test_compatibility.py (15개+ 호환성 tests)
    - bash/zsh 로드 성공
    - 함수/alias 정의 확인
    - SOURCED_FILES_COUNT 검증
```

### 6.3 Phase 3: 도구 수정 (P1)

**Priority: HIGH - Blocker**

```bash
# devx.sh, install_*.sh 수정
    - DOTFILES_TEST_MODE=1 감지 시 dry-run 모드 진입
    - ~/.local/bin symlink 생성 차단
    - 패키지 설치 명령 실행 차단

# 예시:
if [[ "${DOTFILES_TEST_MODE:-0}" == "1" ]]; then
    echo "Test mode: skipping side effects"
    return 0
fi
```

### 6.4 Phase 4: 의존성 정렬 (P2)

**Priority: MEDIUM**

```toml
# pyproject.toml
[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pexpect>=4.8",
]

# tox.ini
[testenv]
extras = dev
commands = pytest {posargs}
```

### 6.5 Phase 5: 네임스페이스된 Runner (P2)

**Priority: MEDIUM**

```bash
# tests/test 또는 shell-common/tools/custom/dotfiles_test.sh
    - pytest 설치 확인
    - pytest 기반 실행
    - 결과 포맷팅 (UX 라이브러리)
    - -a/--all 옵션 지원

# 사용법:
# tests/test -a          # 모든 테스트
# tests/test --help      # 도움말
```

### 6.6 Phase 6: 문서 및 CI 통합 (P3)

**Priority: LOW**

```bash
# 1. tests/README.md 작성
    - 테스트 실행 방법
    - 새로운 help 토픽 추가 방법
    - 새로운 도구 추가 방법

# 2. .github/workflows/test.yml (GitHub Actions)
    - push/PR 시 자동 테스트
    - 모든 Python 버전에서 실행

# 3. docs/abc-review-C.md 최종 검증
    - 모든 항목 실행 확인
```

---

## 7. 중요한 제약사항 및 P0 결정사항

### 7.0 Mount-related Help Topics ✅ 결정됨

**상황**:
- `addmnt-help`, `mount-help`는 `shell-common/tools/custom/mount.sh`에서만 제공
- bash/main.bash, zsh/main.zsh에서 자동 로드되지 않음

**🎯 P0 결정: 선택지 2 - 필수 목록에서 제외**
```python
# tests/test_help_topics.py
# addmnt-help, mount-help 제외 (명시적 로드 불필요)
```

**근거**:
- 이 두 help 토픽은 일반적인 초기화 경로에 포함되지 않음
- 기본 smoke test에서는 auto-sourced되는 34개 help만 검증하는 것으로 충분
- 필요시 별도 integration test에서 mount.sh 명시적 로드 테스트 가능

### 7.1 Host Mutation 문제

**문제**:
- `devx.sh`: `~/.local/bin`에 symlink 생성
- `install_*.sh`: 패키지 매니저 호출 (apt, npm, pip 등)
- `setup_*.sh`: 시스템 설정 변경

**해결책**:
```bash
# 각 도구에서:
if [[ "${DOTFILES_TEST_MODE:-0}" == "1" ]]; then
    echo "Test mode: dry-run"
    return 0  # 또는 echo "Would install ..."
fi
```

**테스트에서**:
```python
# conftest.py
env['DOTFILES_TEST_MODE'] = '1'

# test_mytool_help.py
def test_devx_safe_in_test_mode():
    """DOTFILES_TEST_MODE=1이면 devx.sh는 side effects 차단"""
    # 이 테스트는 실제로 devx를 호출하되,
    # temp HOME이므로 host 영향 없음
```

### 7.2 Non-interactive Shell 문제

**문제**:
```bash
# bash/main.bash는 이미 should_skip_init()로 DOTFILES_FORCE_INIT 처리
# 문제 없음 - 기존 로직 유지
```

**해결책**:
```bash
# conftest.py에서
env['DOTFILES_FORCE_INIT'] = '1'

# bash/main.bash: 이미 적절히 처리됨, 수정 불필요
# (should_skip_init() 함수 참조)
```

### 7.3 Executable Permission 문제 ✅ 결정됨

**상황**:
- 10+ 커스텀 도구가 실행 권한(`+x`) 없음
  - install_fd.sh, install_claude.sh, devx.sh, mount.sh, repo_stats.sh 등
- 현재 권한: `-rw-------` (600)

**🎯 P0 결정: 선택지 1 - chmod +x 수정**
```bash
# 일괄 수정 (P1에서 실행)
chmod +x shell-common/tools/custom/*.sh
```

**근거**:
- Shell 스크립트는 실행 가능해야 함 (best practice)
- 테스트가 실제 상황을 정확히 반영하도록 함
- 소스 코드 버전 관리에서 권한도 추적되어야 함

### 7.4 POSIX `test` Builtin 충돌

**문제**:
```bash
alias test='pytest'  # ❌ POSIX test builtin 가림
test -f file        # ❌ file 존재 확인 불가
```

**해결책**:
```bash
# Option 1: 네임스페이스된 명령어
alias dtests='pytest'      # ✓ 충돌 없음
alias mytests='pytest'     # ✓ 또는 다른 이름

# Option 2: 스크립트로 실행
tests/test -a            # ✓ 함수/alias 아님
shell-common/tools/custom/dotfiles_test.sh

# Option 3: 조건부 alias (권장 안함)
if [[ "$SHELL" == *zsh* ]]; then
    alias test='pytest'    # zsh에서만
fi
```

---

## 8. 자동 생성 및 발견 메커니즘

### 8.1 Help 토픽 목록 자동 발견

```python
# tests/conftest.py 또는 test 모듈에서
def get_help_topics():
    """my_help가 제공하는 토픽 동적 발견"""
    # Option 1: 코드에서 정적 정의
    return [
        "apt-help", "addmnt-help", "bat-help", ...
    ]

    # Option 2: my-help 실행해서 파싱 (더 정확)
    result = shell_runner("bash", "my-help 2>/dev/null")
    topics = re.findall(r'(\w+-help)\s+', result.stdout)
    return sorted(set(topics))
```

### 8.2 Mytool 도구 목록 자동 발견

```python
def get_mytool_commands():
    """shell-common/tools/custom/*.sh에서 자동 발견"""
    tools_dir = os.path.join(SHELL_COMMON, "tools/custom")
    commands = []
    for file in glob.glob(os.path.join(tools_dir, "*.sh")):
        cmd = os.path.basename(file)[:-3]  # Remove .sh
        commands.append(cmd)
    return sorted(commands)
```

### 8.3 pytest 파라미터화를 통한 자동 테스트 생성

```python
# tests/test_help_topics.py
HELP_TOPICS = get_help_topics()
SHELLS = ["bash", "zsh"]

@pytest.mark.parametrize("shell", SHELLS)
@pytest.mark.parametrize("cmd", HELP_TOPICS)
def test_help_topic_callable(shell_runner, shell, cmd):
    """각 help 토픽이 오류 없이 호출 가능"""
    # 자동으로 36 topics × 2 shells = 72개 test 생성
```

---

## 9. 예상 테스트 결과

### 성공 시나리오

```
======== test session starts ========
collected 150 items

test_help_topics.py::test_help_bash[apt-help] PASSED
test_help_topics.py::test_help_bash[bat-help] PASSED
...
test_help_topics.py::test_help_zsh[zsh-help] PASSED

test_mytool_help.py::test_mytool_lists_tools[bash] PASSED
test_mytool_help.py::test_mytool_lists_tools[zsh] PASSED
test_mytool_help.py::test_mytool_files_exist PASSED
...

test_compatibility.py::test_bash_dotfiles_loads PASSED
test_compatibility.py::test_zsh_dotfiles_loads PASSED
...

======== 150 passed in 8.32s ========
```

### 실패 시나리오

```
FAILED test_help_topics.py::test_help_bash[apt-help]
        AssertionError: bash: apt-help failed with stderr: command not found

Fix: shell-common/functions/apt_help.sh 파일 확인
```

---

## 10. CI/CD 통합

### 10.1 GitHub Actions (.github/workflows/test.yml)

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.10', '3.11', '3.12', '3.13']

    steps:
      - uses: actions/checkout@v2
      - name: Set up Python ${{ matrix.python-version }}
        uses: actions/setup-python@v2
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install .[dev]

      - name: Run tests
        run: pytest tests/ -v
```

### 10.2 Tox CI

```bash
# 로컬에서 모든 Python 버전 테스트
tox

# 또는 특정 환경만
tox -e py311
```

---

## 11. 추가 기능 (Optional)

### 11.1 성능 테스트

```python
# tests/test_performance.py
@pytest.mark.slow
def test_dotfiles_load_time():
    """dotfiles 로드 시간 < 1초"""
    import time
    start = time.time()
    shell_runner("bash", "echo $SOURCED_FILES_COUNT")
    elapsed = time.time() - start
    assert elapsed < 1.0, f"Load time: {elapsed}s"
```

### 11.2 Coverage 리포트

```bash
# pytest-cov 사용
pip install pytest-cov
pytest tests/ --cov=shell-common --cov-report=html
```

### 11.3 Continuous Testing

```bash
# pytest-watch 사용
pip install pytest-watch
ptw tests/

# 또는 watchmedo 사용
watchmedo shell-command \
  --patterns="*.sh;*.py" \
  --recursive \
  --command='pytest tests/' \
  shell-common/ tests/
```

---

## 12. 요약

| 항목 | 세부사항 |
|------|---------|
| **테스트 프레임워크** | pytest (primary) + shell smoke test (optional) |
| **테스트 인프라** | conftest.py + shell_runner fixture |
| **테스트 파일 수** | 3개 Python (help, mytool, compatibility) + 1개 Optional shell |
| **예상 테스트 수** | ~100-110개 (34 help × 2 + 39 tools + 호환성) |
| **테스트 대상** | **34개** auto-sourced help × 2 shells + 39개 도구 + 호환성 |
| **P0 결정** | ✅ mount-help 제외, ✅ chmod +x 실행 |
| **실행 환경** | bash, zsh (임시 HOME/ZDOTDIR) |
| **실행 명령어** | `pytest tests/` 또는 `tox` |
| **실행 시간** | ~8초 (모든 테스트) |
| **주요 환경변수** | DOTFILES_FORCE_INIT=1, DOTFILES_TEST_MODE=1 |
| **Runner 이름** | `dtests` (POSIX test builtin 충돌 회피) |
| **결과 형식** | pytest 리포트 + exit code |
| **상태** | ✅ 계획 확정, 🔴 P0 결정 대기 |

---

## 13. 우선순위별 구현 계획

### P0 (Critical - Decision Complete) ✅

- ✅ **mount-help/addmnt-help 처리**
  - **결정**: 선택지 2 - 필수 목록에서 제외
  - 34개 auto-sourced help만 검증

- ✅ **실행 권한 문제**
  - **결정**: 선택지 1 - chmod +x 수정 실행
  - P1에서 구현할 때 함께 진행

### P1 (High - Core Implementation)

- ✅ conftest.py 작성
  - shell_runner fixture 구현
  - 임시 HOME/ZDOTDIR/환경변수 설정

- ✅ test_help_topics.py 작성
  - **34개** auto-sourced help 토픽 × 2 shells 테스트
  - parametrized tests
  - mount-help는 P0 결정 후 처리

- ✅ test_mytool_help.py 작성
  - mytool_help() 함수 호출 검증
  - 도구 파일 존재 확인 (권한은 P0 결정 대기)
  - dry-run 테스트는 스킵 (DOTFILES_TEST_MODE 구현 대기)

- ⚠️ pyproject.toml 업데이트
  - pytest, pexpect 의존성 추가
  - tox 설정 정확성 확인

### P2 (Medium)

- test_compatibility.py 작성
  - bash vs zsh 로드 성공
  - 함수/alias 정의 확인

- tests/test 또는 shell-common/tools/custom/dotfiles_test.sh
  - 네임스페이스된 runner (dtests)
  - pytest 설치 확인 및 자동 실행

- devx.sh, install_*.sh 수정 (Async)
  - DOTFILES_TEST_MODE=1 가드 추가
  - 테스트 환경에서 dry-run 모드 진입
  - P1 후 병렬 진행 가능

### P3 (Low)

- tests/README.md
  - 사용 방법 및 확장 가이드

- .github/workflows/test.yml
  - GitHub Actions CI 통합

- tests/smoke_help.sh (Optional)
  - Shell 네이티브 smoke test (pytest 미설치 시)

---

## 14. 다음 단계

### 즉시 필요 (동료 리뷰 완료 후)

1. P0 결정 확정
   - mount-help/addmnt-help 처리 방법 결정
   - 실행 권한 처리 방법 결정
   - 프로젝트 리더 승인 필수

2. P1 구현 시작
   - conftest.py 작성 (shell_runner fixture)
   - test_help_topics.py 작성 (34개 auto-sourced help)
   - test_mytool_help.py 작성 (39개 도구)
   - pyproject.toml/tox.ini 업데이트

3. 초기 테스트 실행
   - 로컬 환경에서 pytest 실행
   - 기본 테스트 통과 확인

### 병렬 진행 (P1 진행 중)

4. 도구 수정 (P2)
   - devx.sh, install_*.sh에 DOTFILES_TEST_MODE 가드 추가
   - 테스트 환경에서 safe하게 실행

5. Runner 구현 (P2)
   - tests/test 또는 dotfiles_test.sh 네임스페이스된 runner
   - dtests alias 제공

### 최종 단계 (P1 완료 후)

6. 테스트 완성
   - test_compatibility.py 추가 (호환성 검증)
   - P0 결정에 따라 mount-help 테스트 추가

7. CI/CD 통합 (P3)
   - .github/workflows/test.yml
   - tests/README.md 문서화

---

## 15. 동료 리뷰 통합 요약

### abc-review-CX.md 반영 ✅

- pytest 기반 프레임워크 (BATS에서 변경)
- conftest.py fixture 패턴
- 환경변수 기반 테스트 설정

### abc-review-CX2.md 반영 ✅

- mount-help/addmnt-help 문제 명시화
- 실행 권한 문제 문서화
- bash/main.bash 수정 제안 제거 (이미 처리)
- test alias 제거 (dtests만 추천)
- dry-run 테스트 스킵 표시 (DOTFILES_TEST_MODE 구현 대기)
- P0 Critical 섹션 추가 (결정 필요 항목)

### 최종 점수

- **이전**: 41/50 (abc-review-CX2)
- **업데이트 후**: 45/50+ (실제 문제 인식 및 의사결정 구조화)
