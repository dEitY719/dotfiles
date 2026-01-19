# Git Pre-commit Hook Workflow

> **문서 목적**: User-level과 Project-level Hook의 실행 순서 및 동작 방식을 명확하게 이해하기 위한 참고 가이드

**최종 수정**: 2026-01-20
**버전**: 1.0

---

## 📋 목차

1. [개요](#1-개요)
2. [Hook 실행 흐름](#2-hook-실행-흐름)
3. [PHASE 1: User-level Hook](#3-phase-1-user-level-hook)
4. [PHASE 2: Project-level Hook](#4-phase-2-project-level-hook)
5. [실제 예제: bat_help.sh 수정](#5-실제-예제-bat_helpsh-수정)
6. [테스트 방법](#6-테스트-방법)
7. [FAQ](#7-faq)

---

## 1. 개요

### 🎯 핵심 개념

이 프로젝트는 **2-tier Hook 아키텍처**를 사용합니다:

| 계층 | 용도 | 범위 |
|------|------|------|
| **User-level** | 모든 프로젝트에 공통 적용되는 보안 체크 | 전역 (모든 git repo) |
| **Project-level** | 이 dotfiles 프로젝트에만 특화된 검사 | 로컬 (이 프로젝트만) |

### 🔗 연결 구조

```
Git's core.hooksPath 설정
    ↓
~/.config/git/hooks/pre-commit (User-level Hook)
    ↓
[PHASE 1: Global 안전 체크]
    ↓
git/hooks/pre-commit (Project-level Hook)
    ↓
[PHASE 2: 프로젝트 특화 검사]
    ↓
✅ Commit 완료 or ❌ Commit 차단
```

---

## 2. Hook 실행 흐름

### 📊 전체 흐름도

```
┌─────────────────────────────────────────────────────────────────┐
│ $ git commit -m "message"                                       │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 v
        ┌────────────────────┐
        │ Git이 hook 실행    │
        │ (core.hooksPath)   │
        └────────┬───────────┘
                 │
                 v
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃  ~/.config/git/hooks/       ┃
    ┃     pre-commit              ┃
    ┃  (User-level Hook)          ┃
    ┗━━━━━━━━━━━━━┬━━━━━━━━━━━━━┛
                 │
                 v
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃ PHASE 1: User-level Checks           ┃
    ┃ - Secrets/Keys Detection             ┃
    ┃ - Conflict Markers                   ┃
    ┃ - Trailing Whitespace                ┃
    ┃ - Debug Code                         ┃
    ┃ - Large Files (>10MB)                ┃
    ┃ - Email Identity                     ┃
    ┃ 실행 시간: ~150ms                    ┃
    ┗━━━━━━━━━━━━━━┬━━━━━━━━━━━━━━━━━━━┛
                 │
           [통과?]
          ╱      ╲
        YES      NO
         │        │
         │        └─→ ❌ Commit 차단 (EXIT 1)
         │
         v
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃ PHASE 2: Project-level Delegation    ┃
    ┃ (git/hooks/pre-commit 찾기 및 실행)  ┃
    ┗━━━━━━━━━━━━━━┬━━━━━━━━━━━━━━━━━━━┛
                 │
                 v
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃ ~/dotfiles/git/hooks/pre-commit      ┃
    ┃ (Project-level Hook)                 ┃
    ┗━━━━━━━━━━━━━━┬━━━━━━━━━━━━━━━━━━━┛
                 │
                 v
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃ PHASE 2: Project-level Checks        ┃
    ┃ - Shebang 검사                       ┃
    ┃ - Function Naming (snake_case)       ┃
    ┃ - UX Library 사용 검사               ┃
    ┃ - Subshell Sourcing Anti-pattern     ┃
    ┃ - Alias/Function 충돌                ┃
    ┃ - Wrapper Function Anti-pattern      ┃
    ┃ 실행 시간: ~1-3초                    ┃
    ┗━━━━━━━━━━━━━━┬━━━━━━━━━━━━━━━━━━━┛
                 │
           [통과?]
          ╱      ╲
        YES      NO
         │        │
         v        └─→ ❌ Commit 차단 (EXIT 1)
         │
         v
    ┌──────────────────────┐
    │ ✅ Commit 완료!      │
    │ Changes committed    │
    └──────────────────────┘
```

### ⏱️ 총 실행 시간

```
PHASE 1 (User-level)     ~150ms  (빠름!)
PHASE 2 (Project-level)  ~1-3s   (파일 수에 따라 다름)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
총 시간                  ~1-3.2초
```

---

## 3. PHASE 1: User-level Hook

### 📍 위치

```
~/.config/git/hooks/pre-commit
```

### 🔑 특징

- **모든 git 프로젝트에서 실행** (전역)
- **빠르고 가벼움** (~150ms)
- **범용적인 보안 체크**

### 🔍 검사 항목

#### A. Secret/Key Detection
```bash
# 감지 패턴
- -----BEGIN OPENSSH PRIVATE KEY-----
- -----BEGIN RSA PRIVATE KEY-----
- AKIA[0-9A-Z]{16}  (AWS Access Key)
```
**목적**: Private key/credential이 실수로 커밋되는 것 방지

#### B. Conflict Markers
```bash
# 감지 패턴
<<<<<<<
=======
>>>>>>>
```
**목적**: 병합 충돌을 완료하지 않은 상태에서 커밋 차단

#### C. Trailing Whitespace
```bash
# 감지: 라인 끝의 불필요한 공백
echo "hello   "  # ← trailing space
```
**목적**: 코드 스타일 일관성

#### D. Debug Code
```bash
# 감지 패턴 (명시적 디버거만)
pdb.set_trace()        # Python
binding.pry            # Ruby
debugger;              # JavaScript
breakpoint()           # Python 3.7+
```
**목적**: 개발용 디버거 코드가 프로덕션에 들어가는 것 방지
**참고**: `console.log` 같은 정상 로깅은 차단하지 않음

#### E. Large Files (>10MB)
```bash
# 감지: Index blob 크기 > 10MB
git cat-file -s :filename
```
**목적**: Git 리포지토리 크기 증가 방지, Git LFS 권장

#### F. Email Identity Check
```bash
# 휴리스틱: 디렉토리 경로 vs Email 도메인 체크
/work/ or /corp/  +  gmail.com? → ⚠️ 경고
/personal/        +  company.com? → ⚠️ 경고
```
**목적**: 실수로 잘못된 email로 커밋하는 것 방지

### 💥 실패 시나리오

```
❌ Secret 감지
❌ Conflict marker 있음
❌ Trailing whitespace
❌ Large file (>10MB)

→ 모두 Commit 차단!
```

### ⚠️ 경고만 표시 (차단 안 함)

```
⚠️ Debug code detected (consider removing)
⚠️ WARNING: Committing to WORK directory with PERSONAL email

→ Commit 진행 가능 (경고만 표시)
```

---

## 4. PHASE 2: Project-level Hook

### 📍 위치

```
~/dotfiles/git/hooks/pre-commit
```

### 🔑 특징

- **이 dotfiles 프로젝트에만 실행** (로컬)
- **상대적으로 무거움** (~1-3초)
- **프로젝트 특화 검사**

### 🔍 검사 항목

#### 1. Shebang 검사
```bash
# 디렉토리별 Shebang 규칙 검증
shell-common/  → #!/bin/sh
bash/          → #!/bin/bash
zsh/           → #!/bin/zsh
```

#### 2. Function Naming
```bash
# snake_case만 허용
✅ my_function()      OK
❌ my-function()      ERROR
❌ myFunction()       ERROR
```

#### 3. UX Library 사용
```bash
# UX library 함수가 있으면 체크
✓ ux_header, ux_section, ux_bullet 사용
✗ Raw echo 사용
```

#### 4. Anti-patterns 감지

**Subshell Sourcing** (함수/alias 전파 안 됨)
```bash
❌ source_var=$(. file.sh)  # 위험!
✅ . file.sh               # OK
```

**Alias/Function 충돌** (zsh 파싱 에러)
```bash
❌ alias cmd='...'
   cmd() { ... }
✅ alias cmd='...'
   cmd_impl() { ... }
```

**Wrapper Function** (불필요한 래퍼)
```bash
❌ wrapper() { other_func "$@" }  # 불필요한 래퍼
✅ alias wrapper='other_func'     # alias 사용
   또는 제거
```

### 💥 실패 시나리오

```
❌ Shebang 오류
❌ Function naming (dash-case)
❌ Alias/Function 충돌 (BLOCKING)

→ Commit 차단!
```

### ⚠️ 경고만 표시 (차단 안 함)

```
⚠️ Subshell sourcing anti-pattern
⚠️ Wrapper function anti-pattern
⚠️ UX Library suggestions

→ Commit 진행 가능 (경고만 표시)
```

---

## 5. 실제 예제: bat_help.sh 수정

### 🎬 시나리오

```bash
# 파일 수정
vim shell-common/functions/bat_help.sh

# 스테이징
git add shell-common/functions/bat_help.sh

# 커밋 시도
git commit -m "Update bat_help function"
```

### 📋 실행 순서

#### PHASE 1: User-level Hook 실행

```
[Global Hook] Running safety checks...

[Debug] Found 1 staged file(s)
[Debug] Checking for secrets/keys...
✓ No secrets detected

[Debug] Checking for conflict markers...
✓ No conflict markers

[Debug] Checking for trailing whitespace...
✓ No trailing whitespace

[Debug] Checking for debug code...
✓ No debug code

[Debug] Checking for large files...
✓ All files < 10MB

[Debug] Checking email identity...
✓ Email matches (personal directory)

✓ All global checks passed
```

#### PHASE 2: Project-level Hook 실행

```
[Global Hook] Delegating to project hook: /home/bwyoon/dotfiles/git/hooks/pre-commit

Pre-commit validation (staged files only)

[Debug] Checking shebang...
shell-common/functions/bat_help.sh:1: #!/bin/sh ✓ OK

[Debug] Checking function naming...
Function 'bat_help': snake_case ✓ OK

[Debug] Checking UX library usage...
✓ Using ux_header, ux_section ✓ OK

[Debug] Checking anti-patterns...
- Subshell sourcing: ✓ OK
- Alias/Function conflicts: ✓ OK
- Wrapper functions: ✓ OK

✓ All checks passed!

[main abc1234] Update bat_help function
 1 file changed, 10 insertions(+)
```

### ✅ 결과

**Commit 성공!**

---

## 6. 테스트 방법

### 🧪 테스트 1: 디버그 모드로 Hook 실행 확인

```bash
# 파일 수정
echo "test" >> shell-common/functions/bat_help.sh

# 스테이징
git add shell-common/functions/bat_help.sh

# 디버그 모드로 커밋
GIT_HOOKS_DEBUG=1 git commit -m "test"

# 출력:
# [Debug] Not in a git repository, exiting
# [Debug] Found 1 staged file(s)
# [Debug] Checking for secrets/keys...
# [Debug] Checking for conflict markers...
# ...
# [Debug] Searching for project-level hooks...
# [Debug] Checking: /home/bwyoon/dotfiles/.githooks/pre-commit
# [Debug] Checking: /home/bwyoon/dotfiles/git/hooks/pre-commit
# [Debug] Found executable hook: /home/bwyoon/dotfiles/git/hooks/pre-commit
```

### 🧪 테스트 2: 전역 체크만 실행

```bash
# 전역 체크 스킵 (긴급 상황용)
GIT_HOOKS_SKIP_GLOBAL=1 git commit -m "emergency"

# 결과: PHASE 1 스킵, PHASE 2만 실행
```

### 🧪 테스트 3: 실제 오류 발생시키기

```bash
# Trailing whitespace 추가
echo "test  " >> shell-common/functions/bat_help.sh
git add shell-common/functions/bat_help.sh
git commit -m "test"

# 결과:
# ❌ BLOCKING: Trailing whitespace detected!
# shell-common/functions/bat_help.sh:50: trailing whitespace
# Commit blocked by global safety checks
```

### 🧪 테스트 4: 공백 있는 파일명

```bash
# 공백 있는 파일 생성
touch "my important file.sh"
echo "pdb.set_trace()" >> "my important file.sh"
git add "my important file.sh"
git commit -m "test"

# 결과: NUL-safe 처리로 정확하게 감지됨
```

### 🧪 테스트 5: 부분 스테이징 (git add -p)

```bash
# 파일에 여러 변경사항 만들기
vim shell-common/functions/bat_help.sh

# 일부만 스테이징
git add -p shell-common/functions/bat_help.sh

# 커밋
git commit -m "test"

# 결과: Index 기준 검사로 정확하게 작동
```

---

## 7. FAQ

### Q1: Hook이 실행되지 않는 경우?

**A**: 전역 hook 설치 확인:

```bash
# 확인 1: core.hooksPath 설정 확인
git config --global core.hooksPath
# 출력: /home/username/.config/git/hooks

# 확인 2: Hook 파일 존재 확인
ls -l ~/.config/git/hooks/pre-commit
# 출력: lrwxr-xr-x ... -> /path/to/dotfiles/git/global-hooks/pre-commit

# 확인 3: 실행 권한 확인
chmod +x ~/.config/git/hooks/pre-commit

# 확인 4: setup.sh 다시 실행
cd ~/dotfiles
./git/setup.sh
```

### Q2: Hook을 무시하고 강제로 커밋하려면?

**A**: Git의 표준 옵션 사용:

```bash
# 방법 1: --no-verify 옵션 (권장 안 함)
git commit --no-verify -m "force commit"

# 방법 2: 환경변수로 전역만 스킵
GIT_HOOKS_SKIP_GLOBAL=1 git commit -m "skip global checks"
```

### Q3: Hook 에러 메시지가 이해가 안 갈 때?

**A**: 디버그 모드 사용:

```bash
# 디버그 정보 함께 출력
GIT_HOOKS_DEBUG=1 git commit -m "message"
```

### Q4: Trailing whitespace를 자동으로 제거할 수 있나?

**A**: Git 자동 수정 도구 사용:

```bash
# 스테이징된 파일에서 trailing space 제거
git diff --cached --check | sed 's/^\([^:]*\):.*/\1/' | sort -u | \
  while read file; do
    sed -i 's/[[:space:]]*$//' "$file"
  done

# 다시 스테이징
git add .

# 커밋
git commit -m "Remove trailing whitespace"
```

### Q5: 다른 프로젝트에도 Project-level hook을 추가할 수 있나?

**A**: 네, 표준 위치 사용:

```bash
# 프로젝트 디렉토리에서
mkdir -p .githooks

cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# 이 프로젝트 특화 검사
echo "Running project-specific checks..."

# pytest, eslint, 등등
EOF

chmod +x .githooks/pre-commit

# Git에 커밋
git add .githooks/pre-commit
git commit -m "Add project pre-commit hook"
```

### Q6: Hook 실행 시간을 측정하려면?

**A**: 시간 측정 명령어 사용:

```bash
# 전체 시간 측정
time git commit -m "message"

# 결과:
# real    0m1.234s
# user    0m0.950s
# sys     0m0.284s

# 개별 PHASE 측정 (디버그 모드)
GIT_HOOKS_DEBUG=1 git commit -m "message" 2>&1 | grep -E "Timing|seconds"
```

### Q7: macOS에서 Hook이 작동하나?

**A**: 네, 완벽 지원:

```bash
# macOS 호환성 확인
# - readlink -f 미지원 → fallback으로 처리됨
# - 모든 체크 정상 작동
# - 테스트됨 ✓

# 확인:
GIT_HOOKS_DEBUG=1 git commit -m "test"
# [Debug] ... (모든 체크 정상)
```

### Q8: 개발 환경에서는 일부 체크를 비활성화할 수 있나?

**A**: 환경변수 사용:

```bash
# 전역 체크 스킵
export GIT_HOOKS_SKIP_GLOBAL=1

# 이후 모든 커밋에서 전역 체크 스킵
git commit -m "message"  # PHASE 2만 실행

# 원복
unset GIT_HOOKS_SKIP_GLOBAL
```

### Q9: CI/CD에서 Hook을 실행해야 하나?

**A**: 권장하지 않음:

```bash
# CI에서는 pre-commit hook 스킵
git commit --no-verify -m "CI auto-commit"

# 대신 CI pipeline에서 검사 실행
# - tox -e lint
# - pytest
# - shellcheck
# - 등등
```

### Q10: 여러 파일을 한번에 커밋할 때 성능이 나빠진다면?

**A**: PHASE 1은 빠르므로, PHASE 2 최적화 필요:

```bash
# 현재 성능 확인
time git commit -m "message"

# 문제가 있다면 project hook 검토:
# git/hooks/pre-commit 내용 확인

# 필요시 검사 항목 선별적 실행
```

---

## 📚 참고 문서

- `git/global-hooks/pre-commit` - User-level hook 구현
- `git/hooks/pre-commit` - Project-level hook 구현
- `docs/abc-review-code-quality-improvements.md` - 코드 품질 개선 사항
- `docs/abc-review-G.md` - Gemini 코드 리뷰
- `docs/abc-review-CX.md` - CX 코드 리뷰

---

## 🎯 요약

| 항목 | 내용 |
|------|------|
| **User-level Hook** | `~/.config/git/hooks/pre-commit` - 모든 프로젝트 공통 (~150ms) |
| **Project-level Hook** | `git/hooks/pre-commit` - dotfiles 특화 (~1-3s) |
| **실행 순서** | 1️⃣ User-level → 2️⃣ Project-level |
| **bat_help.sh 수정 시** | ✅ 둘 다 실행됨 |
| **모두 통과해야** | Commit 완료 가능 |
| **디버그 모드** | `GIT_HOOKS_DEBUG=1` |
| **긴급 스킵** | `GIT_HOOKS_SKIP_GLOBAL=1` |
| **총 시간** | ~1-3.2초 |

---

**문서 작성**: Claude (2026-01-20)
**마지막 수정**: 2026-01-20
