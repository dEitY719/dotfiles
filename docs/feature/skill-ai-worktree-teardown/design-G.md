# ai-worktree:teardown — Design Document

## Overview

AI 워크트리 작업 완료 후 정리 스킬.
`ai-worktree:spawn`의 역연산으로, 워크트리 제거 → main 복귀 → remote 동기화를 한 번에 수행한다.

## Trigger Phrases

- "작업 끝", "워크트리 정리", "teardown", "cleanup worktree"
- "작업 완료됐어", "워크트리 제거해줘", "clean up and go back to main"

## Preconditions

사용자는 이미 다음을 완료한 상태:

1. 워크트리에서 코드 작업 완료
2. PR 생성 및 push 완료
3. main에 merge 완료 (사용자가 직접 승인)

## Execution Flow

```
[워크트리 내부에서 실행]
    │
    ├─ Step 1: Validate — 워크트리 내부인지 확인
    │
    ├─ Step 2: Pre-flight checks — uncommitted changes, unpushed commits
    │
    ├─ Step 3: Identify main repo — git-common-dir로 메인 repo 경로 추출
    │
    ├─ Step 4: Switch to main repo — cd {main-repo-path}
    │
    ├─ Step 5: Remove worktree — git worktree remove {path}
    │
    ├─ Step 6: Delete branch — git branch -d {branch} (safe delete)
    │
    ├─ Step 7: Sync main — git checkout main && git pull origin main
    │
    ├─ Step 8: Handle conflicts — (if any) resolve and report
    │
    ├─ Step 9: Log — append TEARDOWN entry to ai-worktree-spawn.log
    │
    └─ Step 10: Report
```

## Step Details

### Step 1: Validate

현재 위치가 worktree 내부인지 확인.

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
GIT_DIR="$(git rev-parse --git-dir)"

# 워크트리 내부: GIT_DIR != GIT_COMMON
if [[ "$GIT_DIR" == "$GIT_COMMON" ]]; then
  echo "Error: Not inside a worktree. Nothing to tear down."
  exit 1
fi
```

> **spawn과 반대**: spawn은 "워크트리 안이면 차단", teardown은 "워크트리 밖이면 차단".

### Step 2: Pre-flight Checks

uncommitted changes와 unpushed commits를 확인하여 작업 손실을 방지.

```bash
# Uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Warning: Uncommitted changes detected."
  echo "  Options: commit, stash, or --force to discard"
  # --force 없으면 중단
fi

# Unpushed commits
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "no-upstream")
if [[ "$REMOTE" != "no-upstream" && "$LOCAL" != "$REMOTE" ]]; then
  echo "Warning: Unpushed commits detected."
  # --force 없으면 중단
fi
```

### Step 3: Identify Main Repo and Worktree Info

```bash
WORKTREE_PATH="$(git rev-parse --show-toplevel)"
MAIN_REPO="$(git rev-parse --git-common-dir | sed 's|/\.git$||')"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
WORKTREE_NAME="$(basename "$WORKTREE_PATH")"
```

### Step 4: Switch to Main Repo

```bash
cd "$MAIN_REPO"
```

### Step 5: Remove Worktree

```bash
git worktree remove "$WORKTREE_PATH"
# 실패 시 (dirty worktree + --force)
# git worktree remove --force "$WORKTREE_PATH"
```

### Step 6: Delete Branch

safe delete로 merge 확인 후 삭제. merge되지 않았으면 경고.

```bash
if ! git branch -d "$BRANCH" 2>/dev/null; then
  echo "Warning: Branch '$BRANCH' not fully merged."
  echo "  Use --force to delete anyway, or check merge status."
  # --force 시: git branch -D "$BRANCH"
fi
```

### Step 7: Sync Main

```bash
git checkout main
git pull origin main
```

### Step 8: Handle Conflicts

pull 중 conflict 발생 시:

```bash
if git pull origin main 2>&1 | grep -q "CONFLICT"; then
  echo "Conflicts detected during pull. Resolving..."
  # AI agent가 conflict 파일을 분석하고 해결 시도
  # 해결 불가 시 사용자에게 보고
fi
```

### Step 9: Log

spawn 로그와 같은 파일에 TEARDOWN 이벤트 기록.

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] TEARDOWN worktree=${WORKTREE_NAME} branch=${BRANCH} path=${WORKTREE_PATH}" \
  >> "${GIT_COMMON}/ai-worktree-spawn.log"
```

### Step 10: Report

```
[OK] Teardown complete
  Removed:  ../my-app-gemini-1
  Branch:   wt/gemini/1 (deleted)
  Now on:   main (up to date with origin/main)
```

## Options

| Option | Description | Default |
|---|---|---|
| `--force` | Skip pre-flight checks, force remove dirty worktree | `false` |
| `--keep-branch` | Don't delete the branch after removing worktree | `false` |
| `--dry-run` | Print plan without executing | `false` |

## Error Handling

| Situation | Action |
|---|---|
| Not inside a worktree | Print error, stop |
| Uncommitted changes | Warn, stop (unless `--force`) |
| Unpushed commits | Warn, stop (unless `--force`) |
| Branch not fully merged | Warn, stop branch delete (unless `--force`) |
| Worktree remove fails | Try `--force`, report if still fails |
| Pull conflict | AI agent attempts resolution, reports to user |
| Main branch not found | Try `master`, then error |

## Relationship with ai-worktree:spawn

```
spawn                          teardown
─────                          ────────
Validate (NOT in worktree)  ↔  Validate (IN worktree)
Detect agent                   (not needed)
Compute path + index           Extract path from current location
Create worktree + branch       Remove worktree + branch
Log SPAWN                      Log TEARDOWN
cd into worktree               cd into main repo
```

spawn의 `ai-worktree-spawn.log`를 공유하여 생애주기 추적 가능.

## File Structure (예상)

```
ai-worktree-teardown/
├── SKILL.md
└── references/
    ├── bash-commands.md
    └── options-and-errors.md
```

`agent-detection.md`는 불필요 (teardown은 agent 이름을 감지할 필요 없음 —
현재 워크트리의 branch/path에서 정보를 추출).

## git-crypt Consideration

teardown에서는 git-crypt 문제 없음. worktree를 제거하고 main repo로 돌아가는
과정에서 filter가 개입하지 않음. main repo는 이미 unlock 상태.
