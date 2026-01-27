# Test Architecture Review

## 현재 프로젝트의 테스트 구조 분석

### 1. 디렉토리 구조

```
tests/
├── test                          # 메인 테스트 러너 (쉘 스크립트)
├── conftest.py                   # pytest 설정 & fixture
├── __init__.py
├── README.md                     # 테스트 문서
├── AGENTS.md                     # AI 에이전트 가이드
├── test_help_topics.py           # Help 시스템 테스트 (68 tests)
├── test_mytool_help.py           # Custom 도구 테스트 (76 tests)
└── test_compatibility.py         # Bash/Zsh 호환성 테스트 (32 tests)
                                  # ────────────────────────────
                                  # 총 275개 테스트
```

### 2. 파일별 역할

#### A. tests/test (메인 러너)

```bash
#!/bin/bash
# 역할: 테스트 실행 및 의존성 검증

주요 기능:
├─ 의존성 확인 (Python, pytest, pytest-xdist)
├─ 병렬/순차 모드 선택
├─ 환경 변수 설정 (DOTFILES_TEST_MODE)
└─ 결과 출력 (성공/실패 요약)

병렬 모드 (기본):
  python3 -m pytest tests/ --tb=short
  → pyproject.toml에서 "-n auto" 자동 적용

순차 모드 (디버깅):
  python3 -m pytest tests/ -p no:xdist
  → 느린 하지만 더 자세한 에러 정보
```

**특징:**
- 사용자 친화적 인터페이스
- 자동 의존성 검증
- 성능 정보 제공 (60-80초 vs 250초)

#### B. conftest.py (핵심 설정)

```python
역할: pytest fixture 제공 & 테스트 환경 구성

구성 요소:
├─ worker_id fixture
│  └─ pytest-xdist worker 감지 (master, gw0, gw1, ...)
│
├─ ShellRunnerResult 클래스
│  └─ 서브셸 명령 실행 결과 캡슐화
│
├─ run_command() 함수
│  └─ 격리된 환경에서 쉘 명령 실행
│     (HOME, ZDOTDIR, XDG_* 모두 임시 디렉토리)
│
├─ temp_home fixture
│  └─ xdist-aware 임시 홈 디렉토리
│     (각 Worker마다 고유한 디렉토리)
│
├─ shell_runner fixture
│  └─ 테스트에서 사용하는 메인 fixture
│     - bash/zsh 모두 지원
│     - 격리된 환경에서 명령 실행
│     - 결과 캡슐화
│
└─ dotfiles_state fixture
   └─ 초기화 상태 검증
      (SHELL_COMMON, SOURCED_FILES_COUNT 등)
```

**중요 특징:**
```python
# 병렬 모드 지원
@pytest.fixture
def worker_id(request):
    if hasattr(request.config, "workerinput"):
        return request.config.workerinput["workerid"]  # gw0, gw1, ...
    return "master"

# 각 Worker마다 격리된 환경
@pytest.fixture
def temp_home(worker_id):
    with tempfile.TemporaryDirectory(
        prefix=f"dotfiles_test_{worker_id}_"
    ) as tmpdir:
        yield tmpdir
```

#### C. test_help_topics.py (Help 시스템)

```python
목표: 34개 help 명령어의 정상 작동 검증

테스트:
├─ TestHelpTopicsBasic (5 tests)
│  ├─ my_help_impl 함수 존재 확인
│  ├─ my-help 알리아스 존재 확인
│  └─ HELP_DESCRIPTIONS 초기화
│
├─ TestHelpTopicsCallable (68 tests)
│  └─ 각 help 함수가 bash/zsh에서 실행 가능한지
│     (34 help topics × 2 shells)
│
├─ TestHelpTopicsWithDifferentFormats (5 tests)
│  ├─ 대시/언더스코어 형식 혼용
│  └─ 서브토픽 인자 처리
│
└─ TestHelpTopicsErrorHandling (5 tests)
   ├─ 유효하지 않은 토픽 처리
   └─ 에러 메시지 검증

매개변수화:
@pytest.mark.parametrize("shell", ["bash", "zsh"])
def test_something(shell_runner, shell):
    → 각 테스트가 bash와 zsh에서 실행
```

**격리 방식:**
```python
# 각 테스트가 독립적인 환경에서 실행
result = shell_runner(shell, "my_help_impl")
# shell_runner가 temp_home을 사용하여 격리
```

#### D. test_mytool_help.py (Custom 도구)

```python
목표: shell-common/tools/custom/ 내 39개 도구 검증

테스트:
├─ TestMytoolFilesExist (39 tests)
│  ├─ 파일 존재 확인
│  └─ +x 실행 권한 확인
│
├─ TestMytoolHelpFunction (4 tests)
│  └─ mytool_help 함수 호출 가능
│
├─ TestMytoolHelpLists (4 tests)
│  ├─ 도구 목록 출력
│  └─ 별칭 관리
│
├─ TestMytoolIntegration (4 tests)
│  └─ my_help_impl과 통합
│
└─ TestMytoolErrorHandling (4 tests)
   └─ 누락된 도구 대응

특징:
- 각 도구마다 존재 확인
- 실행 권한 검증
- Help 시스템과의 통합 확인
```

#### E. test_compatibility.py (호환성)

```python
목표: bash와 zsh 간 완전한 호환성 검증

테스트:
├─ TestDotfilesInitialization (4 tests)
│  └─ 두 셸 모두에서 초기화 성공
│
├─ TestFunctionAvailability (4 tests)
│  ├─ 함수/알리아스 가용성
│  └─ my_help_impl, mytool_help 확인
│
├─ TestShellFeatures (4 tests)
│  └─ 셸별 기능 지원 ([[ ]], [ ] 등)
│
├─ TestHelpSystemConsistency (4 tests)
│  └─ HELP_DESCRIPTIONS, help 함수 존재
│
└─ TestErrorHandling (2 tests)
   └─ 미정의 함수/문법 오류 처리
```

**중요:**
```python
# 각 테스트를 두 셸에서 실행
@pytest.mark.parametrize("shell", ["bash", "zsh"])
def test_feature(shell_runner, shell):
    result = shell_runner(shell, "command")
    # bash와 zsh에서 동일 결과 기대
```

## 테스트 격리 메커니즘

### 1. 프로세스 수준 격리

```
Master Process (main pytest process)
    │
    ├─► Worker 0 (독립 Python 프로세스)
    │   └─ subprocess (bash/zsh)
    │      └─ 격리된 HOME, ZDOTDIR
    │
    ├─► Worker 1 (독립 Python 프로세스)
    │   └─ subprocess (bash/zsh)
    │      └─ 격리된 HOME, ZDOTDIR
    │
    └─► Worker N (독립 Python 프로세스)
        └─ subprocess (bash/zsh)
           └─ 격리된 HOME, ZDOTDIR
```

### 2. 파일시스템 격리

```python
# 각 Worker마다 고유한 임시 디렉토리
Worker 0: HOME=/tmp/dotfiles_test_gw0_a7x9k/
Worker 1: HOME=/tmp/dotfiles_test_gw1_k3m2p/
Worker N: HOME=/tmp/dotfiles_test_gwN_x9q2l/

# 효과: 파일 충돌 완전 차단
```

### 3. 환경 변수 격리

```python
test_env = {
    "DOTFILES_FORCE_INIT": "1",    # 강제 초기화
    "DOTFILES_TEST_MODE": "1",     # 테스트 모드
    "DOTFILES_ROOT": str(REPO_ROOT),
    "SHELL_COMMON": str(SHELL_COMMON),
    "HOME": temp_home,              # 격리된 임시 홈
    "ZDOTDIR": temp_home,           # zsh 설정 경로
    "XDG_CONFIG_HOME": temp_home,   # XDG 설정
    "TERM": "dumb",                 # 비대화형
}
```

## 성능 특성

### 병렬화 효율성

```
테스트 수: 275
실행 시간: 8.45초

분석:
├─ Collection: 1.2초
│  └─ 소수 (1회 수행)
│
├─ 실행 (parallel):
│  Worker 0: 테스트 0-68    (Help Topics)
│  Worker 1: 테스트 69-144  (MyTool)
│  Worker 2: 테스트 145-210 (Compatibility)
│  Worker 3: 테스트 211-275 (기타)
│
│  최대 실행 시간: 7.8초 (가장 느린 Worker)
│
└─ 수렴: 0.05초

예상 순차 실행: 250초
실제 병렬 실행: 8.45초
속도 향상: 29배
```

### 로드 밸런싱

```
--dist load 옵션 분석:

// 테스트 실행 시간 가정
short test:   0.1초
medium test:  0.5초
long test:    2.0초

분배 전략 (--dist load):
├─ 총 테스트 시간 예상: 275 × avg_time
├─ 로드 밸런싱: 각 Worker에 균등 분배
└─ 결과: 최대 Worker 시간과 최소 시간 차이 최소화

예: 32초 작업을 4개 Worker로
  균등 분배: 32 / 4 = 8초/Worker
  로드 밸런싱: max - min = 0.5초
```

## 테스트 작성 가이드

### ✅ 권장 패턴

```python
# 1. Parametrization 사용 (cross-shell 테스트)
@pytest.mark.parametrize("shell", ["bash", "zsh"])
def test_cross_shell(shell_runner, shell):
    """Test가 bash와 zsh 모두에서 실행."""
    result = shell_runner(shell, "command")
    assert result.exit_code == 0

# 2. fixture 사용 (격리된 환경)
def test_file_operation(temp_home):
    """각 Worker가 독립적인 HOME 사용."""
    file_path = os.path.join(temp_home, "test.txt")
    with open(file_path, "w") as f:
        f.write("data")

# 3. worker_id 사용 (고유한 리소스)
def test_unique_resource(worker_id):
    """각 Worker마다 고유한 리소스 이름."""
    db_name = f"test_db_{worker_id}"
    # Worker 0: test_db_gw0
    # Worker 1: test_db_gw1
```

### ❌ 금지된 패턴

```python
# 1. 전역 상태 수정
GLOBAL_VAR = 0
def test_modify_global():
    global GLOBAL_VAR
    GLOBAL_VAR += 1  # ❌ Worker들이 충돌!

# 2. 고정 경로 사용
def test_with_fixed_path():
    path = "/tmp/test.txt"  # ❌ 모든 Worker가 같은 경로!

# 3. 환경 변수 직접 수정
def test_modify_env():
    os.environ["MY_VAR"] = "value"  # ❌ 다른 Worker에 영향!
```

## 확장 가능성

### 새로운 테스트 추가

```python
# tests/test_newfeature.py

import pytest

class TestNewFeature:
    @pytest.mark.parametrize("shell", ["bash", "zsh"])
    def test_something(self, shell_runner, shell):
        """자동으로 병렬 실행됨."""
        result = shell_runner(shell, "my_command")
        assert result.exit_code == 0
```

**장점:**
- 기존 fixture 재사용
- 자동으로 병렬 실행
- 격리된 환경 자동 제공

## 문제 해결

### 문제: Worker들이 파일을 놓고 경쟁

```python
# ❌ 문제 코드
def test_write_config():
    config_path = "/tmp/config.json"
    with open(config_path, "w") as f:
        json.dump({...}, f)
    with open(config_path, "r") as f:
        data = json.load(f)  # 다른 Worker가 덮어쓸 수 있음!

# ✅ 해결책
def test_write_config(worker_id):
    config_path = f"/tmp/config_{worker_id}.json"
    with open(config_path, "w") as f:
        json.dump({...}, f)
    with open(config_path, "r") as f:
        data = json.load(f)  # Worker마다 고유 파일
```

### 문제: 순차 모드에서만 작동

```python
# 원인: conftest fixture가 seq 모드를 가정
# 해결: worker_id 사용하여 격리

@pytest.fixture
def resource(worker_id):
    resource = allocate_resource(worker_id)
    yield resource
    cleanup_resource(resource)
```

## 요약

| 구성 요소 | 역할 | 특징 |
|----------|------|------|
| **tests/test** | 메인 러너 | 의존성 검증, 모드 선택 |
| **conftest.py** | 핵심 설정 | worker_id, fixture 제공 |
| **test_*.py** | 테스트 구현 | 매개변수화, 격리 |
| **pyproject.toml** | pytest 설정 | "-n auto --dist load" |

## 다른 프로젝트에서 적용

이 아키텍처를 다른 프로젝트에 적용하려면:

1. **pyproject.toml 설정**: `addopts = "-n auto --dist load"`
2. **conftest.py 추가**: worker_id, temp_dir fixture
3. **테스트 작성**: parametrize + fixture 사용
4. **격리 보장**: 절대 전역 상태 수정 금지

자세한 내용은 `docs/technic/parallel-testing-with-xdist.md` 참고.
