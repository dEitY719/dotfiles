# Parallel Test Execution with pytest-xdist

## 개요 (Overview)

이 문서는 `pytest-xdist`를 사용한 병렬 테스트 실행 기술을 설명합니다. 이 기술을 통해 테스트 실행 시간을 **3~4배 단축**할 수 있습니다.

- **순차 실행**: ~250초 (275개 테스트)
- **병렬 실행**: ~60-80초 (모든 CPU 코어 활용)

## 핵심 개념

### 1. pytest-xdist란?

`pytest-xdist`는 pytest 플러그인으로, 여러 CPU 코어를 활용하여 테스트를 **병렬**로 실행합니다.

```bash
# 설치
pip install pytest-xdist

# 또는
uv pip install pytest-xdist
```

### 2. 병렬화 작동 원리

```
┌─────────────────────────────────────────────────────────┐
│  Main Process (Master)                                  │
│  - Tests 수집 (Collection)                              │
│  - Worker 프로세스 생성                                 │
│  - 결과 수집                                            │
└──────────────┬──────────────────────────────────────────┘
               │
               ├─► Worker 0 (CPU Core 0) ─► test1, test2, test3
               ├─► Worker 1 (CPU Core 1) ─► test4, test5, test6
               ├─► Worker 2 (CPU Core 2) ─► test7, test8, test9
               └─► Worker N (CPU Core N) ─► testN-2, testN-1, testN
```

**각 Worker:**
- 독립적인 Python 프로세스
- 격리된 실행 환경
- 동시에 다른 테스트 실행

## 구현 방식

### 1. pyproject.toml 설정

```toml
[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]
addopts = "-v --strict-markers -n auto --dist load"
# ↑ 병렬 실행 설정
```

**각 옵션 설명:**

| 옵션 | 의미 | 비고 |
|------|------|------|
| `-n auto` | 시스템의 모든 CPU 코어 사용 | 자동 감지 |
| `--dist load` | 테스트를 **로드 균형** 방식으로 분배 | 이질적인 테스트에 최적 |
| `-v` | Verbose 출력 | 상세 정보 표시 |
| `--strict-markers` | 등록되지 않은 마커 거부 | 오류 방지 |

### 2. 테스트 러너 스크립트 (tests/test)

```bash
# 병렬 실행 (기본)
python3 -m pytest tests/ --tb=short
# 설정에서 "-n auto --dist load" 자동 적용

# 순차 실행 (디버깅용)
python3 -m pytest tests/ \
    --tb=short \
    -o addopts="-v --strict-markers" \
    -p no:xdist
```

### 3. pytest-xdist 지원 코드 (conftest.py)

```python
@pytest.fixture
def worker_id(request):
    """Get pytest-xdist worker ID for test isolation."""
    if hasattr(request.config, "workerinput"):
        # Worker 모드: gw0, gw1, gw2, ...
        return request.config.workerinput["workerid"]
    else:
        # Sequential 모드: master
        return "master"

@pytest.fixture
def temp_home(worker_id):
    """Create isolated temporary HOME (xdist-aware).

    각 Worker마다 고유한 임시 디렉토리 생성:
    - Master: /tmp/dotfiles_test_master_xxxxx
    - Worker 0: /tmp/dotfiles_test_gw0_xxxxx
    - Worker 1: /tmp/dotfiles_test_gw1_xxxxx
    """
    with tempfile.TemporaryDirectory(
        prefix=f"dotfiles_test_{worker_id}_"
    ) as tmpdir:
        yield tmpdir
```

**중요:** Worker마다 고유한 임시 디렉토리를 사용하여 **파일 시스템 충돌** 방지!

## 실행 방식

### 1. 병렬 실행 (권장)

```bash
# 기본: 모든 코어 사용
./tests/test

# Verbose 출력
./tests/test -v

# 결과: 60-80초
# [gw0] PASSED test_1
# [gw1] PASSED test_2
# [gw2] PASSED test_3
# ...
```

**Output 예시:**
```
[gw0] 25% PASSED tests/test_help_topics.py::...
[gw1] 28% PASSED tests/test_compatibility.py::...
[gw2] 35% PASSED tests/test_mytool_help.py::...
...
============================= 275 passed in 8.45s ==============================
```

각 테스트 앞의 `[gw0]`, `[gw1]` 등은 실행 중인 Worker ID입니다.

### 2. 순차 실행 (디버깅)

```bash
# 순차 실행 (문제 해결용)
./tests/test -s

# 결과: 250초
# PASSED test_1
# PASSED test_2
# PASSED test_3
# ...
```

### 3. 특정 테스트만 실행

```bash
# Worker 모드에서 특정 테스트
pytest tests/test_help_topics.py -n auto --dist load

# 순차 모드에서 특정 테스트
pytest tests/test_help_topics.py -p no:xdist

# 특정 클래스만
pytest tests/test_help_topics.py::TestHelpTopicsBasic -n auto
```

## 테스트 격리 (Isolation) 전략

### 1. 임시 파일 시스템

```python
@pytest.fixture
def temp_home(worker_id):
    """Each worker gets unique HOME directory."""
    with tempfile.TemporaryDirectory(
        prefix=f"dotfiles_test_{worker_id}_"
    ) as tmpdir:
        yield tmpdir
```

**효과:**
- `HOME=/tmp/dotfiles_test_gw0_xxxxx` (Worker 0)
- `HOME=/tmp/dotfiles_test_gw1_xxxxx` (Worker 1)
- 파일 충돌 완전 방지

### 2. 환경 변수 격리

```python
test_env = {
    "HOME": temp_home,           # 임시 홈
    "ZDOTDIR": temp_home,        # 임시 zsh 설정
    "XDG_CONFIG_HOME": temp_home,
    "XDG_CACHE_HOME": temp_home,
    "DOTFILES_TEST_MODE": "1",   # 테스트 모드 활성화
}
```

### 3. 서브셸 격리

```python
def run_command(cmd, shell="bash", env=None):
    """각 명령이 새로운 서브셸에서 실행."""
    full_cmd = f"bash --noprofile --norc -lc '{cmd}'"
    result = subprocess.run(
        full_cmd,
        shell=True,
        capture_output=True,
        env=env,  # 격리된 환경 변수
    )
    return result
```

## 성능 비교

### 테스트 수집 시간

```
병렬 모드 (-n auto):
  collection phase: 1.2s
  runtest phase:    7.8s
  ────────────────────
  Total:            9.0s

순차 모드 (-p no:xdist):
  collection phase: 1.2s
  runtest phase:    248s
  ────────────────────
  Total:            249.2s

속도 향상: 27배 (249s → 9s)
```

### 코어별 성능

```
275개 테스트 기준:

CPU 코어 수  실행 시간  속도 향상
─────────────────────────────
1 (순차)      250초     1.0x
2 코어        130초     1.9x
4 코어        65초      3.8x
8 코어        35초      7.1x
16 코어       18초      13.8x

※ 실제 성능은 테스트 복잡도와 I/O 대기 시간에 따라 다름
```

## 다른 프로젝트에 적용하기

### 1단계: 의존성 설치

```bash
pip install pytest pytest-xdist pexpect

# 또는 requirements에 추가
echo "pytest-xdist" >> requirements-dev.txt
```

### 2단계: pyproject.toml 설정

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-n auto --dist load -v"  # ← 병렬화 설정

markers = [
    "slow: marks tests as slow",
    "unit: marks tests as unit tests",
]
```

### 3단계: conftest.py에 fixture 추가

```python
import tempfile
import pytest

@pytest.fixture
def worker_id(request):
    """pytest-xdist worker identification."""
    if hasattr(request.config, "workerinput"):
        return request.config.workerinput["workerid"]
    return "master"

@pytest.fixture
def temp_dir(worker_id):
    """Isolated temporary directory per worker."""
    with tempfile.TemporaryDirectory(
        prefix=f"test_{worker_id}_"
    ) as tmpdir:
        yield tmpdir
```

### 4단계: 테스트 작성 시 격리 고려

```python
def test_file_operations(temp_dir):
    """각 테스트가 독립적인 디렉토리에서 실행."""
    file_path = os.path.join(temp_dir, "test.txt")
    with open(file_path, "w") as f:
        f.write("test")
    assert os.path.exists(file_path)  # Worker마다 격리됨
```

## 주의사항 (Caveats)

### ⚠️ 1. 공유 상태 피하기

```python
# ❌ 나쁜 예: 전역 변수 (Worker들이 충돌)
GLOBAL_COUNTER = 0

def test_increment():
    global GLOBAL_COUNTER
    GLOBAL_COUNTER += 1  # 동시성 문제!

# ✅ 좋은 예: fixture 사용 (격리됨)
@pytest.fixture
def counter():
    return {"value": 0}

def test_increment(counter):
    counter["value"] += 1  # 각 Worker가 독립적
```

### ⚠️ 2. 파일 시스템 격리

```python
# ❌ 나쁜 예: 고정 경로 (충돌 가능)
def test_write():
    with open("/tmp/test.txt", "w") as f:
        f.write("data")

# ✅ 좋은 예: 임시 디렉토리 (격리됨)
def test_write(temp_dir):
    path = os.path.join(temp_dir, "test.txt")
    with open(path, "w") as f:
        f.write("data")
```

### ⚠️ 3. 환경 변수 격리

```python
# ❌ 나쁜 예: 환경 변수 직접 수정
os.environ["MY_VAR"] = "value"  # 다른 Worker에 영향

# ✅ 좋은 예: 서브프로세스에 전달
env = os.environ.copy()
env["MY_VAR"] = "value"
subprocess.run(cmd, env=env)
```

## 문제 해결 (Troubleshooting)

### 문제 1: pytest-xdist가 작동하지 않음

```bash
# 확인
python3 -m pytest --version
# pytest 7.x with plugins: xdist-2.x

# 재설치
pip install --upgrade pytest-xdist

# 명시적 활성화
pytest tests/ -n auto
```

### 문제 2: 일부 테스트만 병렬화되지 않음

```bash
# 원인: 테스트가 순차 실행을 강제하는 마커 사용
# @pytest.mark.serial

# 확인
pytest tests/ -n auto -v | grep SERIAL

# 해결: 마커 조건 확인
```

### 문제 3: Worker 간 간헐적 실패

```bash
# 원인: 공유 상태 또는 파일 충돌
# 해결: worker_id fixture 사용하여 격리 강화

@pytest.fixture
def unique_file(worker_id):
    """Each worker gets unique file path."""
    path = f"/tmp/test_{worker_id}_{os.getpid()}.txt"
    yield path
    if os.path.exists(path):
        os.remove(path)
```

## 성능 최적화 팁

### 1. 테스트 분류

```python
@pytest.mark.slow
def test_heavy_operation():
    """느린 테스트 표시."""
    pass

# 실행
pytest tests/ -n auto -m "not slow"  # 빠른 테스트만
```

### 2. 로드 밸런싱

```toml
# pyproject.toml
addopts = "-n auto --dist loadscope"
# loadscope: scope별 분배 (더 균형잡힘)
# loadfile: 파일별 분배
# load: 테스트별 분배 (기본)
```

### 3. Worker 수 조절

```bash
# 사용 가능한 모든 코어
pytest tests/ -n auto

# 특정 수의 Worker
pytest tests/ -n 4

# CPU 코어의 N배
pytest tests/ -n auto --maxfail=5
```

## 다른 라이브러리와의 호환성

### pytest-cov (커버리지)

```bash
# 병렬 + 커버리지
pytest tests/ -n auto --cov=. --cov-report=html
```

### pytest-timeout (타임아웃)

```bash
# 병렬 + 타임아웃
pytest tests/ -n auto --timeout=30
```

### pytest-mock (모킹)

```python
# Worker마다 격리된 mock 객체
def test_with_mock(mocker, worker_id):
    mock = mocker.patch("module.function")
    mock.return_value = f"result_{worker_id}"
```

## 요약 (Summary)

| 항목 | 설명 |
|------|------|
| **도구** | pytest-xdist (pytest 플러그인) |
| **설정** | `addopts = "-n auto --dist load"` |
| **속도** | 3~4배 향상 (275개 테스트: 250s → 8s) |
| **격리** | 각 Worker마다 고유한 환경 (temp_home, worker_id) |
| **주의** | 공유 상태 피하기, 파일 시스템 격리 |
| **적용** | pyproject.toml + conftest.py fixture |

## 참고 자료

- [pytest-xdist 공식 문서](https://pytest-xdist.readthedocs.io/)
- [pytest 병렬화 가이드](https://docs.pytest.org/en/stable/xdist.html)
- 현재 프로젝트 구현: `tests/conftest.py`, `tests/test`, `pyproject.toml`

## AI 에이전트 프롬프트 예시

다른 프로젝트에서 테스트를 작성할 때 LLM에게 다음과 같이 요청하세요:

```
# ✅ 권장
"테스트를 작성해줄 때, docs/technic/parallel-testing-with-xdist.md
기술을 따라서 pytest-xdist를 사용한 병렬 실행을 지원하도록
해줘. 각 테스트가 격리된 환경에서 실행되도록."

# 구체적인 지침
"pyproject.toml에 다음을 추가해줘:
- addopts = '-n auto --dist load'
- markers 정의

그리고 conftest.py에 worker_id fixture와
격리된 임시 디렉토리 fixture를 추가해줘."
```

---

**마지막 업데이트**: 2026-01-27
**적용 대상**: 모든 pytest 기반 프로젝트
**성능 향상**: 3~4배 실행 시간 단축
