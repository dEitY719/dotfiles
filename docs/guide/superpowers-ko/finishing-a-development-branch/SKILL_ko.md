---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup
---

# 개발 브랜치 마무리하기

## 개요

명확한 옵션을 제시하고 선택한 워크플로우를 처리하여 개발 작업의 완료를 안내합니다.

**핵심 원칙:** 테스트 검증 → 옵션 제시 → 선택 실행 → 정리.

**시작 시 알림:** "finishing-a-development-branch 스킬을 사용하여 이 작업을 완료하겠습니다."

## 프로세스

### 단계 1: 테스트 검증

**옵션을 제시하기 전에 테스트가 통과하는지 검증합니다:**

```bash
# 프로젝트의 테스트 스위트 실행
npm test / cargo test / pytest / go test ./...
```

**테스트 실패 시:**
```
테스트 실패 (<N>개 실패). 완료 전에 수정해야 합니다:

[실패 항목 표시]

테스트가 통과할 때까지 머지/PR을 진행할 수 없습니다.
```

중단합니다. 단계 2로 진행하지 마세요.

**테스트 통과 시:** 단계 2로 진행합니다.

### 단계 2: 베이스 브랜치 결정

```bash
# 일반적인 베이스 브랜치 시도
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

또는 질문합니다: "이 브랜치는 main에서 분기되었는데 맞나요?"

### 단계 3: 옵션 제시

정확히 다음 4가지 옵션을 제시합니다:

```
구현이 완료되었습니다. 어떻게 하시겠습니까?

1. <base-branch>로 로컬 머지
2. 푸시하고 Pull Request 생성
3. 브랜치를 현재 상태로 유지 (나중에 직접 처리)
4. 이 작업 폐기

어떤 옵션을 선택하시겠습니까?
```

**설명을 추가하지 마세요** - 옵션을 간결하게 유지합니다.

### 단계 4: 선택 실행

#### 옵션 1: 로컬 머지

```bash
# 베이스 브랜치로 전환
git checkout <base-branch>

# 최신 상태로 풀
git pull

# 피처 브랜치 머지
git merge <feature-branch>

# 머지 결과에 대해 테스트 검증
<test command>

# 테스트 통과 시
git branch -d <feature-branch>
```

이후: 워크트리 정리 (단계 5)

#### 옵션 2: 푸시 및 PR 생성

```bash
# 브랜치 푸시
git push -u origin <feature-branch>

# PR 생성
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<변경 사항 2-3줄 요약>

## Test Plan
- [ ] <검증 단계>
EOF
)"
```

이후: 워크트리 정리 (단계 5)

#### 옵션 3: 현재 상태 유지

보고: "브랜치 <name>을 유지합니다. 워크트리는 <path>에 보존됩니다."

**워크트리를 정리하지 마세요.**

#### 옵션 4: 폐기

**먼저 확인합니다:**
```
다음이 영구적으로 삭제됩니다:
- 브랜치 <name>
- 모든 커밋: <commit-list>
- <path>의 워크트리

확인하려면 'discard'를 입력하세요.
```

정확한 확인을 기다립니다.

확인된 경우:
```bash
git checkout <base-branch>
git branch -D <feature-branch>
```

이후: 워크트리 정리 (단계 5)

### 단계 5: 워크트리 정리

**옵션 1, 2, 4의 경우:**

워크트리인지 확인합니다:
```bash
git worktree list | grep $(git branch --show-current)
```

워크트리인 경우:
```bash
git worktree remove <worktree-path>
```

**옵션 3의 경우:** 워크트리를 유지합니다.

## 빠른 참조

| 옵션 | 머지 | 푸시 | 워크트리 유지 | 브랜치 정리 |
|------|------|------|--------------|------------|
| 1. 로컬 머지 | ✓ | - | - | ✓ |
| 2. PR 생성 | - | ✓ | ✓ | - |
| 3. 현재 상태 유지 | - | - | ✓ | - |
| 4. 폐기 | - | - | - | ✓ (강제) |

## 흔한 실수

**테스트 검증 생략**
- **문제:** 깨진 코드를 머지하거나 실패하는 PR을 생성
- **해결:** 옵션을 제시하기 전에 항상 테스트를 검증

**열린 질문**
- **문제:** "다음에 뭘 하면 될까요?" → 모호함
- **해결:** 정확히 4가지 구조화된 옵션을 제시

**자동 워크트리 정리**
- **문제:** 필요할 수 있는 워크트리를 삭제 (옵션 2, 3)
- **해결:** 옵션 1과 4에서만 정리

**폐기 시 확인 없음**
- **문제:** 실수로 작업을 삭제
- **해결:** 입력된 "discard" 확인을 필수로 요구

## 위험 신호

**절대 하지 마세요:**
- 테스트가 실패하는 상태에서 진행
- 결과에 대한 테스트 검증 없이 머지
- 확인 없이 작업 삭제
- 명시적 요청 없이 force-push

**항상 하세요:**
- 옵션을 제시하기 전에 테스트 검증
- 정확히 4가지 옵션 제시
- 옵션 4에서 입력된 확인 받기
- 옵션 1과 4에서만 워크트리 정리

## 연동

**호출되는 곳:**
- **subagent-driven-development** (단계 7) - 모든 작업 완료 후
- **executing-plans** (단계 5) - 모든 배치 완료 후

**함께 사용:**
- **using-git-worktrees** - 해당 스킬에서 생성된 워크트리를 정리
