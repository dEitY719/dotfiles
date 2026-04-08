---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - creates isolated git worktrees with smart directory selection and safety verification
---

# Git Worktree 사용하기

## 개요

Git worktree는 동일한 저장소를 공유하는 격리된 작업공간을 생성하여, 브랜치 전환 없이 여러 브랜치에서 동시에 작업할 수 있게 합니다.

**핵심 원칙:** 체계적인 디렉터리 선택 + 안전성 검증 = 신뢰할 수 있는 격리.

**시작 시 선언:** "using-git-worktrees 스킬을 사용하여 격리된 작업공간을 설정합니다."

## 디렉터리 선택 프로세스

다음 우선순위 순서를 따릅니다:

### 1. 기존 디렉터리 확인

```bash
# 우선순위 순서로 확인
ls -d .worktrees 2>/dev/null     # 선호 (숨김)
ls -d worktrees 2>/dev/null      # 대안
```

**발견된 경우:** 해당 디렉터리를 사용합니다. 둘 다 존재하면 `.worktrees`가 우선합니다.

### 2. CLAUDE.md 확인

```bash
grep -i "worktree.*director" CLAUDE.md 2>/dev/null
```

**설정이 지정된 경우:** 묻지 않고 해당 설정을 사용합니다.

### 3. 사용자에게 질문

디렉터리가 없고 CLAUDE.md에 설정도 없는 경우:

```
worktree 디렉터리를 찾을 수 없습니다. 어디에 worktree를 생성할까요?

1. .worktrees/ (프로젝트 로컬, 숨김)
2. ~/.config/superpowers/worktrees/<project-name>/ (글로벌 위치)

어느 것을 선호하시나요?
```

## 안전성 검증

### 프로젝트 로컬 디렉터리의 경우 (.worktrees 또는 worktrees)

**worktree 생성 전 디렉터리가 ignore 처리되었는지 반드시 확인해야 합니다:**

```bash
# 디렉터리가 ignore 처리되었는지 확인 (로컬, 글로벌, 시스템 gitignore 모두 참조)
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

**ignore 처리되지 않은 경우:**

Jesse의 규칙 "고장난 것은 즉시 수리하라"에 따라:
1. .gitignore에 적절한 항목을 추가합니다
2. 변경 사항을 커밋합니다
3. worktree 생성을 진행합니다

**이것이 중요한 이유:** worktree 내용이 실수로 저장소에 커밋되는 것을 방지합니다.

### 글로벌 디렉터리의 경우 (~/.config/superpowers/worktrees)

.gitignore 검증이 필요 없습니다 - 프로젝트 외부에 위치하기 때문입니다.

## 생성 단계

### 1. 프로젝트명 감지

```bash
project=$(basename "$(git rev-parse --show-toplevel)")
```

### 2. Worktree 생성

```bash
# 전체 경로 결정
case $LOCATION in
  .worktrees|worktrees)
    path="$LOCATION/$BRANCH_NAME"
    ;;
  ~/.config/superpowers/worktrees/*)
    path="~/.config/superpowers/worktrees/$project/$BRANCH_NAME"
    ;;
esac

# 새 브랜치로 worktree 생성
git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

### 3. 프로젝트 설정 실행

자동 감지 후 적절한 설정을 실행합니다:

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

### 4. 클린 베이스라인 검증

worktree가 깨끗한 상태에서 시작하는지 테스트를 실행하여 확인합니다:

```bash
# 예시 - 프로젝트에 적합한 명령 사용
npm test
cargo test
pytest
go test ./...
```

**테스트 실패 시:** 실패 내용을 보고하고, 진행할지 조사할지 질문합니다.

**테스트 통과 시:** 준비 완료를 보고합니다.

### 5. 위치 보고

```
Worktree 준비 완료: <전체-경로>
테스트 통과 (<N>개 테스트, 0개 실패)
<기능명> 구현 준비 완료
```

## 빠른 참조

| 상황 | 조치 |
|------|------|
| `.worktrees/` 존재 | 사용 (ignore 확인) |
| `worktrees/` 존재 | 사용 (ignore 확인) |
| 둘 다 존재 | `.worktrees/` 사용 |
| 둘 다 없음 | CLAUDE.md 확인 → 사용자에게 질문 |
| 디렉터리가 ignore 처리되지 않음 | .gitignore에 추가 + 커밋 |
| 베이스라인 중 테스트 실패 | 실패 보고 + 질문 |
| package.json/Cargo.toml 없음 | 의존성 설치 건너뜀 |

## 흔한 실수

### ignore 검증 건너뛰기

- **문제:** worktree 내용이 추적되어 git status를 오염시킴
- **해결:** 프로젝트 로컬 worktree 생성 전 항상 `git check-ignore`를 사용

### 디렉터리 위치 가정하기

- **문제:** 불일치를 초래하고, 프로젝트 규칙을 위반
- **해결:** 우선순위 따르기: 기존 > CLAUDE.md > 질문

### 실패한 테스트 상태에서 진행하기

- **문제:** 새로운 버그와 기존 문제를 구분할 수 없음
- **해결:** 실패를 보고하고, 진행에 대한 명시적 허락을 받기

### 설정 명령 하드코딩하기

- **문제:** 다른 도구를 사용하는 프로젝트에서 작동하지 않음
- **해결:** 프로젝트 파일(package.json 등)에서 자동 감지

## 예시 워크플로우

```
You: using-git-worktrees 스킬을 사용하여 격리된 작업공간을 설정합니다.

[.worktrees/ 확인 - 존재함]
[ignore 확인 - git check-ignore로 .worktrees/가 ignore 처리됨을 확인]
[worktree 생성: git worktree add .worktrees/auth -b feature/auth]
[npm install 실행]
[npm test 실행 - 47개 통과]

Worktree 준비 완료: /Users/jesse/myproject/.worktrees/auth
테스트 통과 (47개 테스트, 0개 실패)
auth 기능 구현 준비 완료
```

## 위험 신호

**절대 하지 말 것:**
- ignore 처리 확인 없이 worktree 생성 (프로젝트 로컬)
- 베이스라인 테스트 검증 건너뛰기
- 질문 없이 실패한 테스트 상태에서 진행
- 모호한 상황에서 디렉터리 위치 가정
- CLAUDE.md 확인 건너뛰기

**항상 할 것:**
- 디렉터리 우선순위 따르기: 기존 > CLAUDE.md > 질문
- 프로젝트 로컬의 경우 디렉터리가 ignore 처리되었는지 확인
- 프로젝트 설정 자동 감지 및 실행
- 클린 테스트 베이스라인 검증

## 통합

**호출하는 스킬:**
- **brainstorming** (Phase 4) - 설계가 승인되고 구현이 이어질 때 필수
- **subagent-driven-development** - 작업 실행 전 필수
- **executing-plans** - 작업 실행 전 필수
- 격리된 작업공간이 필요한 모든 스킬

**함께 사용하는 스킬:**
- **finishing-a-development-branch** - 작업 완료 후 정리에 필수
