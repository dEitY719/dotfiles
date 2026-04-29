# gh-pr-approve: status / prune 서브커맨드 설계

**작성일**: 2026-04-29
**상태**: 설계 완료, 구현 대기 (별도 세션에서 진행)
**관련**: `gh-flow status/prune` (이슈 #252 후속 작업), `shell-common/functions/gh_flow.sh`

## 1. 배경

`gh-flow`는 `status` / `prune` 서브커맨드로 worker 상태를 진단하고 state dir을 정리한다.
`gh-pr-approve`는 동일한 fire-and-forget 패턴(`spawn → ai prompt → teardown`)을 쓰지만
진단/정리 도구가 없어, 사용자가 직접 `~/.local/state/gh-pr-approve/<repo>/<pr>/`를 들여다보고
`rm -rf`로 정리해야 한다.

이번 작업은 `gh-flow`의 status/prune 의미론을 `gh-pr-approve`에 미러링한다.
worker 파이프라인이 단발(polling 없음)이므로 verdict matrix가 한층 단순하다.

## 2. 목표 / 비목표

### 목표
- `gh-pr-approve status` (전체 표) / `gh-pr-approve status <N>` (단일 진단) 추가
- `gh-pr-approve prune` (전체 스캔) / `gh-pr-approve prune [--force] <N>...` (scoped) 추가
- 신규 함수는 `_gh_flow_*` 사촌과 1:1 대응되는 이름으로 통일 (cognitive load 최소화)
- worker 실행 시 사용된 self-PR 플래그를 state dir에 기록해 status에서 표시

### 비목표
- 멀티 repo prune (gh-flow도 단일 repo만 지원)
- `prune --dry-run` (gh-flow에 없음 — 일관성 유지)
- `/gh-pr-approve` 스킬 로직 변경
- approve 결과(LGTM 승인 vs follow-up 이슈) state 기록 — 스킬 레이어 책임
- worker timeout 자동 감지 (현재도 없고 이번 범위 밖)

## 3. CLI 계약

### 3.1 사용법

```bash
gh-pr-approve status [<N>]                  # 전체 표 또는 단일 진단
gh-pr-approve prune [--force] [<N>...]      # 전체 스캔 또는 scoped prune
```

### 3.2 실행 예시

```bash
gh-pr-approve status              # 전체 표 — 누가 돌고 있고 누가 실패했는지
gh-pr-approve status 42           # PR #42 진단 (verdict + next action)
gh-pr-approve prune               # 'done' state 제거, 실패는 힌트만 출력
gh-pr-approve prune --force       # 실패한 worktree까지 자동 gwt teardown
gh-pr-approve prune 42 56         # scoped — pid alive 또는 worktree 존재 시 거부
gh-pr-approve prune --force 42    # scoped + alive pid kill (worktree는 여전히 거부)
```

### 3.3 에러 UX

- 잘못된 PR 번호: `gh-pr-approve <subcmd>: invalid PR number '<arg>'`
- 모르는 플래그: `gh-pr-approve prune: unknown arg '<arg>' (only --force is accepted)`
- worktree 잔존 시 scoped prune: `#<N> worktree exists at <path> — run 'cd <path> && gwt teardown --force' first`
- alive pid + `--force` 미지정: `#<N> worker pid=<P> still alive — pass --force to kill and remove`

## 4. 설계

### 4.1 Orchestrator 분기 추가

`gh_pr_approve()`의 첫 `case`에 두 분기 추가 (gh-flow와 동일 형태):

```sh
case "${1:-}" in
"" | -h | --help | help) gh_pr_approve_help; return 0 ;;
status) shift; _gh_pr_approve_status "$@"; return $? ;;   # NEW
prune)  shift; _gh_pr_approve_prune "$@";  return $? ;;   # NEW
esac
# (기존 spawn 경로는 변경 없음)
```

### 4.2 State directory 변경

기존 파일 그대로 + 신규 1개:

```
~/.local/state/gh-pr-approve/<repo>/<pr>/
├── state          # 기존
├── ai             # 기존
├── pid            # 기존
├── worktree.path  # 기존
├── log / log.prev # 기존
├── usage.jsonl    # 기존
└── flags          # NEW — "--admin-merge --squash" 등, 빈 값이면 파일 미생성
```

`_gh_pr_approve_spawn_worker`에 한 줄 추가:
```sh
[ -n "$_self_args" ] && printf '%s\n' "$_self_args" >"$_dir/flags"
```

**의도적 비대칭** (gh-flow와의):
- gh-flow `pr.number`에 해당하는 파일 없음 — dir 이름이 곧 PR 번호.
  → `_gh_pr_approve_pr_state()`는 `basename "$_dir"`로 PR 번호를 추출.

### 4.3 Verdict matrix

`_gh_pr_approve_verdict <pr>` — issue dir의 state/pid/worktree를 읽어
`<verdict>\n<next-action>` 두 줄을 출력. gh-flow와 동일 contract, 매트릭스만 단순:

| state | pid | worktree | verdict | next action |
|---|---|---|---|---|
| `done` | — | — | `done — safe to prune` | `gh-pr-approve prune <N>` |
| `spawning` / `approving` / `tearing-down` | alive | — | `active worker (<state>) — leave alone` | `(none — still working)` |
| `spawning` / `approving` / `tearing-down` | dead | — | `dead worker mid-step (<state>)` | `gh-pr-approve prune <N>` |
| `failed:*` | — | present | `dead failure, worktree alive` | `cd <wt> && gwt teardown --force, then gh-pr-approve prune <N>` |
| `failed:*` | — | absent/none | `dead failure — state-only cleanup` | `gh-pr-approve prune <N>` |
| (no dir) | — | — | `no state — PR not tracked` | `(none)` |
| 그 외 | — | — | `unknown state (<state>)` | `inspect <dir>` |

polling/reply 분기는 모두 제거 — gh-pr-approve worker엔 그런 단계가 없다.

### 4.4 Informational PR state (단일 진단)

verdict와 별개로, `status <N>` 출력 표에 한 줄 추가 (Q1 옵션 B):

```
PR  #42 (OPEN, review: APPROVED, 2026-04-29)
```

`gh pr view <N> --json state,reviewDecision,mergedAt,closedAt` 한 번 호출.
실패 시 `(unreachable — gh CLI failed)`로 표기, **verdict 로직엔 영향 없음**.

### 4.5 Subcommand 동작 명세

#### `gh-pr-approve status` — 전체 표
`ux_table_header "PR" "STATE" "PID / WORKTREE"` 헤더 + 각 PR 한 행. gh-flow status 미러.

#### `gh-pr-approve status <N>` — 단일 진단
gh-flow와 동일 레이아웃에 `PR` (informational), `Flags` (신규) 행 추가:

```
gh-pr-approve status #42 - <repo>
  State        approving
  Worker       pid=12345 (alive, 02:14)
  PR           #42 (OPEN, review: APPROVED)
  Worktree     /path/to/wt (present)
  Flags        --admin-merge --squash
  Last log     2026-04-29 14:32

  --- tail -5 /path/.../log ---
  ...
  ---

  Verdict      active worker (approving) — leave alone
  Next action  (none — still working)
```

`flags` 파일이 없으면 `Flags  (none)`.

#### `gh-pr-approve prune` — 전체 스캔
- `state == done` → `rm -rf <entry>`
- `state == failed:*`:
  - `--force` AND worktree present → `cd <wt> && gwt teardown --force`, 성공 시 state 제거
  - 그 외 → `gwt teardown --force` 힌트 출력, state 보존
- 다른 state는 손대지 않음 (active worker일 가능성)

#### `gh-pr-approve prune <N>...` — scoped
순서대로 검사:
1. dir 부재 → `#<N> no state to prune` warning, continue
2. worktree 존재 → **항상 거부** (force여도) — `gwt teardown` 책임
3. pid alive AND `--force` 미지정 → 거부
4. pid alive AND `--force` → `kill -TERM` (1초 sleep) → 안 죽으면 `kill -KILL` → state 제거
5. pid dead → state 제거

종료 코드: 거부 1건이라도 있으면 `1`, 아니면 `0`.

### 4.6 Flag parsing

gh-flow `_gh_flow_prune` 단일-패스 파서를 그대로 차용:
- `--force | -f` 인식
- `--`로 flag 종료
- 알 수 없는 `-X`는 에러
- `#` prefix PR 번호 허용 (`'#42'` → `42`)

### 4.7 Help text 변경

`gh_pr_approve_help`에 다음 라인 추가 (gh-flow help의 status/prune 라인을 1:1 미러):

**Usage 블록**:
```
gh-pr-approve status [<N>]            full table, or per-PR diagnostic
gh-pr-approve prune [--force] [<N>...] clean 'done' state, or scoped per-PR prune
```

**Examples 블록**:
```
gh-pr-approve status              # full table — who's still running, who failed
gh-pr-approve status 42           # per-PR diagnostic (verdict + next action)
gh-pr-approve prune               # remove 'done' state dirs; print hints for failures
gh-pr-approve prune --force       # also gwt teardown failed worktrees
gh-pr-approve prune 42 56         # scoped — refuses if pid alive or worktree present
gh-pr-approve prune --force 42    # scoped + kill alive pid (worktree still rejected)
```

**State directory 블록**:
- `flags         - launch flags (--self-record, --admin-merge, etc.)` 라인 추가

**Failure isolation 블록**:
- `Distinct failure states: failed:spawning, failed:approving, failed:tearing-down.` 라인 추가

## 5. 신규/변경 함수 요약

### 신규 함수

| 함수 | 역할 | gh-flow 대응 |
|---|---|---|
| `_gh_pr_approve_pr_state` | PR state/reviewDecision 조회 (informational) | `_gh_flow_pr_state` (단순화) |
| `_gh_pr_approve_verdict` | verdict + next-action 두 줄 출력 | `_gh_flow_verdict` (matrix 축소) |
| `_gh_pr_approve_status` | dispatcher (no-arg vs single PR) | `_gh_flow_status` |
| `_gh_pr_approve_status_single` | 단일 PR 진단 표 + tail 5 + verdict | `_gh_flow_status_single` |
| `_gh_pr_approve_prune` | dispatcher (full-scan vs scoped) + flag parsing | `_gh_flow_prune` |
| `_gh_pr_approve_prune_scoped` | scoped prune 본체 | `_gh_flow_prune_scoped` |

### 기존 함수 변경

- `gh_pr_approve` orchestrator: `case "${1:-}"`에 `status` / `prune` 분기 2줄 추가
- `_gh_pr_approve_spawn_worker`: `_self_args` 비어있지 않으면 `<dir>/flags`에 기록 (1줄)
- `gh_pr_approve_help`: 위 4.7의 라인 추가

## 6. 테스트 계획

shell-common이 BATS 같은 정식 테스트 프레임워크를 도입하지 않은 상태이므로,
manual scenario 표를 기준으로 검증한다 (구현 PR에 체크리스트로 첨부):

| # | 시나리오 | 기대 동작 |
|---|---|---|
| 1 | 정상 worker 진행 중 | `status`에 `approving (alive)`, `prune <N>` 거부, 완료 후 `prune` 통과 |
| 2 | 죽은 worker (외부 kill) | `status`에 `(dead)`, `prune --force <N>` 통과 (worktree 없을 때) |
| 3 | `failed:approving` + worktree 잔존 | `prune` 힌트 출력, `prune --force` 자동 teardown |
| 4 | PR 외부 closed/merged | `status <N>`에 informational로 표시, verdict는 worker state만 반영 |
| 5 | `gh-pr-approve prune 42 abc` | `abc` invalid 거부, `42`만 처리 |
| 6 | `--admin-merge --squash`로 spawn 후 status | `Flags  --admin-merge --squash` 표시 |
| 7 | scoped prune이 worktree 존재 PR 거부 | `force`여도 거부, gwt teardown 안내 |

자동 검증 (pre-commit):
- `pipe_loop_check.sh` — heredoc 패턴 강제 (auto-memory: subshell tracing trap 회피)
- `zsh_emulation_check.sh` — `emulate -L sh` 누락 차단

## 7. 리스크 / 미해결

1. **`gh pr view` 호출 비용** — 단일 진단에서 매번 1회 호출. PR 수가 많은 repo에서 status 단독 호출 시 누적 latency가 우려되지만, status 무인자(전체 표)는 PR state를 호출하지 않으므로 영향 제한적.
2. **scoped prune이 worktree를 항상 거부**하는 정책 — 사용자가 `--force --force` 같은 추가 escape를 원할지 미정. 현 정책은 gh-flow와 일관, 추후 피드백으로 완화 가능.
3. **flags 파일 forward compatibility** — 향후 self-PR 옵션이 늘면 `flags` 파일에 빈 줄/공백이 생길 수 있음. status 출력 시 trim 처리 필요.

## 8. 구현 파일

- 수정: `shell-common/functions/gh_pr_approve.sh`
- 참고: `shell-common/functions/gh_flow.sh` (1:1 mirror 대상)
- 문서: 본 design.md
