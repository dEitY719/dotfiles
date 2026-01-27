# 테크닉 문서 (Technic Documentation)

## 개요

이 디렉토리는 dotfiles 프로젝트에서 검증된 고급 기술들을 문서화합니다.
각 기술은 다른 프로젝트에서도 재사용 가능하도록 설계되었습니다.

## 문서 목록

### 1. 병렬 테스트 실행 (Parallel Testing with pytest-xdist)

**파일**: `parallel-testing-with-xdist.md`

**개요**: pytest-xdist를 사용한 병렬 테스트 실행 기술
- 순차 실행: ~250초
- 병렬 실행: ~60-80초
- **속도 향상: 3~4배**

**주요 내용**:
- pytest-xdist 기본 개념
- pyproject.toml 설정 (`-n auto --dist load`)
- Worker 간 격리 메커니즘
- 성능 비교 및 최적화
- 다른 프로젝트 적용 방법

**읽어야 할 대상**:
- 테스트를 작성하는 개발자
- 테스트 성능 개선이 필요한 팀
- 새로운 프로젝트를 시작하는 사람

**실행 예시**:
```bash
# 병렬 실행 (기본)
./tests/test              # 60-80초

# 순차 실행 (디버깅)
./tests/test -s           # 250초
```

### 2. 테스트 아키텍처 검토 (Test Architecture Review)

**파일**: `test-architecture-review.md`

**개요**: 현재 프로젝트의 테스트 구조 상세 분석
- 파일 구조 및 역할
- 275개 테스트 분류
- 격리 메커니즘 설명
- 확장 가능성

**주요 내용**:
- `tests/` 디렉토리 구조
- 각 파일의 역할 (test, conftest.py, test_*.py)
- 테스트 격리 전략 (프로세스, 파일시스템, 환경변수)
- 성능 특성 분석
- 테스트 작성 가이드 (권장/금지 패턴)
- 문제 해결

**읽어야 할 대상**:
- 테스트 코드를 작성하는 개발자
- 테스트 아키텍처를 이해하고 싶은 사람
- 격리 메커니즘을 학습하고 싶은 사람

**주요 섹션**:
- ✅ 권장 패턴 (parametrization, fixture, worker_id)
- ❌ 금지된 패턴 (전역 상태, 고정 경로)

### 3. AI 에이전트 테스트 프롬프트 (AI Agent Testing Prompts)

**파일**: `ai-agent-testing-prompts.md`

**개요**: LLM(Claude, Coding Agent 등)에게 테스트를 작성하도록 요청하는 프롬프트 가이드
- 효과적인 프롬프트 작성법
- 3단계 프롬프트 템플릿
- 실전 예시
- 응답 검증 체크리스트

**주요 내용**:
- 기본/중간/상세 프롬프트 템플릿
- LLM별 최적화 (Claude, Generic Agent)
- 프롬프트 생성 도구 (Python 코드)
- 문제별 프롬프트 예시
- 응답 검증 체크리스트

**읽어야 할 대상**:
- Claude Code / Coding Agent 사용자
- 다른 프로젝트에서 병렬 테스트를 적용하고 싶은 사람
- AI 에이전트를 효과적으로 사용하고 싶은 사람

**사용 시나리오**:
1. 새 프로젝트 시작 → 기본 프롬프트 사용
2. 기존 테스트 개선 → 중간 프롬프트 사용
3. 구체적 요구사항 → 상세 프롬프트 사용

## 문서 관계도

```
┌─ parallel-testing-with-xdist.md (병렬화 기술)
│  └─ 실제 구현 예시
│     (pyproject.toml, conftest.py 설정값)
│
├─ test-architecture-review.md (아키텍처)
│  └─ 현재 프로젝트의 구현
│     (275개 테스트, 격리 메커니즘)
│
└─ ai-agent-testing-prompts.md (프롬프트)
   └─ LLM을 위한 지침
      (다른 프로젝트에 적용)
```

## 빠른 시작 (Quick Start)

### 현재 프로젝트에서 병렬 테스트 실행

```bash
# 1. 테스트 실행 (기본: 병렬)
./tools/dev.sh test
# 결과: 8-9초 (275개 테스트)

# 2. 상세 실행
./tests/test -v
# 결과: 각 Worker의 진행상황 표시

# 3. 순차 실행 (디버깅)
./tests/test -s
# 결과: 250초 (느리지만 상세한 에러)
```

### 새 프로젝트에 적용

```bash
# 1. 문서 읽기
cat docs/technic/parallel-testing-with-xdist.md

# 2. AI 에이전트에 프롬프트 전달
# (ai-agent-testing-prompts.md 참고)

# 3. 설정 추가
# pyproject.toml: addopts = "-n auto --dist load"
# conftest.py: worker_id, temp_dir fixture

# 4. 테스트 작성 및 실행
pytest tests/ -n auto
```

## 기술 스택

### 사용 기술
- **pytest**: 테스트 프레임워크
- **pytest-xdist**: 병렬 실행 플러그인
- **tempfile**: 격리된 임시 파일시스템
- **subprocess**: 서브셸 격리

### 성능 특성
- 병렬 모드: 8-9초 (275개 테스트, 4-8개 코어)
- 순차 모드: 250초
- 속도 향상: **27배**
- Worker 수: CPU 코어 수에 따라 자동

## 적용 가능 프로젝트 타입

✅ **적합한 프로젝트**:
- Python 기반 프로젝트
- pytest 사용 프로젝트
- 여러 입력값으로 테스트하는 프로젝트 (@parametrize)
- Shell/CLI 테스트가 많은 프로젝트
- 크로스 플랫폼 호환성 테스트 필요 프로젝트

❌ **부적합한 프로젝트**:
- 테스트 간 공유 상태 필수
- 단일 프로세스 테스트만 가능
- 격리 불가능한 외부 의존성

## 주요 개념 정리

### Worker란?

```
Master (메인 프로세스)
    │
    ├─► Worker 0 (독립 프로세스) → test 1, 2, 3
    ├─► Worker 1 (독립 프로세스) → test 4, 5, 6
    └─► Worker 2 (독립 프로세스) → test 7, 8, 9

각 Worker는 독립적인 Python 프로세스
→ 서로 간섭 없이 동시 실행 가능
```

### Worker ID란?

```
master  → 순차 실행 (단일 프로세스)
gw0     → Worker 0
gw1     → Worker 1
gw2     → Worker 2
```

### 격리(Isolation)란?

```
각 테스트가 영향을 주지 않도록:
✓ 고유한 HOME 디렉토리
✓ 고유한 임시 파일 경로
✓ 고유한 환경 변수
✓ 고유한 리소스 이름 (포트, DB, 등)
```

## 체크리스트

### 새 프로젝트 시작

- [ ] `docs/technic/parallel-testing-with-xdist.md` 읽기
- [ ] `pyproject.toml` 설정 추가
- [ ] `conftest.py` 작성 (worker_id, temp_dir)
- [ ] 첫 테스트 작성 (parametrize + fixture)
- [ ] 병렬 실행 확인

### 기존 프로젝트 마이그레이션

- [ ] `docs/technic/test-architecture-review.md` 읽기
- [ ] 기존 테스트 검토 (격리 문제 확인)
- [ ] pytest-xdist 설치
- [ ] conftest.py 추가/업데이트
- [ ] 기존 테스트 리팩토링
- [ ] 성능 비교 (순차 vs 병렬)

### AI 에이전트 활용

- [ ] `docs/technic/ai-agent-testing-prompts.md` 읽기
- [ ] 프롬프트 템플릿 선택
- [ ] LLM에 요청
- [ ] 생성 코드 검증 (체크리스트)
- [ ] 병렬 실행 확인

## FAQ

### Q1: pytest-xdist는 무엇인가?

**A**: pytest 플러그인으로, 여러 CPU 코어를 활용하여 테스트를 동시에 실행합니다.
- 순차 실행: 1개 코어, 느림
- 병렬 실행: N개 코어, 빠름 (3-4배)

### Q2: 모든 테스트에 적용 가능한가?

**A**: 대부분 가능하지만, 다음을 확인해야 합니다:
- ❌ 테스트 간 공유 상태가 없는가?
- ❌ 파일 충돌이 없는가?
- ❌ 환경 변수 공유가 없는가?

위 조건을 만족하면 `docs/technic/parallel-testing-with-xdist.md` 참고 적용 가능.

### Q3: 순차 실행이 필요한 경우는?

**A**: 디버깅 시:
```bash
./tests/test -s  # 순차 실행
# 또는
pytest tests/ -p no:xdist
```

### Q4: AI 에이전트로 테스트를 만들면 자동으로 병렬화되나?

**A**: 아니오. 프롬프트에 명시해야 합니다.
참고: `docs/technic/ai-agent-testing-prompts.md`

### Q5: 다른 프로젝트에도 같은 설정을 써도 되나?

**A**: 네. 이 기술은 프로젝트 독립적입니다.
- pyproject.toml: `addopts = "-n auto --dist load"`
- conftest.py: worker_id, temp_dir fixture 추가
- 테스트: parametrize + fixture 사용

## 더 알아보기

### 성능 분석
- 275개 테스트, 4 CPU 코어
- 병렬: 8.45초 (27배 향상)
- 각 Worker: 2-3초 (로드 균형)

### 테스트 카테고리
- Help Topics: 68개
- Custom Tools: 76개
- Compatibility: 32개
- 기타: 99개

### 격리 전략
- 프로세스 격리: 각 Worker는 독립 프로세스
- 파일시스템 격리: 임시 홈 디렉토리
- 환경 격리: 고유한 환경 변수

## 이 기술의 영향

### 개발 생산성
- ✅ 테스트 실행 시간 **60초 단축** (타임아웃 리스크 감소)
- ✅ 개발자 피드백 **빠르게** (개발 사이클 단축)
- ✅ CI/CD 시간 **3배 단축**

### 코드 품질
- ✅ 간헐적 실패 제거 (격리)
- ✅ 테스트 신뢰성 향상
- ✅ 회귀 버그 감소

### 팀 효율성
- ✅ 테스트 작성 패턴 표준화
- ✅ AI 에이전트로 테스트 자동 생성 가능
- ✅ 다른 프로젝트에 재사용 가능

## 지원

### 문제 해결
1. `parallel-testing-with-xdist.md` → "문제 해결" 섹션
2. `test-architecture-review.md` → "문제 해결" 섹션

### 프롬프트 생성
1. `ai-agent-testing-prompts.md` 참고
2. 자신의 상황에 맞는 템플릿 선택

### 피드백
- 이 기술 개선 제안: Git Issue
- 문서 개선 제안: Pull Request

---

**마지막 업데이트**: 2026-01-27
**버전**: 1.0
**상태**: 완성 (Production Ready)

## 문서 네비게이션

```
README.md (이 파일)
    ├─ parallel-testing-with-xdist.md (구현 가이드)
    ├─ test-architecture-review.md (아키텍처 분석)
    └─ ai-agent-testing-prompts.md (LLM 프롬프트)
```

**다음**: `parallel-testing-with-xdist.md` 읽기 시작
