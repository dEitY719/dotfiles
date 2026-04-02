# Design: `ai-worktree:spawn` Skill (design-C, Final)

- 문서 ID: `skill-ai-worktree-spawn-design-C`
- 작성자: Claude
- 최종 갱신: 2026-04-02
- 상태: **Final** (design-CX, design-G 리뷰 + 피드백 반영)
- 범위: 다중 AI 코딩 에이전트 병렬 작업을 위한 git worktree 자동 생성

> 1명의 개발자가 5~6개의 AI 코딩 에이전트를 동시에 투입하여 병렬 개발을 오케스트레이션하는 워크플로우의 핵심 도구.

---

## 1. 스킬 이름

**확정: `/ai-worktree:spawn`**

- `ai-worktree` -- AI 에이전트 전용 worktree 관리 그룹
- `spawn` -- 새 작업 공간을 생성하는 서브커맨드

| 호출 방식 | 예시 |
|---|---|
| 명령어 | `/ai-worktree:spawn` |
| 명령어 + 인자 | `/ai-worktree:spawn --task "login-api"` |
| 자연어 (한국어) | "새로운 작업 시작하자", "격리된 작업 공간 만들어줘" |
| 자연어 (영어) | "start new task", "spawn a worktree" |

향후 서브커맨드 확장: `ai-worktree:list`, `ai-worktree:teardown`, `ai-worktree:status`

### 운영 방식

**공통 shell command + 각 에이전트 프롬프트 포인터** 방식으로 운영한다.

- 핵심 로직: `tools/ai-worktree-spawn.sh` (Bash 스크립트, 모든 AI 에이전트 공용)
- 각 AI 에이전트의 설정 파일(GEMINI.md, AGENTS.md 등)에는 "이 스크립트를 호출하라"는 포인터만 기재
- Claude Code 전용 skill loader(SKILL.md)는 사용하지 않는다

---

## 2. 문제 정의

동일 저장소에서 여러 AI가 같은 물리 디렉토리를 공유하면 아래 문제가 발생한다:

1. **브랜치 체크아웃 덮어씀** -- 에이전트 A가 checkout하면 에이전트 B의 파일 상태가 즉시 변경
2. **테스트/빌드 산출물 엉킴** -- `.cache`, `node_modules`, `__pycache__` 등 공유
3. **의도치 않은 스테이징/커밋** -- 다른 에이전트가 수정한 파일이 함께 커밋
4. **브랜치 전환 중 컨텍스트 손실** -- 작업 중 파일이 사라지거나 변경

**해결**: 각 에이전트가 **물리적으로 분리된 디렉토리**에서 작업하되, `.git` 저장소는 하나로 공유 -> **`git worktree`**

---

## 3. 목표와 비목표

### 목표

1. 각 에이전트가 독립 디렉토리에서 병렬 작업한다.
2. 각 에이전트가 고유 브랜치를 가진다.
3. 반복 호출 시 `{agent}-{N}` 번호가 자동 증가한다.
4. 작업 시작 시 실패/충돌 상황을 예측하고 차단한다.
5. 생성 결과(경로, 브랜치, teardown 안내)를 즉시 출력한다.

### 비목표

1. PR 자동 생성/자동 머지까지 수행하지 않는다.
2. 원격 리포지토리 정책(보호 브랜치, 리뷰 룰)을 변경하지 않는다.
3. 여러 저장소를 한 번에 생성하는 오케스트레이션은 포함하지 않는다.

---

## 4. 기능 요구사항

### FR-1. 실행 전제조건

1. 현재 경로가 Git 저장소 루트 또는 하위여야 한다.
2. `.git` 메타데이터에 접근 가능해야 한다.
3. base branch(`main` 또는 `--base`로 지정한 ref)가 존재해야 한다.
4. **worktree 내부에서 실행하면 즉시 중단한다.** 항상 메인 저장소의 새 터미널에서 실행해야 한다.

### FR-2. 에이전트 식별 (우선순위 순)

아래 우선순위로 `agent_name`을 결정한다:

| 우선순위 | 방법 | 예시 |
|---|---|---|
| 1 | 명시 인자 `--agent` | `--agent claude` |
| 2 | 환경변수 `AI_AGENT_NAME` | `export AI_AGENT_NAME=gemini` |
| 3 | 에이전트별 고유 환경변수 | 아래 감지 테이블 참조 |
| 4 | fallback 기본값 | `agent` |

**에이전트별 고유 환경변수 감지 테이블:**

| AI Agent | 감지 방법 | 결과 이름 |
|---|---|---|
| Claude Code | `$CLAUDECODE == 1` | `claude` |
| Gemini CLI | `$GEMINI_CLI == 1` 또는 프로세스명 `gemini` | `gemini` |
| Codex CLI | `$CODEX_CLI == 1` 또는 프로세스명 `codex` | `codex` |
| OpenCode | `$OPENCODE == 1` 또는 `~/.opencode/` 존재 | `opencode` |
| Cursor | `$CURSOR == 1` 또는 `$TERM_PROGRAM == cursor` | `cursor` |
| Copilot | `$GITHUB_COPILOT == 1` | `copilot` |

> **주의**: 환경변수명은 도구 버전에 따라 달라질 수 있음. 감지 로직은 `detect_ai_agent()` 함수로 분리하여 확장 가능하게 설계.

### FR-3. 인덱스 할당 (Auto-Increment)

1. 패턴: `../{project}-{agent}-{N}`
2. `git worktree list` + 부모 디렉토리 스캔으로 기존 `{project}-{agent}-*` 중 최대 N 파악
3. 새 번호 = max(N) + 1 (없으면 1)
4. **동시 실행 충돌 방지**: lockfile 기반 원자 할당 수행
   - lock 경로: `$(git rev-parse --git-common-dir)/ai-worktree-spawn.lock`
   - lock 획득 실패 시: 1초 대기 후 재시도 (최대 3회)
   - lock timeout: 10초 (비정상 종료 대비 stale lock 자동 제거)
   - **lock 범위: 인덱스 계산부터 worktree 생성 완료까지** (중간 해제 금지)

```
알고리즘:
1. GIT_COMMON="$(git rev-parse --git-common-dir)"
2. acquire_lock("${GIT_COMMON}/ai-worktree-spawn.lock")  # flock 또는 mkdir 원자 연산
3. git worktree list -> "{project}-{agent}-N" 패턴 필터링
4. max(N) + 1 = 새 번호
5. 경로가 이미 존재하면 -> N + 1로 건너뜀
6. git worktree add ...  # worktree 생성
7. release_lock
```

**lock 구현 권장**: `flock(1)` 유틸리티 (Linux/WSL 기본 내장) 또는 `mkdir` 원자 연산 (macOS 호환). 비정상 종료 시 데드락 방지를 위해 lock 파일에 PID + 타임스탬프를 기록하고, 10초 경과 stale lock은 자동 제거한다.

### FR-4. 브랜치 생성 전략

| 시나리오 | 브랜치명 | 예시 |
|---|---|---|
| 기본 (인자 없음) | `wt/{agent}/{N}` | `wt/claude/1` |
| `--task` 지정 | `wt/{agent}/{N}-{task-slug}` | `wt/gemini/2-login-api` |
| 명시 브랜치 지정 (신규) | 사용자 지정값 + `-b` 플래그 | `feat/add-auth` |
| 명시 브랜치 지정 (기존) | 사용자 지정값, `-b` 없이 checkout | `feat/add-auth` |
| AI 자동 생성 (optional) | AI가 태스크 분석 후 slug 생성 | `wt/claude/1-user-signup` |

**브랜치 존재 여부에 따른 분기:**

```bash
if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    # 기존 브랜치 -> -b 없이 checkout
    git worktree add "${worktree_path}" "${branch_name}"
else
    # 신규 브랜치 -> -b로 생성
    git worktree add -b "${branch_name}" "${worktree_path}" "${base_ref}"
fi
```

- `task-slug` 정규화: 영문 소문자/숫자/하이픈만 허용, 최대 30자
- **한글 task 설명 처리**: `--task` 인자는 반드시 영문 slug로 전달한다. AI 에이전트가 한글 태스크 설명("로그인 기능 개발")을 영문 slug(`login-api`)로 번역한 뒤 `--task login-api`로 스크립트에 넘긴다. 번역 책임은 AI 프롬프트 측에 있다.
- 브랜치가 이미 다른 worktree에서 사용 중이면 suffix(`-2`, `-3`) 증가 재시도

**base branch 결정 순서:**

1. `--base <ref>` 인자로 명시 지정
2. `origin/main` (원격 추적 브랜치 우선)
3. `main` 또는 `master` (로컬 fallback)
4. 현재 체크아웃된 브랜치

### FR-5. Worktree 생성 + 결과 출력

생성 명령:

```bash
git worktree add -b "${branch_name}" "${worktree_path}" "${base_ref}"
```

생성 성공 시 출력:

```
[OK] 작업 공간 준비 완료
  경로:     ../my-app-claude-1
  브랜치:   wt/claude/1
  base:     origin/main

  다음 명령으로 이동하세요:
    cd ../my-app-claude-1

  작업 완료 후 정리:
    git push -u origin wt/claude/1
    git worktree remove ../my-app-claude-1
    git branch -d wt/claude/1
```

> 스크립트는 외부 프로세스로 실행되므로 호출자 셸의 cwd를 직접 변경할 수 없다. `cd` 명령은 안내 텍스트로 출력하며, AI 에이전트가 이 출력을 읽고 직접 `cd`를 실행한다.

### FR-6. 옵션

| 옵션 | 설명 | 기본값 |
|---|---|---|
| `--agent <name>` | 에이전트명 수동 지정 | 자동 감지 |
| `--task "slug"` | 브랜치 slug 생성에 사용 (영문만) | 없음 |
| `--base <ref>` | 기반 브랜치/커밋 지정 | `origin/main` |
| `--dry-run` | 실제 생성 없이 계획만 출력 | `false` |

> `--list` 기능은 본 커맨드에 포함하지 않는다. `ai-worktree:list` 별도 스킬로 제공 예정.

---

## 5. 비기능 요구사항

### NFR-1. 안전성

| 상황 | 처리 |
|---|---|
| **worktree 내부에서 실행** | **즉시 중단**: "Error: Cannot spawn from inside a worktree. Run from the main repository." |
| 메인 작업 디렉토리가 dirty | 경고 출력 (uncommitted changes 존재) -> 계속 진행 허용 |
| worktree 경로가 이미 존재 | 번호 자동 증분하여 다음 번호 사용 |
| 동일 브랜치가 다른 worktree에서 사용 중 | 즉시 중단, 명확한 에러 메시지 |
| bare repository | `git rev-parse --show-toplevel` 실패 -> 에러 메시지 |
| detached HEAD | base branch를 `main`/`master`로 fallback |
| 부모 디렉토리 쓰기 권한 없음 | 즉시 중단, 권한 에러 메시지 |

### NFR-2. 추적성 (Logging)

생성 시 아래 메타를 로그로 기록:

```
[2026-04-02T10:30:15] SPAWN project=my-app agent=claude index=2 path=../my-app-claude-2 branch=wt/claude/2 base=origin/main
```

- 저장 위치: `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log`
- 형식: 한 줄 구조화 로그 (timestamp + key=value)

### NFR-3. 이식성

1. **타깃 셸: Bash 5.x** (macOS Homebrew bash, Linux, WSL 공통)
2. 경로 처리 시 **공백 포함 경로**를 안전하게 quoting
3. POSIX sh 호환은 비목표 (Bash 전용 기능 `[[ ]]`, `local`, 배열 등 사용 가능)

---

## 6. 사용자 시나리오

### 6.1 기본 사용 (인자 없음)

```
사용자: "새로운 작업 시작하자" 또는 /ai-worktree:spawn
AI: worktree를 생성합니다...
    -> tools/ai-worktree-spawn.sh
    [OK] 작업 공간 준비 완료
      경로:   ../dotfiles-claude-1
      브랜치: wt/claude/1
      base:   origin/main
    AI가 cd ../dotfiles-claude-1 실행 후 작업 대기
```

### 6.2 task 설명 포함

```
사용자: /ai-worktree:spawn --task "로그인 기능 개발"
AI: (한글 -> 영문 slug 번역) --task login-api
    -> tools/ai-worktree-spawn.sh --task login-api
    [OK] ../dotfiles-claude-1 (branch: wt/claude/1-login-api)
```

### 6.3 기존 브랜치 checkout

```
사용자: /ai-worktree:spawn feat/add-auth
AI: (feat/add-auth 브랜치가 이미 존재)
    -> git worktree add ../dotfiles-claude-1 feat/add-auth
    [OK] ../dotfiles-claude-1 (branch: feat/add-auth)
```

### 6.4 신규 브랜치 생성

```
사용자: /ai-worktree:spawn feat/new-feature
AI: (feat/new-feature 브랜치가 존재하지 않음)
    -> git worktree add -b feat/new-feature ../dotfiles-claude-1 origin/main
    [OK] ../dotfiles-claude-1 (branch: feat/new-feature)
```

### 6.5 dry-run

```
사용자: /ai-worktree:spawn --dry-run
AI: [dry-run] 아래 계획을 실행할 예정입니다:
      에이전트: claude
      경로:    ../dotfiles-claude-1
      브랜치:  wt/claude/1
      base:    origin/main
      명령어:  git worktree add -b wt/claude/1 ../dotfiles-claude-1 origin/main
    (실제 생성하지 않았습니다)
```

### 6.6 다중 에이전트 동시 실행 결과

```
터미널A (gemini-cli)  -> ../my-app-gemini-1   (branch: wt/gemini/1)
터미널B (gemini-cli)  -> ../my-app-gemini-2   (branch: wt/gemini/2)
터미널C (codex-cli)   -> ../my-app-codex-1    (branch: wt/codex/1)
터미널D (claude-code) -> ../my-app-claude-1   (branch: wt/claude/1)
터미널E (claude-code) -> ../my-app-claude-2   (branch: wt/claude/2)
터미널F (opencode)    -> ../my-app-opencode-1 (branch: wt/opencode/1)
```

---

## 7. 실행 흐름 (Flowchart)

```
/ai-worktree:spawn [options] [branch-name]
    |
    +-- 1. 전제조건 검증
    |     -> git repo 확인, base ref 존재 확인
    |     -> worktree 내부이면 즉시 중단 (에러)
    |     -> dirty 상태면 경고 출력 (계속 진행)
    |     -> 부모 디렉토리 쓰기 권한 확인
    |
    +-- 2. AI 에이전트 감지 (detect_ai_agent)
    |     -> --agent > $AI_AGENT_NAME > 고유 env > fallback
    |
    +-- 3. 프로젝트명 추출
    |     -> basename $(git rev-parse --show-toplevel)
    |
    +-- 4. Lock 획득
    |     -> flock 또는 mkdir "${GIT_COMMON}/ai-worktree-spawn.lock"
    |     -> 실패 시 1초 대기, 최대 3회 재시도
    |     |
    |     +-- 5. 인덱스 계산 (lock 내부)
    |     |     -> git worktree list + ls ../ -> max+1
    |     |     -> 경로 충돌 시 N+1 건너뜀
    |     |
    |     +-- 6. 브랜치명 결정 (lock 내부)
    |     |     -> 명시 인자 > --task slug > 기본 wt/{agent}/{N}
    |     |     -> 기존 브랜치면 -b 생략, 신규면 -b 사용
    |     |
    |     +-- 7. (--dry-run이면) 계획 출력 후 lock 해제, 종료
    |     |
    |     +-- 8. Worktree 생성 (lock 내부)
    |     |     -> git worktree add [-b] {branch} {path} [{base_ref}]
    |     |
    |     +-- 9. Lock 해제
    |
    +-- 10. 로그 기록
    |     -> ${GIT_COMMON}/ai-worktree-spawn.log에 append
    |
    +-- 11. 결과 출력
          -> 경로, 브랜치, base 정보
          -> cd 명령 안내 (스크립트에서 직접 cd 불가)
          -> push/remove/branch -d teardown 안내
```

---

## 8. 실패 시나리오와 처리

| # | 상황 | 에러 메시지 | 처리 |
|---|---|---|---|
| 1 | Git 저장소가 아님 | `Error: Not a git repository` | 즉시 중단 |
| 2 | **worktree 내부에서 실행** | `Error: Cannot spawn from inside a worktree. Run from the main repository.` | 즉시 중단 |
| 3 | base ref 없음 | `Error: Base ref not found: <ref>` | `main`/`origin/main` 후보 제시 후 중단 |
| 4 | 번호 할당 경합 (lock 충돌) | `Waiting for lock... retry N/3` | 1초 대기 후 재시도 (최대 3회) |
| 5 | 경로 이미 존재 | `Warning: Path exists, using next index` | 자동으로 다음 번호 사용 |
| 6 | 브랜치 이미 사용 중 | `Error: Branch '<name>' already checked out at '<path>'` | 사용자에게 다른 브랜치명 요청 |
| 7 | 부모 디렉토리 쓰기 권한 없음 | `Error: Permission denied: ../` | 즉시 중단, 경로 확인 요청 |
| 8 | stale lock (비정상 종료) | `Warning: Stale lock detected (age > 10s), removing` | lock 자동 제거 후 재시도 |

---

## 9. 구현 계획

### 9.1 파일 구조

```
tools/
  ai-worktree-spawn.sh        # 공통 shell 스크립트 (모든 AI 에이전트 공용)
    - detect_ai_agent()        # 에이전트 감지 함수
    - allocate_index()         # lock 기반 인덱스 할당
    - resolve_branch()         # 브랜치 존재 여부 판단 + 명령 분기
    - create_worktree()        # worktree 생성 + 로그 기록
    - main()                   # 옵션 파싱 + 오케스트레이션
```

> Claude Code 전용 skill loader(SKILL.md, README.md 등)는 사용하지 않는다. 모든 AI 에이전트가 동일한 `tools/ai-worktree-spawn.sh`를 호출하는 구조이다.

### 9.2 AI 에이전트별 프롬프트 포인터

각 AI의 설정 파일에 다음 지침을 추가:

| Agent | 설정 파일 | 포인터 내용 |
|---|---|---|
| Claude Code | `CLAUDE.md` 또는 `AGENTS.md` | "작업 시작 시 `tools/ai-worktree-spawn.sh` 실행" |
| Gemini CLI | `GEMINI.md` | 동일 |
| Codex CLI | `AGENTS.md` | 동일 |
| OpenCode | `AGENTS.md` | 동일 |

프롬프트 포인터에 포함할 내용:

1. 스크립트 호출 방법과 옵션
2. `--task` 인자에는 한글을 영문 slug로 번역하여 전달
3. 출력된 `cd` 명령을 읽고 직접 실행
4. 실패 시 에러 메시지를 사용자에게 전달

### 9.3 공통 Shell 스크립트 인터페이스

```bash
# 사용법
tools/ai-worktree-spawn.sh [options] [branch-name]

# 옵션
--agent <name>    에이전트명 수동 지정
--task "slug"     브랜치 slug 생성 (영문 소문자/숫자/하이픈)
--base <ref>      기반 브랜치 지정 (default: origin/main)
--dry-run         계획만 출력

# 종료 코드
0   성공
1   전제조건 실패 (not a repo, inside worktree, permission denied)
2   lock 획득 실패 (3회 재시도 후)
3   git worktree add 실패
```

---

## 10. 정리(Teardown) 전략

### 10.1 생성 시 안내 (FR-5에서 자동 출력)

```bash
# 작업 완료 후 실행
git -C ../my-app-claude-1 push -u origin wt/claude/1
git worktree remove ../my-app-claude-1
git branch -d wt/claude/1
```

### 10.2 일괄 정리 (향후 `ai-worktree:teardown`)

```bash
# 본인 에이전트 worktree 전체 정리
git worktree list | grep "{project}-claude-" | awk '{print $1}' | xargs -I{} git worktree remove {}

# 죽은 worktree 정리
git worktree prune

# 머지 완료된 wt/* 브랜치 정리
git branch --merged main | grep "^  wt/" | xargs git branch -d
```

---

## 11. 수용 기준 (Acceptance Criteria)

| # | 기준 | 검증 방법 |
|---|---|---|
| AC-1 | 같은 프로젝트에서 6개 TUI 동시 호출 시, 경로/브랜치 중복 없음 | 수동 테스트: 6개 터미널 동시 실행 |
| AC-2 | 동일 에이전트 중복 실행 시 번호 순차 증가 | `claude` 3회 연속 -> `claude-1`, `claude-2`, `claude-3` |
| AC-3 | `--dry-run` 결과가 실제 실행 계획과 동일 | dry-run 출력 vs 실제 생성 결과 비교 |
| AC-4 | 잘못된 base ref 입력 시 생성 없이 명확한 오류 출력 | `--base nonexistent` -> 에러, worktree 미생성 |
| AC-5 | 생성 완료 메시지에 경로, 브랜치, teardown 안내 포함 | 출력 확인 |
| AC-6 | macOS / Linux / WSL에서 동일 동작 | CI 또는 수동 크로스 플랫폼 테스트 |
| AC-7 | `${GIT_COMMON}/ai-worktree-spawn.log`에 생성 이력 기록 | 로그 파일 확인 |
| AC-8 | worktree 내부에서 실행 시 즉시 중단 | worktree 내부에서 호출 -> 에러 메시지, 미생성 |
| AC-9 | 기존 브랜치 지정 시 `-b` 없이 정상 checkout | 이미 존재하는 브랜치로 호출 -> 성공 |

---

## 12. 향후 확장

| 서브커맨드 | 설명 |
|---|---|
| `/ai-worktree:list` | 현재 프로젝트의 모든 AI worktree 목록 + 상태 표시 |
| `/ai-worktree:teardown` | 완료된 worktree 정리 (merged 브랜치 자동 감지 + 삭제) |
| `/ai-worktree:status` | 각 worktree의 변경사항/커밋 상태 요약 대시보드 |

---

## Appendix A: 설계 결정 근거 (3개 설계서 통합)

| 결정 사항 | 채택 출처 | 근거 |
|---|---|---|
| 목표/비목표 분리 | design-CX | scope creep 방지. PR 자동화 등은 비목표로 명시 |
| 에이전트 식별 4단계 우선순위 | design-CX | `--agent` override가 없으면 환경변수 바뀔 때 대응 불가 |
| lock 기반 동시성 제어 | design-CX | 6개 TUI 동시 실행 시 번호 충돌은 실제 발생 가능 |
| 브랜치 네임스페이스 `wt/` | design-CX | 일반 브랜치와 구분, 일괄 정리 용이 (`git branch \| grep wt/`) |
| `--dry-run` 옵션 | design-CX | 실행 전 검증은 안전성의 기본 |
| 추적 로그 | design-CX | 누가 언제 만들었는지 추적 불가하면 정리가 어려움 |
| 수용 기준(AC) 명시 | design-CX | 구현 완료 판단 기준 필요 |
| task-slug 기반 브랜치명 | design-G | `wt/gemini/2-login-api`가 `wt/gemini/2`보다 의도 파악 용이 |
| 다양한 자연어 트리거 | design-G | "격리된 작업 공간 만들어줘" 등 한국어 자연어 지원 |
| 상세 환경변수 감지표 | design-C | 에이전트별 구체적 감지 방법이 구현 시 즉시 참조 가능 |
| Cross-agent shell 스크립트 공통화 | design-C | 스킬 프롬프트는 AI별이나, 실행 로직은 공유 가능해야 함 |
| 실행 흐름 Flowchart | design-C | 구현 순서를 한눈에 파악 가능 |

## Appendix B: 피드백 반영 이력

| # | 출처 | 심각도 | 피드백 내용 | 반영 결과 |
|---|---|---|---|---|
| 1 | CX | High | FR-3 lock 범위와 Flowchart 불일치 | Flowchart 4-9단계를 lock 내부로 통일 |
| 2 | CX | High | `.git/` 하드코딩 -> `git rev-parse --git-common-dir` | lock/log 경로 전체를 `${GIT_COMMON}/` 기준으로 변경 |
| 3 | CX | High | SKILL.md 없음, 스킬 로더 미지원 | shell command + 프롬프트 포인터 구조로 전환, Section 9 재작성 |
| 4 | CX | Medium | `cd`는 외부 스크립트에서 호출자 cwd 변경 불가 | "cd 명령 안내 출력"으로 변경, FR-5/Flowchart 수정 |
| 5 | CX | Medium | `-b` 일변도, 기존 브랜치면 실패 | FR-4에 `git show-ref` 분기 로직 추가 |
| 6 | CX | Low | POSIX sh vs Bash 충돌 | Bash 5.x 타깃 확정, NFR-3 수정 |
| 7 | CX | Low | 이모지 출력 제거 | `[OK]`/`[dry-run]` 텍스트로 대체 |
| 8 | G | - | `clean` -> `teardown` | 문서 전체 일괄 수정 |
| 9 | G | - | lock 구현: `flock`/`mkdir` 원자성 | FR-3에 구현 권장사항 추가 |
| 10 | G | - | task-slug 한글 번역 규칙 | FR-4에 AI 프롬프트 측 번역 책임 명시 |
| D1 | CX 결정 | - | shell command + 프롬프트 포인터 운영 | Section 1, 9 전면 반영 |
| D2 | CX 결정 | - | worktree 내부 spawn 차단 | FR-1, NFR-1, 실패 시나리오 #2 추가 |
| D3 | CX 결정 | - | `--list`는 별도 스킬로 분리 | FR-6 주석, Section 12 반영 |
