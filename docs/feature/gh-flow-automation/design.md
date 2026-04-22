# gh-flow: Fire-and-forget GitHub Issue → PR Automation

**작성일**: 2026-04-22
**상태**: 설계 완료, 구현 대기

## 1. 배경

현재 개발 플로우는 수작업 단계가 많음:

```
(터미널)   gwt spawn <name>                     # worktree 생성
(터미널)   cd <worktree>
(터미널)   claude-yolo                          # TUI 진입
(TUI)      /gh-issue-implement <N>
(TUI)      /gh-commit
(TUI)      /gh-pr
(대기 ~7분) 동료 리뷰 기다림
(TUI)      /gh-pr-reply                         # 리뷰 코멘트 반영
(대기)     승인 폴링 (1분 간격 수동 확인)
(TUI)      /gh-pr-merge
(TUI)      /exit
(터미널)   gwt teardown
```

N개 이슈를 동시에 처리할 때 이 전 과정을 반복해야 해 집중력이 심하게 분산됨.

## 2. 목표 / 비목표

### 목표
- 한 커맨드 `gh-flow <N> [<N2> ...]` 로 N개 이슈를 **병렬**로 전과정 자동화
- **Fire-and-forget** — 커맨드 치고 자리 떠나도 됨, 결과는 칸반 보드에서 확인
- 리뷰 대기 중 claude 세션 **0개** 유지 (토큰/메모리 소모 없음)
- 실패 **격리** — 한 worker가 깨져도 다른 N-1개는 계속 진행

### 비목표
- 진행 상황 대시보드 UI (칸반 보드로 이미 해결됨)
- Slack/데스크탑 알림
- 리부팅 저항성 (systemd 없이 순수 쉘로 단순성 우선)
- 여러 리뷰 라운드 지원 — reply는 **1회만** 시도
- `/gh-pr-reply` 결과 검증 — 사용자의 기존 경험상 이 스킬이 실패한 적 없음

## 3. 아키텍처

```
사용자 터미널 (메인 repo에서)
    │
    │  $ gh-flow 13 42 88
    ▼
┌──────────────────────┐
│ gh-flow (orchestrator)│  bash 함수. N개 worker를 nohup 백그라운드로 fork 후 즉시 종료.
└──────┬───────────────┘
       │ forks (nohup + disown)
       ├──► worker-13  (독립 bash 프로세스)
       ├──► worker-42  (독립 bash 프로세스)
       └──► worker-88  (독립 bash 프로세스)

각 worker 생명주기:
  1. gwt spawn issue-<N>
  2. cd <worktree>
  3. claude -p "/gh-issue-flow <N>"          # implement → commit → PR
  4. poll 루프 (60s 간격):
       · gh pr view --json reviewDecision
       · APPROVED → loop 탈출
       · 리뷰 코멘트 존재 AND reply 미수행 → claude -p "/gh-pr-reply" 1회 실행
       · 그 외: 계속 polling
  5. claude -p "/gh-pr-merge"
  6. gwt teardown
  7. exit

상태/로그 디렉토리:
  ~/.local/state/gh-flow/<repo>/<issue>/
    ├── state         # "spawning|implementing|polling|merging|done|failed:<step>"
    ├── worktree.path # gwt spawn이 만든 경로
    ├── pr.number     # 생성된 PR 번호
    ├── reply.done    # 빈 파일 (존재하면 reply 이미 실행됨)
    └── log           # stdout+stderr tee
```

### 핵심 원칙
- 각 worker는 독립 프로세스 → 타 worker와 공유 상태 없음
- `gh-flow <N>`은 **멱등** — `state` 파일 검사해서 이미 실행 중/완료면 거부, 실패 상태면 이어서 재개
- orchestrator는 fork 후 즉시 종료 → 사용자 쉘 프롬프트 지연 없음

## 4. 컴포넌트

### 4.1 `shell-common/functions/gh_flow.sh`
POSIX 쉘 파일. bash/zsh에서 sourcing됨. 다음을 정의:

- **`gh-flow`** (함수): 오케스트레이터
  - Args: `<issue-number>... | -h|--help`
  - 전제: 메인 repo 내부 (worktree 아님), `gh` 인증됨
  - 동작: 각 이슈에 대해 `_gh_flow_worker`를 `nohup bash -c '...' &` 로 fork + `disown`
  - 출력: `ux_info "Spawned worker for #13 (pid=12345, log=...)"` 를 N번
  - 종료: 즉시 (백그라운드 워커는 살아있음)

- **`_gh_flow_worker`** (함수): worker 본체
  - Args: `<issue-number>`
  - 호출 경로: nohup된 서브셸이 `gh_flow.sh`를 source한 뒤 이 함수 호출
  - 단계별 실패 시 `state` 파일에 `failed:<step>` 쓰고 비정상 종료 (worktree 안 지움)
  - 각 claude 호출은 `claude --dangerously-skip-permissions -p "<slash-command>"` 형태

- **`_gh_flow_poll_reviews`** (헬퍼 함수): PR 리뷰 상태 조회
  - Args: `<pr-number>`
  - 반환: stdout에 `APPROVED | HAS_COMMENTS | WAITING`

- **`gh-flow-help`** + 섹션 헬퍼들: 기존 `*_help.sh` 컨벤션 따름

### 4.2 `~/.local/state/gh-flow/` 상태 디렉토리
런타임에 worker가 생성. XDG 베이스 경로 규칙 준수. `<repo>`는 `basename $(git rev-parse --show-toplevel)`로 도출.

## 5. 데이터 플로우

### 5.1 한 worker의 상태 전이

```
(start)
  │
  ▼
spawning ──── gwt spawn 성공 ──► implementing
  │                                   │
  │                                   ├── claude /gh-issue-flow 성공
  │                                   ▼
  │                                 polling ◄──────┐
  │                                   │            │ 계속 대기
  │                                   ├── reviewDecision == APPROVED
  │                                   │     ▼
  │                                   │   merging
  │                                   │     │
  │                                   │     ├── claude /gh-pr-merge 성공
  │                                   │     ▼
  │                                   │   tearing-down
  │                                   │     │
  │                                   │     ├── gwt teardown 성공
  │                                   │     ▼
  │                                   │    done ✓
  │                                   │
  │                                   ├── 리뷰 코멘트 존재 AND !reply.done
  │                                   │     ▼
  │                                   │   replying
  │                                   │     │
  │                                   │     ├── claude /gh-pr-reply 성공
  │                                   │     │   + reply.done 파일 생성
  │                                   │     ▼
  │                                   └─ polling ──┘
  │
  └── 어느 단계든 실패 → state=failed:<step>, exit (worktree 보존)
```

### 5.2 N개 병렬 타임라인

```
t=0       gh-flow 13 42 88  (사용자 한 커맨드)
          └─ fork 3개 후 즉시 return (사용자 쉘 프롬프트 복귀)

t=0..2m   worker-13, worker-42, worker-88 각각 독립적으로:
          - gwt spawn
          - claude /gh-issue-flow (~60-120초)

t=2m..?   각자 polling 루프 진입. PR 번호 확보 완료.

t=2m..    리뷰어가 각 PR에 개별 페이스로 리뷰/코멘트/승인
          - #13은 리뷰 코멘트 → reply → 승인 → merge
          - #42는 코멘트 없이 바로 승인 → merge
          - #88은 승인 느림 → 계속 polling (문제 없음)

각 worker는 완료 시점에 `state=done` 쓰고 worktree 정리 후 종료.
```

## 6. 에러 처리

### 6.1 단계별 실패 정책 — 모두 "해당 worker만 정지, worktree 남김"

| 단계 | 실패 예시 | 처리 |
|------|-----------|------|
| spawning | `gwt spawn` 실패 (디스크 풀 등) | state=failed:spawning, worktree 없음, exit |
| implementing | `/gh-issue-flow` 실패 (커밋 훅, 빌드 등) | state=failed:implementing, worktree 보존 — 사용자가 `cd` 해서 수동 복구 |
| polling | `gh` 명령 실패 (인증 만료 등) | state=failed:polling, worktree 보존 |
| replying | `/gh-pr-reply` 실패 | state=failed:replying, 단 reply.done은 **안** 남김 (재시도 가능성) |
| merging | PR 머지 충돌 | state=failed:merging, worktree 보존 |
| tearing-down | `gwt teardown` 실패 | state=failed:tearing-down (드묾, 수동 정리) |

### 6.2 타 worker 영향 없음
각 worker는 독립 프로세스 + 독립 worktree + 독립 상태 디렉토리. 한 worker의 실패는 다른 worker에 전파 안 됨.

### 6.3 실패 후 재실행

현재 구현은 "단순 재시도" 모델이다 — step-level resume 은 v1 out of scope.

사용자가 실패 후 `gh-flow 13` 재실행:
- `state=done` → "already done, skipping" 메시지 후 종료.
- `state=<in-progress-state>`:
  - pid 살아있음 → skip (중복 실행 방지).
  - pid 죽어있음 → 새 worker fork. 아래 `failed:*` 와 동일 동작.
- `state=failed:<step>` → 새 worker fork. **새 worker는 항상 Step 1(gwt spawn)부터 시작**하고, `gwt spawn` 이 자동으로 새 인덱스를 붙여 **새 worktree**(`<proj>-issue-13-2`)를 만든다. 이전 실패한 worktree(`<proj>-issue-13-1`)는 디스크에 그대로 남아 사용자가 수동으로 조사·정리할 수 있다.

#### 후속 개선 (v1 out of scope)
진정한 step-level resume — 예: `implementing` 단계에서 실패했으면 기존 worktree를 재사용해 `/gh-issue-flow`만 재실행 — 은 worker가 시작 시 `state` 와 `worktree.path` 를 읽어 Step 1~2를 건너뛰는 로직이 필요하다. 별도 follow-up.

### 6.4 전역 타임아웃
**명시적으로 없음.** 승인이 영영 안 오면 worker는 영원히 polling. 사용자가 판단해서 `kill <pid>` + 수동 정리. (첫 버전은 이 단순성 유지)

## 7. 파일 레이아웃

### 신규 파일
```
shell-common/functions/gh_flow.sh          # 오케스트레이터 + worker + helper 함수들
shell-common/functions/gh_flow_help.sh     # help 출력 (기존 *_help.sh 컨벤션)
docs/feature/gh-flow-automation/design.md  # 본 문서
```

### 런타임 생성
```
~/.local/state/gh-flow/<repo>/<issue>/{state,worktree.path,pr.number,reply.done,log}
```

### 수정 없음
기존 `gwt`, `/gh-issue-flow`, `/gh-pr-reply`, `/gh-pr-merge`는 변경 없이 그대로 재사용.

## 8. 리스크 / 미해결 사항

1. **`claude -p` 와 slash command 호환성** — `/gh-issue-flow` 같은 slash command가 `claude -p "/gh-issue-flow 13"` 형태로 제대로 호출되는지 실측 필요. 안 되면 스킬 직접 호출 프롬프트로 우회.
2. **pre-commit hook이 interactive prompt를 띄우는 경우** — headless claude에서 block될 수 있음. 첫 실행 시 체크.
3. **리뷰어가 PR 승인 후 다시 코멘트** — reply.done 가 true면 무시하고 그대로 merge 시도. 기획상 의도된 동작(Q4 답변).
4. **PR merge conflict** — 베이스 브랜치와 충돌 시 `/gh-pr-merge`가 실패. worker는 `failed:merging` 상태로 멈춤. 수동 해결.
5. **`gwt spawn` 은 메인 repo에서 실행해야 함** — orchestrator도 메인 repo에서 호출되어야. 선행 체크 필요.

## 9. 명령 레퍼런스 (사용자 용)

```bash
# 기본
gh-flow 13                    # 단일 이슈
gh-flow 13 42 88              # 3개 병렬

# 옵션
gh-flow --help                # 도움말
gh-flow --list                # 현재 실행 중인 worker 목록 + 상태
gh-flow --status 13           # 이슈 #13 worker 상세 상태
gh-flow --kill 13             # 이슈 #13 worker 강제 종료 (worktree는 남김)
gh-flow --tail 13             # 이슈 #13 worker 로그 tail -f
```

주: 첫 릴리스는 기본 + `--help` 만 구현. 나머지는 필요하면 추가.
