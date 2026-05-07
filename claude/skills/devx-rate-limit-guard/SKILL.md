---
name: devx:rate-limit-guard
description: >-
  [Claude Code Only] Wrap a long-running command with a rate-limit safety net.
  Schedules a `CronCreate(durable=true)` that fires at the user-supplied reset
  time, runs the wrapped command, and clears the safety net on successful
  completion. Use when the user runs /devx:rate-limit-guard,
  /devx-rate-limit-guard, or asks "rate limit 걸려도 자동 재개", "퇴근하면서
  작업 시키고 limit 풀리면 이어가게 해줘", "auto-resume after my token limit
  resets". Requires the user to know their reset time (run /usage first).
  Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Write, CronCreate, CronDelete
---

# devx:rate-limit-guard — Rate-Limit Resume Safety Net

> **Claude Code only**. Requires this worktree's Claude Code session to stay
> open (or be reopened in this worktree) so the durable cron can fire.

If arg #1 is `-h`/`--help`/`help`, print `references/help.md` verbatim and stop.

## Usage

```
/devx:rate-limit-guard --reset HH:MM [--buffer M] <command>
```

- `--reset HH:MM` — local 24h reset time (REQUIRED, from `/usage`)
- `--buffer M` — minutes after reset to fire (default: 5)
- `<command>` — slash-command or natural-language task to wrap

## Steps

### 1. Parse Arguments

Extract `--reset HH:MM` (required) and `--buffer M` (default 5). Everything
after flags is the wrapped command (preserve quoting). If `--reset` is
missing/malformed, print
`필수 인자 --reset HH:MM 누락. /usage로 리셋 시각 확인 후 재시도.` and stop.

### 2. Compute Fire Time

```bash
python3 claude/skills/devx-rate-limit-guard/references/compute-fire-time.py HH MM B
```

Output: `<min> <hour> <dom> <month> <iso>` — first four = cron expression, `<iso>` = state-file timestamp.

### 3. Capture Worktree Context

```bash
PWD_NOW=$(pwd); BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
```

### 4. Schedule via `CronCreate`

- `cron`: `"<min> <hour> <dom> <month> *"` (from step 2)
- `prompt`: see `references/cron-prompt-template.md` — substitute
  `<PWD_NOW>`, `<BRANCH>`, `<command>` and pass verbatim
- `recurring`: `false`, `durable`: `true`

Save the returned job ID.

### 5. Persist Cleanup State

Write `.claude/.rate-limit-guard.json` (worktree root):

```json
{"cron_id":"<id>","command":"<command>","worktree":"<PWD_NOW>","branch":"<BRANCH>","scheduled_for":"<ISO>"}
```

### 6. Confirm

```
🛡️ Rate-limit 안전망 등록
  • 원본 명령: <command>
  • 자동 재개 시각: <HH:MM + buffer> (job: <id>)
  • 정상 완료 시 자동 해제됩니다.
이제 원본 명령을 실행합니다 ↓
```

### 7. Execute, then Cleanup on Success

Hand off to the wrapped command. After it finishes successfully, in the same turn:
`CronDelete(<id>)` → `rm -f .claude/.rate-limit-guard.json` →
print `✅ 안전망 해제 — 정상 완료`.

On transient errors (rate limit, network, timeout), **leave the cron in
place** — that is exactly when the safety net should fire. Only clean up
on definitive success or explicit user request.

## Constraints

- Never schedule without explicit `--reset HH:MM`.
- Never use `recurring: true` or `durable: false`.
- Never auto-cleanup on rate-limit / network / timeout errors.
- Never invoke from inside another skill — user-triggered only.
