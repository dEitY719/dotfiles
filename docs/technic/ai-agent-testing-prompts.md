# AI 에이전트를 위한 테스트 작성 프롬프트 가이드

## 목표

LLM(Claude, Coding Agent 등)에게 테스트를 작성하도록 요청할 때, **병렬 실행 가능한 격리된 테스트**를 작성하도록 하는 프롬프트 템플릿.

## 프롬프트 작성의 3단계

### 1단계: 기본 프롬프트 (최소)

사용자가 최소한 이 정도는 명시해야 함:

```
테스트를 작성해줄 때, pytest-xdist를 사용한 병렬 실행을
지원하도록 해줘. 각 테스트가 독립적으로 실행될 수 있도록
격리된 환경에서 작동해야 해.

참고: docs/technic/parallel-testing-with-xdist.md
```

### 2단계: 중간 프롬프트 (권장)

더 자세한 요구사항 명시:

```
테스트를 작성할 때 다음을 따라줄래?

1. **병렬 실행 지원**
   - pyproject.toml에 다음 추가:
     addopts = "-n auto --dist load"

2. **conftest.py 설정**
   - worker_id fixture 추가 (pytest-xdist worker 감지)
   - 격리된 임시 디렉토리 fixture 추가
   - 각 테스트가 고유한 리소스 사용하도록

3. **테스트 작성**
   - @pytest.mark.parametrize 사용 (cross-shell)
   - fixture 사용 (전역 상태 금지)
   - 각 Worker마다 고유한 이름/경로 사용

참고: docs/technic/parallel-testing-with-xdist.md
참고: docs/technic/test-architecture-review.md
```

### 3단계: 상세 프롬프트 (최적)

완전한 요구사항 명시:

```
테스트 코드를 작성해줄 때 다음을 꼭 따라줄래:

## A. pyproject.toml 설정

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-n auto --dist load -v"
# -n auto: 모든 CPU 코어 사용
# --dist load: 로드 균형 분배

markers = [
    "slow: marks tests as slow",
    "unit: unit tests",
]

## B. conftest.py 구조

import tempfile
import pytest

@pytest.fixture
def worker_id(request):
    """pytest-xdist worker 감지."""
    if hasattr(request.config, "workerinput"):
        return request.config.workerinput["workerid"]
    return "master"

@pytest.fixture
def temp_dir(worker_id):
    """각 Worker마다 격리된 임시 디렉토리."""
    with tempfile.TemporaryDirectory(
        prefix=f"test_{worker_id}_"
    ) as tmpdir:
        yield tmpdir

## C. 테스트 작성 규칙

1. Parametrization 필수:
   @pytest.mark.parametrize("param", ["value1", "value2"])
   def test_something(param):
       ...

2. Fixture 사용 (전역 상태 금지):
   def test_file_op(temp_dir):  # temp_dir 사용
       path = os.path.join(temp_dir, "file.txt")
       ...

3. Worker별 고유 리소스:
   def test_resource(worker_id):
       name = f"resource_{worker_id}"  # 고유 이름
       ...

4. 금지 패턴:
   - os.environ 직접 수정 ❌
   - 고정 경로 /tmp/file.txt ❌
   - 전역 변수 수정 ❌
   - 하드코드된 포트/파일 ❌

참고:
- docs/technic/parallel-testing-with-xdist.md (구현 가이드)
- docs/technic/test-architecture-review.md (아키텍처)
```

## 프롬프트 템플릿 예시

### 예시 1: 새 프로젝트용 기본 프롬프트

```
프로젝트명: DataProcessor
테스트 대상: CSV 파일 처리 함수들

테스트를 작성해줄 때:
1. pytest-xdist를 사용한 병렬 실행 지원
2. 각 테스트는 격리된 임시 디렉토리에서 실행
3. 여러 입력값으로 parametrize 사용
4. 공유 상태 없이 독립적으로 실행 가능하도록

필수 요구사항:
- pyproject.toml: addopts = "-n auto --dist load"
- conftest.py: worker_id, temp_dir fixture
- tests/test_*.py: parametrized, isolated tests

참고: docs/technic/parallel-testing-with-xdist.md
```

### 예시 2: 기존 프로젝트 테스트 개선용 프롬프트

```
프로젝트명: MyWebApp
현재 문제: 테스트가 느림 (500초), 간헐적 실패 있음

개선 사항:
1. pytest-xdist 도입으로 3-4배 속도 향상 (목표: 60초)
2. 테스트 격리 강화로 간헐적 실패 제거

할 일:
- pyproject.toml 설정 추가
- conftest.py 리팩토링 (worker_id, temp_dir)
- 기존 테스트 업데이트 (fixture 사용, parametrize)

금지 사항:
- 테스트 간 파일 공유
- 고정 포트/경로 사용
- 환경 변수 직접 수정
- 테이터베이스 공유 상태

참고 기술: docs/technic/parallel-testing-with-xdist.md
```

### 예시 3: 특정 테스트 타입용 프롬프트

```
테스트 타입: Shell 명령어 호환성 (bash/zsh)
테스트 수: ~100개

요구사항:
1. bash와 zsh 모두에서 각 명령 검증
2. 각 셸은 독립적인 환경에서 실행
3. 격리된 HOME, PATH 사용
4. pytest-xdist 병렬 실행 지원

구현:
@pytest.mark.parametrize("shell", ["bash", "zsh"])
def test_command(shell_runner, shell):
    result = shell_runner(shell, "my_command")
    assert result.exit_code == 0

conftest.py:
def run_command(cmd, shell, env):
    # shell_runner: 격리된 환경에서 명령 실행
    # 각 Worker마다 고유한 HOME

참고: docs/technic/test-architecture-review.md
```

## LLM별 프롬프트 최적화

### Claude (Claude Code) 사용 시

```
# @병렬-테스트-xdist

I want you to write pytest tests with parallel execution support.
Follow the patterns in docs/technic/parallel-testing-with-xdist.md.

Requirements:
✓ Use pytest-xdist (-n auto)
✓ Each test isolated (temp directories)
✓ Parametrize for cross-platform testing
✓ No global state or shared resources
✓ conftest.py with worker_id fixture

Files to update:
- pyproject.toml: addopts = "-n auto --dist load"
- tests/conftest.py: worker_id, temp_dir fixtures
- tests/test_*.py: new tests with isolation
```

### Generic LLM/Coding Agent 사용 시

```
Write test code following the architecture in:
- docs/technic/parallel-testing-with-xdist.md
- docs/technic/test-architecture-review.md

Key patterns to follow:

1. pytest-xdist configuration:
   addopts = "-n auto --dist load -v"

2. conftest.py fixtures:
   - worker_id(request): detect xdist worker
   - temp_dir(worker_id): isolated temp directory

3. Test patterns:
   @pytest.mark.parametrize("param", [...])
   def test_feature(fixture_name, param):
       # Each test runs in isolation
       # Use temp_dir, worker_id for unique resources

4. Isolation rules:
   ✓ Use fixtures for resources
   ✗ Don't modify os.environ
   ✗ Don't use hardcoded paths
   ✗ Don't modify global variables
```

## 프롬프트 사용 체크리스트

### 기본 체크리스트 (모든 테스트)

- [ ] pytest-xdist 명시 (`-n auto --dist load`)
- [ ] fixture 사용 강조 (전역 상태 금지)
- [ ] parametrize 권장
- [ ] worker_id 감지 필요
- [ ] 격리된 환경 요구

### 고급 체크리스트 (복잡한 테스트)

- [ ] `--dist load` vs `--dist loadscope` 선택
- [ ] 테스트 마커 정의
- [ ] 타임아웃 설정
- [ ] 커버리지 통합
- [ ] CI/CD 통합

### 문제 해결 체크리스트

- [ ] "간헐적 실패" → 공유 상태 확인
- [ ] "느린 테스트" → 병렬화 비활성화 확인
- [ ] "파일 충돌" → worker_id 사용 확인
- [ ] "Worker 간 데이터 공유" → fixture 사용 확인

## 응답 검증 체크리스트

LLM이 생성한 테스트 코드를 검증할 때:

### 필수 요소

```python
# ✓ fixture 사용
def test_something(temp_dir):  # ✓ fixture
    path = os.path.join(temp_dir, "file.txt")  # ✓ 격리

# ✓ parametrize 사용
@pytest.mark.parametrize("value", [1, 2, 3])
def test_values(value):  # ✓ 반복 실행

# ✓ worker_id 감지
@pytest.fixture
def resource(worker_id):
    return allocate(f"res_{worker_id}")  # ✓ 고유
```

### 금지 요소

```python
# ✗ 전역 상태
COUNTER = 0  # ✗ 제거
os.environ["VAR"] = "val"  # ✗ 금지

# ✗ 고정 경로
"/tmp/test.txt"  # ✗ worker_id 사용
"localhost:5000"  # ✗ 포트 충돌

# ✗ 공유 파일
db_path = "/home/data.db"  # ✗ fixture 사용
```

## 프롬프트 생성 도구

### Python으로 프롬프트 생성

```python
def generate_parallel_test_prompt(
    project_name,
    test_type,
    num_tests,
    special_requirements=None
):
    """AI 에이전트용 프롬프트 자동 생성."""

    base_prompt = f"""
프로젝트명: {project_name}
테스트 타입: {test_type}
예상 테스트 수: {num_tests}

병렬 실행 지원 테스트를 작성해줄 때:
1. pytest-xdist 사용 (-n auto --dist load)
2. conftest.py: worker_id, temp_dir fixture
3. 각 테스트는 격리된 환경에서 실행
4. Parametrize와 fixture 사용
5. 금지: 전역 상태, 고정 경로, 환경변수 수정

참고: docs/technic/parallel-testing-with-xdist.md
    """

    if special_requirements:
        base_prompt += f"\n특수 요구사항: {special_requirements}"

    return base_prompt

# 사용 예
prompt = generate_parallel_test_prompt(
    "MyProject",
    "Unit Tests",
    150,
    "Database isolation, cross-platform"
)
print(prompt)
```

## 실전 예시

### 문제: "테스트가 250초 걸림"

✅ 올바른 프롬프트:

```
현재: 테스트가 250초 (순차 실행)
목표: 60초 이하 (병렬 실행)

pytest-xdist를 사용한 병렬화를 해줄래?
- pyproject.toml에 addopts = "-n auto --dist load"
- conftest.py에 worker_id, temp_dir fixture
- 기존 테스트 업데이트로 격리 강화

참고: docs/technic/parallel-testing-with-xdist.md
```

❌ 나쁜 프롬프트:

```
테스트를 빠르게 해줄래.
(LLM이 뭘 해야 할지 불명확)
```

### 문제: "테스트가 간헐적으로 실패"

✅ 올바른 프롬프트:

```
간헐적 실패 (파일 충돌 의심):
- 테스트 간 /tmp/test.json 공유
- 여러 Worker가 동시에 접근

pytest-xdist 격리를 적용해줄래:
1. 각 테스트가 고유한 파일명 사용 (worker_id)
2. 격리된 임시 디렉토리 (temp_dir fixture)
3. conftest.py 업데이트

참고: docs/technic/parallel-testing-with-xdist.md
```

❌ 나쁜 프롬프트:

```
테스트가 간헐적으로 실패해.
(원인과 해결책이 명확하지 않음)
```

## 프롬프트 라이브러리

### 빠른 참조

```markdown
## 병렬 테스트 프롬프트 라이브러리

### [새 프로젝트]
tests/write-parallel-tests:
  "pytest-xdist 사용 + docs/technic/parallel-testing-with-xdist.md 따르기"

### [기존 프로젝트]
tests/parallelize-tests:
  "pytest-xdist 추가로 테스트 속도 3-4배 향상"

### [테스트 개선]
tests/fix-flaky-tests:
  "pytest-xdist 격리로 간헐적 실패 제거"

### [새 기능]
tests/add-cross-platform:
  "@pytest.mark.parametrize 사용한 cross-shell 테스트"
```

## 결론

### 효과적인 프롬프트 3원칙

1. **명확성**: docs 파일 명시 (docs/technic/...)
2. **구체성**: 설정값 제시 (addopts = "-n auto --dist load")
3. **검증성**: 체크리스트 제공 (금지 패턴, 필수 요소)

### 기억할 것

- pytest-xdist 병렬화 = **3~4배 속도 향상**
- worker_id fixture = **Worker 간 격리**
- temp_dir fixture = **파일 시스템 격리**
- @parametrize = **반복 실행 자동화**

### 문서 참고 순서

1. **빠른 시작**: parallel-testing-with-xdist.md (개요)
2. **구현 세부**: test-architecture-review.md (상세)
3. **프롬프트**: ai-agent-testing-prompts.md (이 문서)

---

**버전**: 1.0
**마지막 업데이트**: 2026-01-27
**적용 범위**: 모든 pytest 기반 프로젝트
**목표**: AI 에이전트 → 고품질 병렬 테스트 자동 생성
