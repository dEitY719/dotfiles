---
name: devx:resume-after-limit
description: >-
  [Claude Code Only] Companion to /devx:rate-limit-guard. Invoked by the
  scheduled cron when token-limit reset arrives — verifies the worktree/
  branch context recorded by the guard, pre-emptively re-arms the next cron
  for multi-cycle runs (`--max-cycles N` > 1), re-runs the original wrapped
  command idempotently, and clears state on success. Use when the user runs
  /devx:resume-after-limit, /devx-resume-after-limit, or when a
  /devx:rate-limit-guard cron prompt fires. Accepts an optional <command>
  argument (cron path) or reads `.claude/.rate-limit-guard.json` (manual
  re-trigger). Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Write, CronCreate, CronDelete
---

# devx:resume-after-limit — Resume After Rate-Limit Reset

> **Claude Code only**. Companion to `/devx:rate-limit-guard`. Triggered by
> that skill's scheduled cron, or invoked manually in the same worktree.

If arg #1 is `-h`/`--help`/`help`, print `references/help.md` verbatim and stop.

## Usage

```
/devx:resume-after-limit                # read state file, resume
/devx:resume-after-limit <command>      # explicit override (cron path)
```

## Steps

### 1. Load State

```bash
test -f .claude/.rate-limit-guard.json && cat .claude/.rate-limit-guard.json
```

Parse `command`, `worktree`, `branch`, `max_cycles`, `cycles_remaining`,
`cycle_window_min` (jq or Python). Missing multi-cycle fields default to
`max_cycles=1`, `cycles_remaining=1`, `cycle_window_min=305` (PR #369 compat).

### 2. Resolve the Command

State file's `command` → `<command>` arg → stop with
`재개할 명령을 알 수 없습니다 (state 파일·인자 모두 없음).`

### 3. Sanity Check Context

```bash
PWD_NOW=$(pwd); BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
```

- If `PWD_NOW != worktree`: STOP —
  `❌ 워크트리 불일치 — 예상: <worktree>, 현재: <PWD_NOW>.`
- If `BRANCH != branch`: warn `⚠️ 브랜치 이동` and continue.

### 4. Pre-emptive Re-arm

If `cycles_remaining > 1`, register the next cycle's cron **before** running
the wrapped command per `references/preemptive-rearm.md` (fire-time
arithmetic, `CronCreate` args, state-file rewrite). Save `<NEXT_ID>` for
Step 7. Otherwise skip.

### 5. Announce

```
🔄 [rate-limit-guard] 재개: <command>
  • 워크트리: <PWD_NOW>  • 브랜치: <BRANCH>
  • 사이클: <max_cycles - cycles_remaining + 1>/<max_cycles>
  • 멱등 실행 — 이미 완료된 sub-step은 스킵.
```

### 6. Execute the Command

Hand off to the wrapped command. The wrapped workflow's own idempotency
handles already-done sub-steps.

### 7. Cleanup on Success

In the same turn after success:

```bash
[ -n "$NEXT_ID" ] && CronDelete <NEXT_ID>   # only if Step 4 ran
rm -f .claude/.rate-limit-guard.json
```

Print `✅ 재개 완료 — 안전망 상태 파일 정리됨`.

The just-fired cron auto-deleted (`recurring: false`); the next-cycle cron
from Step 4 must be explicitly cancelled.

On failure (transient or otherwise), **leave state + next cron** in place —
the next fire re-triggers this skill, or the user re-invokes manually.

## Constraints

- Never proceed past Step 3 on worktree mismatch — wrong dir = wrong work.
- Never delete state or the next cron before the wrapped command succeeds.
- Never invoke from inside another skill — cron- or user-triggered only.
