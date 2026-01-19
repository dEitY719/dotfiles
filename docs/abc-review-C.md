# Git pre-commit Hook 아키텍처: User-level + Project-level 통합 설계

## 문서 개요
- **작성 목적**: User 단위 공통 pre-commit과 프로젝트별 specific pre-commit을 동시에 활용하는 구조 설계
- **참고 문서**: `docs/abc-review-O.md` (동료 피드백)
- **현재 상태**: `git/hooks/pre-commit`을 프로젝트에 tracked로 관리 중

---

## 1. 동료 피드백 요약 및 검토

### 1.1 핵심 질문
> "git/hooks/pre-commit은 User 단위가 아닌 프로젝트 단위로 사용하는 개발자가 더 많나요?"

**동료의 답변 (abc-review-O.md 기반)**:
- ✅ **프로젝트 단위가 더 일반적**: 팀 일관성, 재현성, 공유 가능성 때문
- ⚠️ **하지만 `.git/hooks`는 버전 관리 안 됨**: 그래서 프로젝트 표준으로는 부족
- 💡 **해결책**: `core.hooksPath` + tracked hook 디렉토리 (예: `.githooks/`, `git/hooks/`)

### 1.2 User 단위 전역 hook의 필요성
- **개인 생산성 도구**: 개인 선호 포매터, 빠른 검증
- **공통 체크**: 여러 프로젝트에서 공통으로 적용하고 싶은 가벼운 검증

**결론**: 프로젝트 단위가 주류지만, User 단위 공통 hook도 유용함 → **둘 다 지원하는 hybrid 구조 필요**

---

## 2. 설계 목표 및 제약사항

### 2.1 설계 목표
1. **User-level 공통 hook**: 모든 git 레포에서 자동 실행되는 가벼운 검증
2. **Project-level specific hook**: 프로젝트별 상세 검증 (버전 관리 가능)
3. **순차 실행 및 실패 전파**: 둘 중 하나라도 실패하면 commit 차단
4. **하위 호환성**: 기존 dotfiles 레포의 `git/hooks/pre-commit` 구조 유지

### 2.2 기술적 제약사항
- Git의 `core.hooksPath`는 **단일 디렉토리만** 지정 가능
- `.git/hooks/`는 버전 관리되지 않음 (팀 공유 불가)
- Wrapper hook이 자기 자신을 재귀 호출하면 안 됨

---

## 3. 아키텍처 설계

### 3.1 전체 구조도

```
┌─────────────────────────────────────────────────────────────┐
│ Git Commit Attempt                                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 v
┌─────────────────────────────────────────────────────────────┐
│ ~/.config/git/hooks/pre-commit (전역 wrapper hook)          │
│ - core.hooksPath로 설정됨                                    │
│ - 모든 git 레포에서 실행                                     │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ├──> [Phase 1] User-level 공통 검증 실행
                 │    (가벼운 체크만: trailing space, TODO 등)
                 │    ✗ 실패 시 → commit 차단
                 │
                 └──> [Phase 2] Project-level hook 위임
                      (레포 내 .githooks/pre-commit 또는
                       git/hooks/pre-commit 실행)
                      ✗ 실패 시 → commit 차단

                 ✓ 모두 성공 → commit 허용
```

### 3.2 디렉토리 구조

```bash
# User-level (전역)
~/.config/git/hooks/
  └── pre-commit                    # Wrapper hook (모든 레포에서 실행)

# Project-level (이 dotfiles 레포 예시)
~/dotfiles/
  ├── git/hooks/pre-commit          # 현재 프로젝트의 hook (tracked)
  ├── .git/hooks/                   # (비어있음, wrapper가 대신 처리)
  └── git/setup.sh                  # 설치 스크립트 (수정 필요 없음)

# 다른 프로젝트 예시
~/my-project/
  ├── .githooks/pre-commit          # 표준 위치
  └── .git/hooks/                   # (비어있음)
```

---

## 4. 구현 계획

### 4.1 Phase 1: 전역 wrapper hook 설치

#### 4.1.1 디렉토리 생성 및 Git 설정
```bash
# ~/.config/git/hooks/ 생성
mkdir -p "$HOME/.config/git/hooks"

# Git이 이 디렉토리를 hook 위치로 사용하도록 설정
git config --global core.hooksPath "$HOME/.config/git/hooks"
```

**효과**: 이후 모든 git 레포에서 `~/.config/git/hooks/`의 hook 실행

#### 4.1.2 Wrapper hook 작성
파일: `~/.config/git/hooks/pre-commit`

```bash
#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Global pre-commit hook wrapper
# Purpose: Run user-level common checks + delegate to project hook
# ═══════════════════════════════════════════════════════════════

# Color codes for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ───────────────────────────────────────────────────────────────
# Phase 1: User-level common checks (lightweight only)
# ───────────────────────────────────────────────────────────────

echo -e "${YELLOW}[Global pre-commit] Running user-level checks...${NC}"

# Example: Check for trailing whitespace in staged files
if git diff --cached --check --color 2>&1 | grep -q 'trailing whitespace'; then
    echo -e "${RED}✗ Found trailing whitespace in staged files${NC}"
    git diff --cached --check --color
    exit 1
fi

# Example: Warn about TODO/FIXME in staged files (non-blocking)
staged_files=$(git diff --cached --name-only)
if [ -n "$staged_files" ] && echo "$staged_files" | xargs grep -Hn "TODO\|FIXME" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Warning: Found TODO/FIXME in staged files${NC}"
    # Don't block commit for this
fi

echo -e "${GREEN}✓ User-level checks passed${NC}"

# ───────────────────────────────────────────────────────────────
# Phase 2: Delegate to project-level hook if exists
# ───────────────────────────────────────────────────────────────

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [ -z "$repo_root" ]; then
    # Not in a git repo (shouldn't happen, but defensive)
    exit 0
fi

# Search for project-level hook in standard locations
project_hook=""
if [ -x "$repo_root/.githooks/pre-commit" ]; then
    project_hook="$repo_root/.githooks/pre-commit"
elif [ -x "$repo_root/git/hooks/pre-commit" ]; then
    project_hook="$repo_root/git/hooks/pre-commit"
fi

if [ -n "$project_hook" ]; then
    echo -e "${YELLOW}[Global pre-commit] Delegating to project hook: $project_hook${NC}"

    # Execute project hook and propagate exit code
    if ! "$project_hook"; then
        echo -e "${RED}✗ Project-level pre-commit hook failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Project-level checks passed${NC}"
else
    echo -e "${YELLOW}[Global pre-commit] No project-level hook found, skipping${NC}"
fi

# All checks passed
exit 0
```

**권한 부여**:
```bash
chmod +x "$HOME/.config/git/hooks/pre-commit"
```

### 4.2 Phase 2: 기존 dotfiles 레포 적응

#### 4.2.1 현재 상태 분석
- ✅ `git/hooks/pre-commit` 존재 (comprehensive validation)
- ✅ `git/setup.sh`가 `.git/hooks/pre-commit`으로 심볼릭 링크 생성
- ⚠️ Wrapper hook 도입 후 심볼릭 링크 불필요 (wrapper가 직접 호출)

#### 4.2.2 변경 사항
**변경 불필요**: 현재 구조 유지 가능
- Wrapper가 `$repo_root/git/hooks/pre-commit` 경로 지원
- 기존 심볼릭 링크는 무시됨 (wrapper가 우선)

**선택적 정리** (나중에):
```bash
# git/setup.sh에서 심볼릭 링크 생성 로직 제거 가능
# (하지만 하위 호환성 위해 남겨둬도 무방)
```

### 4.3 Phase 3: 다른 프로젝트에 적용

#### 신규 프로젝트 설정 예시
```bash
# 표준 위치 사용
mkdir -p .githooks
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Project-specific validation here
echo "Running project checks..."
# pytest, ruff, etc.
EOF

chmod +x .githooks/pre-commit
git add .githooks/pre-commit
```

---

## 5. 장단점 분석

### 5.1 Wrapper 패턴의 장점
1. ✅ **User + Project 동시 지원**: 한 번의 commit에서 두 단계 검증
2. ✅ **버전 관리 가능**: 프로젝트 hook은 레포에 포함되어 팀 공유
3. ✅ **유연성**: 각 레포가 hook 유무를 자유롭게 결정
4. ✅ **하위 호환성**: 기존 구조 (예: `git/hooks/`) 그대로 지원

### 5.2 주의사항
1. ⚠️ **재귀 호출 방지**: Wrapper가 project hook 찾을 때 자기 자신 제외
2. ⚠️ **성능**: User-level은 가벼운 체크만 (무거운 건 project로)
3. ⚠️ **디버깅**: 실패 시 어느 단계에서 실패했는지 명확히 표시 필요

---

## 6. 실행 흐름 예시

### 6.1 시나리오: dotfiles 레포에서 commit
```bash
$ git commit -m "Update function"

[Global pre-commit] Running user-level checks...
✓ User-level checks passed

[Global pre-commit] Delegating to project hook: /home/user/dotfiles/git/hooks/pre-commit

Pre-commit validation (staged files only)
✓ All checks passed!

✓ Project-level checks passed

[main abc1234] Update function
```

### 6.2 시나리오: 프로젝트 hook 없는 레포
```bash
$ git commit -m "Simple change"

[Global pre-commit] Running user-level checks...
✓ User-level checks passed

[Global pre-commit] No project-level hook found, skipping

[main def5678] Simple change
```

### 6.3 시나리오: 실패 케이스
```bash
$ git commit -m "Bad code"

[Global pre-commit] Running user-level checks...
✓ User-level checks passed

[Global pre-commit] Delegating to project hook: /home/user/project/.githooks/pre-commit

✗ Found 3 BLOCKING violation(s)
[BLOCKING] Function naming violations (1):
  ...

✗ Project-level pre-commit hook failed
# Commit 차단됨
```

---

## 7. 구현 우선순위

### 7.1 필수 구현 (Minimum Viable Product)
1. ✅ Phase 1: Wrapper hook 작성 및 전역 설치
2. ✅ Phase 2: 기존 dotfiles와 통합 테스트
3. ✅ 문서화: README에 설치 가이드 추가

### 7.2 선택적 개선
1. 🔄 `git/setup.sh` 리팩토링 (심볼릭 링크 로직 제거)
2. 🔄 User-level 공통 체크 확장 (팀 협의 필요)
3. 🔄 다른 hook 타입 지원 (pre-push, commit-msg 등)

---

## 8. 의사결정 포인트

### 8.1 User-level 공통 체크에 무엇을 넣을까?
**추천**: 가볍고 범용적인 것만
- ✅ Trailing whitespace
- ✅ Merge conflict markers (`<<<<<<<`, `>>>>>>>`)
- ✅ 대용량 파일 체크 (>10MB)
- ❌ 언어별 linting (프로젝트마다 다름)
- ❌ 테스트 실행 (너무 무거움)

**이유**: User-level은 "최소 공통 분모", 상세한 건 project-level로

### 8.2 기존 심볼릭 링크를 제거할까?
**추천**: 당분간 유지
- 하위 호환성 보장 (wrapper 설치 안 한 환경 대비)
- Wrapper와 충돌 없음 (wrapper가 직접 호출하므로)
- 나중에 필요시 제거 가능

---

## 9. 검토 질문 (동료와 논의 필요)

### 9.1 기술적 질문
- [ ] User-level 공통 체크에 어떤 검증을 넣을지?
- [ ] 다른 프로젝트에도 `.githooks/` 표준 적용할지?
- [ ] `pre-push`, `commit-msg` 등 다른 hook도 통합할지?

### 9.2 운영 질문
- [ ] 팀원들에게 wrapper 설치를 강제할지 권장할지?
- [ ] 설치 자동화 스크립트를 만들지? (예: `install-global-hooks.sh`)
- [ ] 기존 레포들을 일괄 마이그레이션할지?

---

## 10. Claude의 의견 및 추가 제안

### 10.1 설계 평가
✅ **동료의 피드백이 매우 정확함**: Wrapper 패턴이 Git hook의 단일 디렉토리 제약을 우회하는 표준 접근법

✅ **현재 dotfiles 구조와 잘 호환됨**: `git/hooks/` 경로 지원으로 기존 코드 변경 최소화

⚠️ **주의점**: User-level에 너무 많이 넣으면 "모든 레포가 느려지는" 부작용

### 10.2 추가 제안

#### 제안 1: Hook 설치 자동화
`dotfiles/git/install-global-hooks.sh` 추가:
```bash
#!/usr/bin/env bash
# Automated setup for global + project hooks

# 1. Create global hook directory
mkdir -p "$HOME/.config/git/hooks"

# 2. Copy wrapper hook from dotfiles
cp "$(dirname "$0")/hooks/global-pre-commit-wrapper.sh" \
   "$HOME/.config/git/hooks/pre-commit"
chmod +x "$HOME/.config/git/hooks/pre-commit"

# 3. Configure Git
git config --global core.hooksPath "$HOME/.config/git/hooks"

echo "✓ Global hooks installed successfully"
```

#### 제안 2: 디버그 모드
Wrapper에 환경변수 지원:
```bash
# 디버그 출력 활성화
export GIT_HOOKS_DEBUG=1

# Hook 실행 스킵 (긴급 상황용)
export GIT_HOOKS_SKIP=1
```

#### 제안 3: Performance 측정
각 단계별 실행 시간 표시:
```bash
# Wrapper에 추가
start_time=$(date +%s%N)
# ... (검증 로직)
end_time=$(date +%s%N)
elapsed=$(( (end_time - start_time) / 1000000 ))
echo "[Timing] User-level checks: ${elapsed}ms"
```

---

## 11. 다음 단계

### 11.1 구현 전 검토 사항
- [ ] 동료와 설계 리뷰 (이 문서 기반)
- [ ] User-level 공통 체크 범위 합의
- [ ] 구현 우선순위 결정

### 11.2 구현 후 검증 사항
- [ ] dotfiles 레포에서 기존 hook 정상 작동 확인
- [ ] 다른 레포에서 wrapper만 동작하는지 확인
- [ ] 실패 시 적절한 에러 메시지 출력 확인
- [ ] 성능 영향 측정 (commit 체감 시간)

---

## 12. 결론

**핵심 답변**:
1. ✅ **가능합니다**: Wrapper 패턴으로 User + Project 동시 지원
2. 🎯 **추천 방식**: 전역 `core.hooksPath` + tracked `.githooks/` (또는 `git/hooks/`)
3. 🔄 **기존 코드 변경 최소**: dotfiles의 현재 구조와 호환

**권장 사항**:
- User-level: 가벼운 공통 체크만
- Project-level: 언어/프레임워크별 상세 검증
- 단계적 도입: dotfiles 먼저, 다른 프로젝트는 점진적으로

**리스크**:
- 낮음: 기존 구조 유지하면서 점진적 확장 가능
- 롤백 용이: `git config --global --unset core.hooksPath`로 원복

---

**문서 작성**: Claude (2026-01-20)
**기반 자료**: `docs/abc-review-O.md` (동료 O의 분석)
**참고 코드**: `git/hooks/pre-commit` (현재 프로젝트 hook)
