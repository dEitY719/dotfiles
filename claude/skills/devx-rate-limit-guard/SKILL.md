---
name: devx:rate-limit-guard
description: >-
  [Claude Code Only] Wrap a long-running command with a rate-limit safety net.
  Schedules a `CronCreate(durable=true)` that fires at the user-supplied reset
  time, runs the wrapped command, and clears the safety net on successful
  completion. Use when the user runs /devx:rate-limit-guard,
  /devx-rate-limit-guard, or asks "rate limit 걸려도 자동 재개", "퇴근하면서
  작업 시키고 limit 풀리면 이어가게 해줘", "auto-resume after my token limit
  resets". Supports multi-cycle re-arming via `--max-cycles N`. Requires the
  user to know their reset time (run /usage first). Accepts `-h`/`--help`/`help`
  to print usage.
allowed-tools: Bash, Read, Write, CronCreate, CronDelete
---

# devx:rate-limit-guard — Rate-Limit Resume Safety Net

> **Claude Code only**. Requires this worktree's Claude Code session to stay
> open (or be reopened in this worktree) so the durable cron can fire.

If arg #1 is `-h`/`--help`/`help`, or when you need usage/examples, print `references/help.md` verbatim and stop.

## Steps

### 1. Parse Arguments

Extract `--reset HH:MM` (required), `--max-cycles` (positive int, default 1),
`--cycle-window` (positive int, default 305). If `--buffer` is present, emit
`⚠️ --buffer 폐지됨 (5분 마진 = 상수). 값 무시.` and continue. Remaining tokens
are the wrapped command (preserve quoting). On missing/malformed `--reset`:
`필수 인자 --reset HH:MM 누락. /usage로 리셋 시각 확인 후 재시도.` and stop.

### 2. Compute First-Fire Time + Capture Context

```bash
python3 claude/skills/devx-rate-limit-guard/references/compute-fire-time.py HH MM 5
PWD_NOW=$(pwd); BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
```

`5` is the hardcoded margin (formerly `--buffer`). Output:
`<min> <hour> <dom> <month> <iso>` (first four = cron expression).

### 3. Schedule via `CronCreate`

- `cron`: `"<min> <hour> <dom> <month> *"` (from step 2)
- `prompt`: see `references/cron-prompt-template.md` — substitute
  `<PWD_NOW>`, `<BRANCH>`, `<command>` and pass verbatim
- `recurring`: `false`, `durable`: `true`

Save the returned job ID.

### 4. Persist Cleanup State

Write `.claude/.rate-limit-guard.json` (worktree root):

```json
{"cron_id":"<id>","command":"<command>","worktree":"<PWD_NOW>","branch":"<BRANCH>","scheduled_for":"<ISO>","max_cycles":<N>,"cycles_remaining":<N>,"cycle_window_min":<M>}
```

`cycles_remaining` starts at `max_cycles`; `/devx:resume-after-limit`
decrements it as it re-arms subsequent cycles.

### 5. Confirm

```
🛡️ Rate-limit 안전망 등록 (사이클 1/<N>, 간격 <M>분)
  • 원본 명령: <command>
  • 자동 재개 시각: <HH:MM + 5min> (job: <id>)
이제 원본 명령을 실행합니다 ↓
```

### 6. Execute, then Cleanup on Success

Hand off to the wrapped command. On success:
`CronDelete(<id>)` → `rm -f .claude/.rate-limit-guard.json` →
`✅ 안전망 해제 — 정상 완료`.

On transient errors (rate limit / network / timeout), **leave the cron in
place** — that is exactly when the safety net should fire.

## Constraints

- Never schedule without explicit `--reset HH:MM`.
- Never use `recurring: true` or `durable: false`.
- Never auto-cleanup on transient errors.
- Never invoke from inside another skill — user-triggered only.
- `--max-cycles 1` (default) preserves PR #369 behavior.
