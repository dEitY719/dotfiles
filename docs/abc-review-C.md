# ABC Review - Git Hook Management System (Combined Review)

> **검토 날짜**: 2026-01-22
> **검토자**: Claude (Explanatory Mode) + GPT-5.2 (Codex CLI) + Team Review
> **검토 범위**: `git/` 디렉토리 Hook 관리 시스템
> **검토 목적**: SSOT, SOLID 원칙 준수 여부 및 반복 실수 예방 메커니즘 평가

---

## 🚨 **CRITICAL FINDINGS** (동료 리뷰에서 발견)

### ⛔ P0: 보안 크리티컬 - 즉시 조치 필요

**1. SECRET 파일이 Git에 Tracked 상태**

```bash
$ git ls-files git/.git-credentials
git/.git-credentials    # ← 레포에 추적됨!
```

**위험도**: CRITICAL
**영향**: 토큰/credential이 이미 공개 저장소에 노출되었을 경우 계정 탈취, 조직 보안 사고로 즉시 이어질 수 있음

**즉시 조치**:
```bash
# 1. 파일 추적 해제 및 .gitignore 추가
git rm --cached git/.git-credentials
echo "git/.git-credentials" >> .gitignore

# 2. 토큰 폐기/재발급 (이미 노출되었다고 가정)
# GitHub Enterprise: Settings → Developer settings → Personal access tokens → Revoke

# 3. Hook에서 파일명 기반 차단 추가
FORBIDDEN_FILES=".git-credentials|.env|id_rsa|*.pem|credentials.json"
```

**2. NUL-safe 주장과 실제 구현의 불일치**

**문제**: 문서(HOOK_WORKFLOW.md)는 "NUL-safe 처리"를 강조하지만, 실제 구현은 NUL-safe가 아님

```bash
# git/global-hooks/pre-commit:100
STAGED_FILES_NUL=$(git diff --cached --name-only -z --diff-filter=ACM)
```

**왜 문제인가**: Bash 변수는 NUL 문자(`\0`)를 보존할 수 없음. 변수에 담는 순간 NUL이 손실되어 파일명에 공백이 있으면 여전히 오작동 가능.

**올바른 구현** (P1 우선순위):
```bash
# NUL-safe 스트리밍 처리
git diff --cached --name-only -z --diff-filter=ACM | while IFS= read -r -d '' file; do
    # 파일별 처리
    check_file "$file"
done
```

**3. Hook 함수 계약 불일치 - 차단/경고가 정확하지 않을 수 있음**

**문제**: `check_naming_violations()`, `check_function_naming()` 등이 위반 발견 시 return 1을 하지 않아, 메인 로직의 `if ! check_...; then` 패턴과 맞지 않음.

**결과**: 차단/경고 카운트가 부정확하고, 재현성이 떨어져 Hook 신뢰도 저하.

**4. 임시 파일 공유 문제 - 정확한 카운팅 불가**

**문제**: `SUBSHELL_VIOLATIONS_FILE` 등이 전체 파일 루프에서 공유됨. 한 번이라도 내용이 생기면 이후 파일에서도 계속 카운트 증가.

```bash
# 잘못된 패턴 (현재)
for file in $STAGED_FILES; do
    check_subshell_sourcing "$file"  # 같은 임시 파일에 계속 append
done

if [ -s "$SUBSHELL_VIOLATIONS_FILE" ]; then
    violation_count++  # 부정확!
fi
```

**5. 문서 드리프트 - 참조 문서가 존재하지 않음**

```bash
# git/hooks/pre-commit:179
Reference: https://github.com/bwyoon/dotfiles/blob/main/para/archive/rca-knowledge/docs/analysis/2025-01-19-shell-function-propagation-issues.md
```

**문제**: 해당 경로에 문서가 없음. SSOT가 깨지고, 팀원이 Hook 메시지를 따라가도 근거 문서에 도달 못 함.

---

## 📋 Executive Summary

### ✅ 강점 (Strengths)

1. **우수한 2-Tier Hook 아키텍처**: User-level과 Project-level Hook의 명확한 분리 (SRP 준수)
2. **뛰어난 문서화**: HOOK_WORKFLOW.md가 실행 흐름을 상세히 설명
3. **포괄적인 검사 항목**: 6가지 보안 체크 + 6가지 코드 품질 체크
4. **플랫폼 호환성**: macOS, Linux, WSL 모두 지원
5. **실용적인 우회 메커니즘**: 환경변수와 --no-verify 옵션

### ⚠️ 개선 필요 영역 (Critical → High → Medium)

**Critical (즉시 조치)**:
1. ⛔ **Secret 파일 노출**: `.git-credentials`가 git에 tracked됨
2. ⛔ **NUL-safe 허점**: 문서 주장과 실제 구현 불일치
3. ⛔ **Hook 정확성**: 함수 return 값 불일치, 임시 파일 공유 문제

**High (신뢰도 회복)**:
4. **Postmortem 실수 미방지**: auto-sourcing 패턴을 Hook이 감지하지 못함
5. **Library purity 체크 부재**: auto-sourced 디렉토리에 실행 스크립트 유입 가능
6. **자동화 테스트 부재**: 회귀 테스트 없어 정확성 검증 불가

**Medium (SSOT/유지보수)**:
7. **설정 분산**: Hook 관련 설정이 여러 파일에 분산
8. **문서 드리프트**: 참조하는 문서 경로 오류
9. **성능 최적화 여지**: Project-level hook이 1-3초 소요

### 종합 평가

**CX (동료) 평가**: 30/50 (구현 정확성과 신뢰도 중점)
**Claude 평가**: 4.2/5 (설계와 개선 가능성 중점)

**통합 평가**: Hook 시스템의 **설계 방향은 우수**하나, **구현 정확성과 보안**에서 Critical한 문제들이 발견되어 즉시 조치가 필요함.

---

## 🔍 상세 분석

### 1. Single Source of Truth (SSOT) 원칙 준수

#### ✅ 잘 지켜진 부분

**1.1 Hook 로직의 단일 소스**

```
git/global-hooks/pre-commit     → User-level hook 구현 (단일 소스)
git/hooks/pre-commit            → Project-level hook 구현 (단일 소스)
~/.config/git/hooks/pre-commit  → Symlink (참조만)
.git/hooks/pre-commit           → Symlink (참조만)
```

**평가**: ⭐⭐⭐⭐⭐ (5/5)
- Hook 로직이 실제 구현 파일에만 존재
- Symlink를 통한 참조로 중복 제거
- 수정이 한 곳에서만 이루어지므로 일관성 보장

#### ⚠️ 개선이 필요한 부분

**1.2 설정 값의 분산 (CX 지적)**

**문제점** (Medium Priority):
- Hook 관련 설정이 3개 파일에 분산 (setup.sh, 2개 hook 파일)
- 매직 넘버 (10MB, 20줄) 하드코딩
- Secret 패턴, 디버그 패턴이 각 Hook에 개별 정의

**권장 개선안**:
```bash
# git/config/hook-config.sh (새 파일 제안)
# Hook 설정 중앙 집중화

# Thresholds
export HOOK_LARGE_FILE_LIMIT_MB=10
export HOOK_OUTPUT_MAX_LINES=20

# Security Patterns
export HOOK_SECRET_PATTERNS="-----BEGIN (OPENSSH |RSA )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}"
export HOOK_FORBIDDEN_FILES=".git-credentials|.env|id_rsa|*.pem|credentials.json"

# Code Quality Patterns
export HOOK_DEBUG_PATTERNS="pdb\.set_trace\(\)|binding\.pry|^[[:space:]]*debugger;|breakpoint\(\)"
```

**1.3 문서 드리프트 (CX 지적)**

**문제**: Hook이 참조하는 문서 경로가 실제로 존재하지 않음

```bash
# git/hooks/pre-commit:179
Reference: docs/analysis/2025-01-19-shell-function-propagation-issues.md
# ← 이 파일이 실제로 없음!
```

**영향**: 팀원이 Hook 메시지를 보고 참조 문서를 찾으려 해도 찾을 수 없음.

**권장 조치** (P2):
1. 실제 존재하는 문서로 경로 수정
2. 또는 해당 내용을 `git/doc/ANTI_PATTERNS.md`로 통합

---

### 2. SOLID 원칙 준수

#### ✅ Single Responsibility Principle (SRP)

**2.1 Hook 레벨별 명확한 책임**

| Hook | 책임 | Claude 평가 | CX 평가 |
|------|------|-------------|---------|
| **User-level** | 범용 보안 체크 | ⭐⭐⭐⭐⭐ | 6/10 (많은 로직이 한 파일에) |
| **Project-level** | 프로젝트 특화 검사 | ⭐⭐⭐⭐⭐ | 6/10 (체크/출력/집계 혼재) |

**CX 지적**: 각 hook 파일이 "체크 로직 + 출력 포맷 + 집계 + 리포팅"을 모두 포함해 SRP 위반 경향.

**개선 제안** (P2):
```bash
# 체크 로직을 모듈화
git/hooks/checks/
  ├── check-shebang.sh
  ├── check-naming.sh
  ├── check-subshell.sh
  └── ...

# 메인 Hook은 실행/리포팅만
git/hooks/pre-commit  # 파일 수집, 모듈 실행, 결과 집계
```

#### ⚠️ Open/Closed Principle (OCP)

**Claude 평가**: ⭐⭐⭐⭐⭐ (5/5)
**CX 평가**: 5/10

**CX 지적**: 새 체크 추가 시 "함수 추가 + 메인 루프 수정 + 변수 선언"이 필요해 확장이 쉽지 않음.

**개선 제안**: 체크를 플러그인처럼 자동 로드
```bash
# 모든 check-*.sh 파일을 자동 실행
for check_script in git/hooks/checks/check-*.sh; do
    source "$check_script"
    # 함수명 규칙: check_파일명()
done
```

---

### 3. 반복 실수 예방 (Prevention Mechanisms)

#### ✅ Hook이 현재 방지하는 실수들

1. **Shebang 일관성**: ✅ shell-common/bash/zsh별 강제
2. **Function Naming**: ✅ dash-case 차단
3. **Subshell Sourcing**: ⚠️ WARNING만 (일부 방지)
4. **Alias/Function 충돌**: ✅ BLOCKING (Postmortem 문제 일부 해결)
5. **Wrapper Function**: ⚠️ WARNING
6. **보안 (Secret 패턴)**: ⚠️ 패턴 기반만 (파일명은 미검사)

#### ⚠️ Hook이 방지하지 못하는 Critical 실수들

**3.1 Postmortem 실수: Auto-sourcing of Executable Scripts (HIGH Priority)**

**Postmortem 핵심 문제**:
```markdown
shell-common/tools/custom/에 있는 실행 스크립트들이
shell init에서 auto-source되어 무한루프/hang 발생
```

**현재 Hook의 한계**:
- `tools/custom/`에 있는 스크립트의 `main()` 자동 실행 패턴을 감지 못 함
- shell init 파일에서 `for f in tools/custom/*.sh; do source $f; done` 패턴을 차단 못 함

**권장 구현** (P1 - 동료 리뷰 수용):

```bash
# Check 1: tools/custom에 auto-executable 스크립트 방지
check_auto_executable_in_custom() {
    local file="$1"
    [[ "$file" != shell-common/tools/custom/*.sh ]] && return 0

    # main() 정의가 있고, EOF에서 호출되는지 확인
    if grep -q "^main()[[:space:]]*{" "$file" &&  \
       tail -20 "$file" | grep -qE "^main(\s+\"\$@\")?$"; then
        echo "$file: [BLOCKING] Auto-executable script in tools/custom/
  Postmortem: This pattern caused shell init hang.

  Fix: Either
    1. Move to tools/integrations/ (if needs auto-sourcing)
    2. Remove auto-execution: Don't call main() at EOF
    3. Add guard: [ \"\${BASH_SOURCE[0]}\" = \"\${0}\" ] && main

  Reference: docs/postmortem/postmortem-auto-sourcing-utility-scripts.md" >> "$AUTO_EXEC_FILE"
        return 1
    fi
    return 0
}

# Check 2: shell init에서 tools/custom auto-sourcing 방지
check_init_auto_sourcing() {
    local file="$1"
    [[ "$file" != bash/main.bash && "$file" != zsh/main.zsh ]] && return 0

    # tools/custom를 for loop으로 source하는 패턴 감지
    if grep -E "for.*tools/custom.*\.(source|\.)" "$file"; then
        echo "$file: [BLOCKING] Auto-sourcing tools/custom/ detected
  Postmortem: This is exactly what caused the hang incident.

  Fix: Only auto-source tools/integrations/

  Reference: docs/postmortem/postmortem-auto-sourcing-utility-scripts.md" >> "$AUTO_SOURCING_FILE"
        return 1
    fi
    return 0
}
```

**3.2 Library Purity 체크 부재 (HIGH Priority - CX 발견)**

**문제**: `shell-common/functions/`, `tools/integrations/` (auto-sourced 경로)에 실행 스크립트가 섞이면 shell init에서 즉시 실행되어 hang 발생 가능.

**권장 구현** (P1 - 동료 리뷰 수용):

```bash
check_library_purity() {
    local file="$1"

    # auto-sourced 경로만 검사
    [[ "$file" != shell-common/functions/*.sh && \
       "$file" != shell-common/tools/integrations/*.sh ]] && return 0

    # 금지 패턴들
    local violations=""

    # 1. EOF에서 main 호출
    if tail -20 "$file" | grep -qE "^(main|.*_main)(\s+|\$)"; then
        violations+="  - Calls main() at EOF (will execute on source)\n"
    fi

    # 2. 사용자 입력 대기 (guard 없이)
    if grep -qE "(read -r|select )" "$file" && \
       ! grep -qE "\[\[ \$- == \*i\* \]\]" "$file"; then
        violations+="  - Uses read/select without interactive guard\n"
    fi

    # 3. 설치/설정 명령어
    if grep -qE "(apt-get install|pip install|npm install)" "$file"; then
        violations+="  - Contains installation commands (belongs in tools/custom/)\n"
    fi

    if [ -n "$violations" ]; then
        echo "$file: [BLOCKING] Library purity violation (auto-sourced path)
$violations
  Risk: Will execute immediately on shell init, causing hang/unexpected behavior.

  Fix: Move to tools/custom/ (executable scripts only)

  Reference: docs/postmortem/postmortem-auto-sourcing-utility-scripts.md" >> "$PURITY_FILE"
        return 1
    fi

    return 0
}
```

**3.3 Secret 파일명 기반 차단 부재 (P0 - CX 발견)**

**현재**: 패턴 기반만 검사 (`-----BEGIN PRIVATE KEY-----`)
**문제**: `.git-credentials`, `.env`, `id_rsa` 같은 파일명은 미검사

**권장 구현** (P0):

```bash
# A. Secret 파일명 차단 (최우선)
FORBIDDEN_FILENAMES="\\.git-credentials|\\.env|\\.env\\..*|id_rsa|id_dsa|.*\\.pem|credentials\\.json"

check_forbidden_filename() {
    local file="$1"
    local basename=$(basename "$file")

    if echo "$basename" | grep -qE "$FORBIDDEN_FILENAMES"; then
        echo "❌ BLOCKING: Forbidden filename detected: $file
  This file likely contains secrets and should NEVER be committed.

  Action required:
    1. git rm --cached \"$file\"
    2. Add to .gitignore
    3. If already pushed, consider token rotation

  Common secret files: .git-credentials, .env, id_rsa, *.pem" >> "$SECRET_FILES"
        return 1
    fi
    return 0
}
```

---

### 4. 구현 정확성 개선 (CX Critical Findings)

#### 4.1 NUL-safe 처리 수정 (P1)

**현재 코드** (git/global-hooks/pre-commit:100):
```bash
# ❌ 잘못됨: 변수는 NUL 보존 불가
STAGED_FILES_NUL=$(git diff --cached --name-only -z --diff-filter=ACM)

# 이후 공백 있는 파일명에서 오작동 가능
```

**올바른 구현**:
```bash
# ✅ NUL-safe 스트리밍 처리
git diff --cached --name-only -z --diff-filter=ACM | while IFS= read -r -d '' file; do
    [ -z "$file" ] && continue

    # 각 검사 수행
    check_secrets "$file"
    check_conflicts "$file"
    check_whitespace "$file"
done
```

#### 4.2 Hook 함수 계약 통일 (P1)

**문제**: 일부 check 함수가 return 값을 일관되게 사용하지 않음.

**권장 표준**:
```bash
# 모든 check 함수는 다음 계약을 따름:
# - return 0: 검사 통과
# - return 1: 위반 발견
# - 위반 내용은 전역 임시 파일에 기록

check_example() {
    local file="$1"
    local violations=0

    # 검사 로직
    if [ 위반조건 ]; then
        echo "$file:$line: [LEVEL] Message" >> "$VIOLATIONS_FILE"
        violations=1
    fi

    return $violations  # 반드시 return!
}

# 메인 루프에서 일관되게 사용
if ! check_example "$file"; then
    ((violation_count++))
fi
```

#### 4.3 임시 파일 Per-File 격리 (P1)

**문제**: 임시 파일이 전체 루프에서 공유되어 카운트 부정확

**권장 수정**:
```bash
# 파일 루프 시작 전에 현재 라인 수 기록
before=$(wc -l < "$VIOLATIONS_FILE")

for file in $STAGED_FILES; do
    check_something "$file"
done

# 라인 수 차이로 정확한 카운트
after=$(wc -l < "$VIOLATIONS_FILE")
new_violations=$((after - before))
```

---

## 📊 종합 평가 (Combined Score)

### 점수 카드

| 평가 항목 | Claude 점수 | CX 점수 | 통합 평가 |
|-----------|------------|---------|----------|
| **SSOT 준수** | 4.5/5 | 30/50 | 설계는 우수, 구현 정확성 부족 |
| **SOLID 준수** | 4.8/5 | 30/50 | 방향은 좋으나 모듈화 부족 |
| **보안** | 4.0/5 | 20/50 | ⛔ Critical 문제 발견 |
| **반복 실수 예방** | 4.0/5 | 25/50 | Postmortem 미방지 |
| **문서화** | 5.0/5 | 35/50 | 우수하나 드리프트 있음 |
| **구현 정확성** | 4.7/5 | 25/50 | NUL-safe, 함수 계약 문제 |
| **테스트 가능성** | 3.0/5 | 20/50 | 자동화 테스트 전무 |

### 통합 결론

**설계 관점 (Claude)**: 4.2/5 ⭐⭐⭐⭐☆
**신뢰도 관점 (CX)**: 30/50 (60%)

**종합 판단**: Hook 시스템의 **아키텍처와 방향성은 매우 우수**하나, **Critical한 보안 문제**와 **구현 정확성 이슈**로 인해 현재 상태에서는 **신뢰도가 낮음**. P0/P1 이슈들을 해결하면 **우수한 예방 시스템**으로 발전 가능.

---

## 🎯 우선순위별 개선 권장 사항 (Combined)

### P0: 보안 크리티컬 (즉시 조치)

**1. `.git-credentials` 파일 처리** ✅ **완료**
- [x] `git rm --cached git/.git-credentials`
- [x] `.gitignore`에 추가
- [x] 토큰 폐기/재발급 (이미 노출되었다고 가정)
- 완료 시간: 2026-01-22

**2. Hook에 파일명 기반 Secret 차단 추가 (동료 우수 패턴 채용)** ✅ **완료**
- [x] 규칙 세분화: basename/path 분리된 SSOT 상수
  - FORBIDDEN_BASENAME_ERE: .git-credentials, credentials.json, id_rsa, id_dsa, id_ed25519, *.pem
  - ENV_BASENAME_BLOCK_ERE/ALLOW_ERE: .env* 기본 차단, 템플릿만 허용
  - FORBIDDEN_PATH_ERE: .aws/credentials, .aws/config (경로 기반)
- [x] 함수 캡슐화: `is_forbidden_staged_path()` 구현
  - 경로 기반 체크 → basename 체크 → env 허용리스트 (우선순위 명확)
  - 재사용 가능, 단위 테스트 가능
- [x] rename(R) 케이스 포함 (`--diff-filter=ACMR`)
- [x] 포괄적 테스트 완료 (15개 시나리오, 모두 통과)
- 완료 시간: 2026-01-22 (즉시 리팩토링, "내일은 오지 않는다")
- 동료 우수 패턴 채용:
  - ✅ 함수 캡슐화로 테스트/재사용 가능
  - ✅ basename/path 분리로 정확성 향상
  - ✅ P1 NUL-safe 이행 준비 완료
- 효과: Secret 파일 커밋 원천 차단, 유지보수성 우수

### P1: 신뢰도 회복 (1-2주 내)

**3. NUL-safe 처리 수정**
- [ ] 변수 대신 스트리밍 처리로 변경
- [ ] 공백 있는 파일명 테스트 케이스 추가
- [ ] 문서의 NUL-safe 주장 검증
- [ ] 작업 시간: 2-3시간
- [ ] 효과: 공백 파일명 오작동 방지

**4. Hook 함수 계약 통일 및 임시 파일 격리**
- [ ] 모든 check 함수 return 값 표준화
- [ ] Per-file 또는 라인 수 기반 정확한 카운팅
- [ ] 작업 시간: 3-4시간
- [ ] 효과: 차단/경고 정확성 향상

**5. Postmortem 실수 방지 Hook 추가**
- [ ] `check_auto_executable_in_custom()` 구현
- [ ] `check_init_auto_sourcing()` 구현
- [ ] 작업 시간: 2-3시간
- [ ] 효과: Postmortem 재발 방지

**6. Library Purity 체크 추가**
- [ ] `check_library_purity()` 구현
- [ ] auto-sourced 경로에 실행 스크립트 유입 차단
- [ ] 작업 시간: 2-3시간
- [ ] 효과: Shell init hang 재발 방지

**7. 자동화된 Hook 테스트 구축**
- [ ] `git/tests/test-hooks.sh` 작성
- [ ] Secret 탐지, NUL-safe, Function naming 등 테스트
- [ ] CI/CD 통합
- [ ] 작업 시간: 4-5시간
- [ ] 효과: 회귀 방지, 신뢰도 검증

### P2: SSOT/유지보수 (다음 스프린트)

**8. Hook 설정 중앙 집중화**
- [ ] `git/config/hook-config.sh` 생성
- [ ] 모든 매직 넘버, 패턴 통합
- [ ] 작업 시간: 3-4시간
- [ ] 효과: SSOT 원칙 완전 준수

**9. 문서 드리프트 수정**
- [ ] 존재하지 않는 참조 경로 수정
- [ ] 또는 `git/doc/ANTI_PATTERNS.md` 생성
- [ ] 작업 시간: 1-2시간
- [ ] 효과: 팀원이 참조 문서 접근 가능

**10. Check 로직 모듈화 (SRP/OCP 개선)**
- [ ] `git/hooks/checks/` 디렉토리 생성
- [ ] 각 체크를 독립 파일로 분리
- [ ] 메인 Hook은 실행/리포팅만
- [ ] 작업 시간: 6-8시간
- [ ] 효과: 유지보수성, 확장성 향상

### P3: 성능/UX (장기적 개선)

**11. 성능 최적화 (캐싱)**
- [ ] `~/.cache/git-hooks/` 기반 캐싱
- [ ] 작업 시간: 5-6시간
- [ ] 효과: Hook 실행 시간 70-80% 단축

**12. 에러 메시지 개선**
- [ ] 사용자 친화적 메시지로 변경
- [ ] 작업 시간: 2-3시간
- [ ] 효과: 사용자 경험 개선

---

## 💡 특별 제안

### 1. Hook 문서 자동 생성

**문제**: 문서(HOOK_WORKFLOW.md)와 코드의 드리프트 위험

**제안**:
```bash
# git/bin/generate-hook-docs
# Hook 코드의 주석에서 문서 자동 생성
# 예: # CHECK: Secret detection → 문서 섹션 자동 생성
```

### 2. Pre-commit Hook 자체의 Pre-commit Hook

**제안**: Hook 코드 변경 시 자동으로 검증
```bash
# Hook 스크립트가 변경되면:
# 1. Shellcheck 실행
# 2. Hook 테스트 실행
# 3. 문서 동기화 확인
```

---

## 📝 최종 결론

### 핵심 강점 (유지)
1. ✅ 2-Tier 아키텍처 - 명확한 책임 분리
2. ✅ 포괄적인 검사 항목 - 보안 + 코드 품질
3. ✅ 상세한 문서화 - 운영 가이드로 우수

### Critical 개선 사항 (즉시 조치)
1. ⛔ **Secret 파일 노출** - 즉시 제거 및 토큰 재발급
2. ⛔ **NUL-safe 허점** - 스트리밍 처리로 수정
3. ⛔ **Hook 정확성** - 함수 계약 통일, 임시 파일 격리

### 권장 조치 순서
1. **주말 긴급 작업** (2시간): P0 보안 이슈 해결
2. **1주차** (8-10시간): P1 신뢰도 회복 (NUL-safe, 정확성, Postmortem)
3. **2주차** (10-12시간): P1 자동화 테스트 + P2 SSOT
4. **이후 스프린트**: P2/P3 점진적 개선

**성공 기준**: P0/P1 완료 후 **전체 평가 60% → 85%** 달성 가능

---

**검토 완료**: 2026-01-22
**동료 리뷰 반영**: GPT-5.2 (Codex CLI) Critical Findings 통합
**다음 검토 권장일**: P0/P1 완료 후 즉시 재검토
