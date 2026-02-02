# Cross-Review: dotfiles 개선안 통합 분석 (최종판)

**Reviewer**: Claude Sonnet 4.5
**Date**: 2026-02-02
**Reviewed Documents**:
- `abc-review-CM.md` (CodeMate - Architecture)
- `abc-review-R.md` (Roo - SOLID)
- `abc-review-CX.md` (CX - Meta Review)
- `abc-review-G.md` (Gemini - Consolidation)

---

## Executive Summary

**핵심 합의사항**: 4명의 리뷰어 모두 `main.bash/main.zsh`의 **SRP 위반**(과도한 책임)과 **OCP 위반**(확장성 부족)을 최우선 개선 과제로 지목했습니다.

**주요 발견**:
- ✅ **구조적 문제 식별 정확**: 경로 탐지 중복, 로더 로직 하드코딩
- ❌ **사실 오류 다수**: 이미 존재하는 파일(`opencode.sh`, `make_jira.sh`)을 "신규 필요"로 오인
- ⚠️ **프로젝트 규칙 미반영**: 골든 룰(이모지 금지, ux_lib 사용, 경로 하드코딩 금지) 위반 사례 누락

**본 문서 목적**: 4개 리뷰를 통합하고 사실을 확인하여, 실행 가능한 최종 개선 계획을 제시합니다.

---

## 메타 리뷰 통합 (CX + Gemini 피드백)

### CX 핵심 지적사항

| 카테고리 | 내용 |
|---------|------|
| **사실 오류** | `opencode.sh`, `make_jira.sh`, `make_confluence.sh` 이미 존재함 |
| **디렉터리 오류** | `shell-common/util/` 디렉터리는 현재 없음 (신규 생성 필요) |
| **골든 룰 누락** | 이모지 금지, ux_lib 통일, 경로 하드코딩 금지 위반 사례 미제시 |
| **문서 품질** | 링크 형식 오류, 프롬프트 잔재("대답하지 말고 기다려.") |

### Gemini 핵심 보완사항

| 카테고리 | 내용 |
|---------|------|
| **POSIX 준수** | `path_resolver.sh`는 bash/zsh 모두 수정 없이 동작해야 함 |
| **SSOT 정정** | `~/para/archive/rca-knowledge`가 이미 합의된 SSOT (R의 제안 무효) |
| **우선순위 강조** | Core Loading 리팩터링을 **P0**로 명시 |

---

## 사실 확인 및 정정

### 이미 존재하는 파일/기능

| 파일/기능 | 실제 위치 | 이전 리뷰 오류 |
|----------|----------|--------------|
| `opencode.sh` | `shell-common/tools/integrations/opencode.sh` | CM: "신규 생성" 제안 (오류) |
| `make_jira.sh` | `shell-common/tools/custom/make_jira.sh` | R: "구현 안됨" (오류) |
| `make_confluence.sh` | `shell-common/tools/custom/make_confluence.sh` | R: "구현 안됨" (오류) |
| `work-aliases.sh` | `shell-common/aliases/work-aliases.sh` | alias도 이미 존재 |

**실제 문제**: 이들 파일은 존재하지만, `bash/main.bash:305`에 경로 하드코딩이 있음:
```bash
export PATH=/home/bwyoon/.opencode/bin:$PATH  # 골든 룰 위반
```

### 신규 생성 필요 항목

| 항목 | 이유 |
|-----|------|
| `shell-common/util/` 디렉터리 | 현재 없음, 공통 유틸리티 모듈 배치용 |
| `shell-common/config/` 디렉터리 | 로더 설정 파일용 |
| `path_resolver.sh` | 경로 탐지 중앙화 |
| `loader.sh` | 모듈 로딩 추상화 |
| `loader.conf` | skip 목록 외부화 |

---

## 프로젝트 골든 룰 위반 사례

### 발견된 위반 사례 (`bash/main.bash` 기준)

| 위반 규칙 | 위치 | 현재 코드 | 수정 필요 |
|----------|------|----------|----------|
| **경로 하드코딩 금지** | Line 305 | `export PATH=/home/bwyoon/.opencode/bin:$PATH` | `$HOME` 사용 또는 `opencode.sh`로 이동 |
| **ux_lib 사용** | 일부 스크립트 | `echo`, `printf` 직접 사용 | `ux_info`, `ux_success` 등으로 교체 |
| **Interactive Guard** | 일부 sourced 파일 | 가드 누락 가능성 | 전수 검사 필요 |

### 개선 액션

```bash
# bash/main.bash:305 수정 (P0)
# ❌ Before
export PATH=/home/bwyoon/.opencode/bin:$PATH

# ✅ After (Option 1: opencode.sh로 이동)
# bash/main.bash에서 제거, opencode.sh에서 처리

# ✅ After (Option 2: $HOME 사용)
export PATH="${HOME}/.opencode/bin:${PATH}"
```

---

## 4개 리뷰 비교 분석

### CodeMate (Architecture Focus)
**강점**:
- ✅ 구체적 솔루션 제시 (`init_common.sh`, `loader.sh`, `path_resolver.sh`)
- ✅ 플러그인 기반 로더 아키텍처 설계
- ✅ 실행 가능한 파일명/함수명 제안

**약점**:
- ❌ 사실 확인 누락 (`opencode.sh` 이미 존재)
- ❌ 새 파일 생성 과도 (최소 3개 이상)
- ❌ `shell-common/util/` 디렉터리 없는데 전제함

### Roo (Quality & Process)
**강점**:
- ✅ 정량적 평가 (SOLID 36/50)
- ✅ 우선순위 체계 (P0/P1/P2)
- ✅ 리스크 기반 분류 (High/Medium/Low)

**약점**:
- ❌ 사실 확인 누락 (`make_jira.sh`, `make_confluence.sh` 이미 존재)
- ❌ 구체적 구현 방법 부족 (어떻게 할지 불명확)
- ❌ SSOT 제안이 기존 결정(`~/para/archive/rca-knowledge`)과 충돌

### CX (Meta Review)
**강점**:
- ✅ **사실 확인 철저** (이미 존재하는 파일들 정확히 지적)
- ✅ 프로젝트 규칙 반영 강조 (골든 룰 위반 사례)
- ✅ 문서 품질 개선 (링크, 프롬프트 잔재 제거)

**약점**:
- ⚠️ 구체적 해결책은 제시하지 않음 (다른 리뷰 평가에 집중)

### Gemini (Consolidation)
**강점**:
- ✅ **POSIX 준수 요구사항** 추가 (크로스쉘 호환성)
- ✅ 기존 결정사항 존중 (SSOT=rca-knowledge)
- ✅ 통합 액션 플랜 4단계 제시

**약점**:
- ⚠️ 기술적 깊이는 CM보다 얕음

### 통합 평가

| 항목 | CM | R | CX | G | 통합 접근 |
|------|----|----|----|----|----------|
| 구조 설계 | ⭐⭐⭐ | ⭐ | - | ⭐⭐ | CM의 설계 + G의 POSIX 요구사항 |
| 사실 확인 | ❌ | ❌ | ⭐⭐⭐ | ⭐⭐ | CX의 검증 적용 |
| 우선순위 | ⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | R의 체계 유지 |
| 골든 룰 | ❌ | ❌ | ⭐⭐⭐ | ⭐ | CX의 규칙 반영 |
| 실행 가능성 | ⭐⭐ | ⭐ | - | ⭐⭐⭐ | G의 단계별 접근 |

---

## 통합 개선 계획

### Phase 1: 즉시 실행 (1-2주) - P0

#### 1. 경로 탐지 중앙화 ⭐⭐⭐

**현재 문제**:
- `bash/main.bash`와 `zsh/main.zsh`에 동일 로직 중복
- 쉘별 문법 차이로 유지보수 비용 증가

**해결책** (Gemini 요구사항 반영: POSIX 준수):
```bash
# shell-common/util/path_resolver.sh (신규 생성 필요)
#!/usr/bin/env bash
# Direct-exec guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script should be sourced, not executed"
    exit 1
fi

resolve_dotfiles_root() {
    # POSIX-compliant path resolution for both bash and zsh
    if [[ -n "${BASH_VERSION}" ]]; then
        # Bash: Use BASH_SOURCE
        local script_path="${BASH_SOURCE[1]}"
        echo "$(cd "$(dirname "${script_path}")/.." && pwd)"
    elif [[ -n "${ZSH_VERSION}" ]]; then
        # Zsh: Use :A:h modifiers
        echo "${0:A:h:h}"
    else
        # Fallback for unknown shells
        echo "$(cd "$(dirname "$0")/.." && pwd)"
    fi
}
```

**로딩 방식**:
```bash
# bash/main.bash, zsh/main.zsh 공통 사용
# SHELL_COMMON은 수동 설정 (부트스트랩 단계)
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"
source "${SHELL_COMMON}/util/path_resolver.sh"
export DOTFILES_ROOT="$(resolve_dotfiles_root)"
```

**테스트 케이스**:
```bash
# tests/test_path_resolver.sh
test_bash_real_path() {
    result=$(bash -c "source shell-common/util/path_resolver.sh && resolve_dotfiles_root")
    assert_equals "/home/bwyoon/dotfiles" "$result"
}

test_zsh_symlink_path() {
    ln -s "$PWD/bash/main.bash" /tmp/test_symlink.bash
    result=$(bash /tmp/test_symlink.bash)
    assert_equals "/home/bwyoon/dotfiles" "$result"
}
```

#### 2. main.bash/main.zsh SRP 분리 + 골든 룰 위반 수정 ⭐⭐

**현재 책임 (6가지)**:
1. 인터랙티브 가드
2. 경로 초기화
3. UX 라이브러리 로드
4. 모듈 자동 로드
5. PATH 조작 (opencode 등) - **골든 룰 위반**
6. 툴 초기화

**개선 목표**: 모듈 로드 오케스트레이션만 담당 (50줄 미만)

```bash
# bash/main.bash (개선 후)
#!/usr/bin/env bash

# 1. Interactive guard (유지)
[[ $- != *i* ]] && return

# 2. Bootstrap: 최소 경로 설정 (SHELL_COMMON만)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT="${_SCRIPT_DIR%/*}"
export SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

# 3. Path resolver 로드 (검증용)
source "${SHELL_COMMON}/util/path_resolver.sh"

# 4. Loader 로드
source "${SHELL_COMMON}/util/loader.sh"

# 5. 표준 로드 순서 실행
load_category "env"        # 환경 변수
load_category "aliases"    # 별칭
load_category "functions"  # 함수
load_category "integration" # 외부 도구 (opencode 등 - 여기서 PATH 설정)
load_category "projects"   # 프로젝트별 설정

# 6. Bash 전용 설정 (최소)
shopt -s histappend
shopt -s checkwinsize
```

**골든 룰 준수**:
- ✅ `export PATH=/home/bwyoon/.opencode/bin` 제거 → `opencode.sh`로 이동
- ✅ `$HOME` 사용 (하드코딩 제거)
- ✅ 모든 출력은 `ux_lib` 사용 (echo 금지)

### Phase 2: 품질 개선 (2-4주)

#### 3. 로더 설정 외부화

```bash
# shell-common/config/loader.conf
util
temp
deprecated

# shell-common/util/loader.sh
load_category() {
    local skip_list="${SHELL_COMMON}/config/loader.conf"
    # skip 목록 기반 로드
}
```

#### 4. LSP 위반 래퍼 수정

```bash
# ❌ BAD: 계약 변경
ls() { command ls -lh "$@"; }

# ✅ GOOD: 별도 alias
alias ll='ls -lh'
```

### Phase 3: 확장성 (4-8주)

#### 5. 직접-exec 가드 CI

```bash
# .github/workflows/lint.yml
find shell-common/tools/custom -name "*.sh" | while read f; do
  grep -q 'BASH_SOURCE\[0\].*==.*\${0}' "$f" || exit 1
done
```

---

## 우선순위 (최종)

| P | 항목 | 출처 | 공수 | 리스크 | 비고 |
|---|------|------|------|--------|------|
| **0** | **골든 룰 위반 수정** | **CX** | **1일** | **낮음** | **bash/main.bash:305 경로 하드코딩** |
| **0** | **경로 탐지 중앙화** | **CM+G** | **2일** | **낮음** | **POSIX 준수 필수** |
| **0** | **main.bash/zsh SRP** | **CM+R+G** | **5일** | **중간** | **50줄 미만 목표** |
| 1 | 로더 설정 외부화 | CM | 3일 | 낮음 | loader.conf 생성 |
| 1 | LSP 감사 | R | 3일 | 낮음 | 래퍼 함수 5개 이상 |
| 2 | 직접-exec CI | R+CX | 1일 | 낮음 | shell-common/tools/custom/ 검증 |
| 2 | 문서 정정 | CX | 1일 | 낮음 | 링크, 프롬프트 잔재 제거 |

---

## 테스트 전략 (CM+R 누락, Gemini 보완)

### 필수 테스트 케이스

```bash
# tests/test_path_resolver.sh (Gemini: 경량 프레임워크 사용)
test_bash_real_path() {
    result=$(bash -c "source shell-common/util/path_resolver.sh && resolve_dotfiles_root")
    [[ "$result" == "/home/bwyoon/dotfiles" ]] || { echo "FAIL: $result"; exit 1; }
}

test_zsh_symlink_path() {
    ln -s "$PWD/bash/main.bash" /tmp/test_symlink.bash
    result=$(zsh /tmp/test_symlink.bash 2>&1 | grep DOTFILES_ROOT)
    [[ -n "$result" ]] || { echo "FAIL: No output"; exit 1; }
}

test_posix_fallback() {
    # POSIX sh 호환성 검증
    result=$(sh -c ". shell-common/util/path_resolver.sh && resolve_dotfiles_root" 2>&1)
    echo "$result" | grep -q dotfiles || { echo "FAIL: POSIX incompatible"; exit 1; }
}

# tests/test_loader.sh
test_skip_dirs_from_config() {
    echo "util" > shell-common/config/loader.conf
    source shell-common/util/loader.sh
    # util 디렉터리가 로드되지 않아야 함
}

test_load_order_preserved() {
    # env -> aliases -> functions 순서 보장
}

# tests/test_golden_rules.sh (신규)
test_no_hardcoded_paths() {
    grep -r "export PATH=/home" bash/ zsh/ && { echo "FAIL: hardcoded path"; exit 1; }
    return 0
}

test_ux_lib_usage() {
    # echo/printf 직접 사용 금지 검증
    grep -r "^\s*echo\s" shell-common/functions/ && { echo "WARN: raw echo found"; }
}
```

### CI 통합

```yaml
# tox.ini 업데이트
[testenv:shell]
commands =
    bash tests/test_path_resolver.sh
    bash tests/test_loader.sh
    bash tests/test_golden_rules.sh
    pytest tests/  # 기존 Python 테스트
```

---

## 최종 권고 (4개 리뷰 통합)

### ✅ 즉시 채택 (P0)
- **CodeMate**: 경로 탐지 중앙화 (`path_resolver.sh`)
- **Gemini**: POSIX 준수 요구사항 추가
- **CX**: 골든 룰 위반 수정 우선
- **Roo**: 우선순위 체계 (P0/P1/P2)

### ⚠️ 수정 후 채택 (P1)
- **CodeMate**: 로더 외부 설정 (loader.conf) - 단, `shell-common/util/` 디렉터리 신규 생성 필요
- **Roo**: LSP 감사 - 구체적 예시 추가 필요 (어떤 래퍼가 문제인지)
- **CX**: 사실 오류 정정 (`opencode.sh`, `make_jira.sh` 이미 존재)

### ❌ 보류 또는 거부
- **CodeMate**: 플러그인 메타데이터 시스템 (Phase 3 이후로 연기, 복잡도 과다)
- **CodeMate**: UX 라이브러리 완전 분리 (현재 필요성 낮음, 향후 재검토)
- **Roo**: `docs/worklog/`, `docs/jira/` 생성 (SSOT는 `~/para/archive/rca-knowledge`로 이미 결정됨)

### 📋 문서 정정 필요 (P2)
- **CX 지적사항**:
  - `abc-review-CM.md`, `abc-review-R.md` 말미의 "# 대답하지 말고 기다려." 제거
  - 링크 형식 수정 (`AGENTS.md:1` → `../../AGENTS.md`)
  - 생성일 메타데이터 수정 (`$(date ...)` → 실제 날짜)

---

## Action Items (최종 실행 계획)

### Phase 0: 사전 준비 (Day 1)
- [ ] **디렉터리 생성**: `shell-common/util/`, `shell-common/config/`
- [ ] **골든 룰 위반 수정**: `bash/main.bash:305` 경로 하드코딩 제거
  ```bash
  # 수정 전: export PATH=/home/bwyoon/.opencode/bin:$PATH
  # 수정 후: opencode.sh로 이동 또는 $HOME 사용
  ```
- [ ] **문서 정정**: CM, R 리뷰 문서에서 프롬프트 잔재 제거

### Phase 1: Core Refactoring (Week 1-2) - P0
- [ ] **`path_resolver.sh` 구현** (POSIX 준수, Gemini 요구사항)
  - [ ] bash/zsh/sh 모두에서 테스트
  - [ ] `tests/test_path_resolver.sh` 작성
- [ ] **`main.bash` 리팩터링** (50줄 미만 목표)
  - [ ] PATH 조작 로직 제거 → `opencode.sh`로 이동
  - [ ] 로더 호출로 단순화
- [ ] **`main.zsh` 리팩터링** (50줄 미만 목표)
  - [ ] `main.bash`와 동일 구조 적용

### Phase 2: Loader Enhancement (Week 3-4) - P1
- [ ] **`loader.conf` 생성** (skip 목록 외부화)
- [ ] **`loader.sh` 구현** (모듈 로딩 추상화)
- [ ] **LSP 위반 감사**
  - [ ] `shell-common/functions/` 전체 래퍼 함수 검토
  - [ ] 계약 위반 함수 최소 5개 수정
- [ ] **테스트**: `tests/test_loader.sh` 작성

### Phase 3: Quality & Verification (Week 5-6) - P2
- [ ] **직접-exec 가드 CI**
  - [ ] `.github/workflows/lint.yml` 업데이트
  - [ ] `shell-common/tools/custom/` 전체 검증
- [ ] **골든 룰 검증 테스트**
  - [ ] `tests/test_golden_rules.sh` 작성
  - [ ] 경로 하드코딩, echo 직접 사용 등 검사
- [ ] **문서 업데이트**
  - [ ] `docs/ARCHITECTURE.md` - 로딩 메커니즘 다이어그램
  - [ ] `AGENTS.md` - 새 디렉터리 구조 반영
- [ ] **테스트 커버리지 60%+** 달성

### 검증 체크리스트
- [ ] `tox` 전체 통과
- [ ] bash/zsh 양쪽에서 dotfiles 로딩 성공
- [ ] 경로 하드코딩 0건
- [ ] 모든 새 스크립트에 direct-exec 가드 존재
- [ ] 문서에 사실 오류 0건

---

## 변경 이력

- **2026-02-02 (초안)**: CM, R 리뷰 통합
- **2026-02-02 (최종)**: CX, Gemini 피드백 반영, 사실 확인 완료, 골든 룰 위반 사례 추가

_Reviewer: Claude Sonnet 4.5_
_Final Review Date: 2026-02-02_
