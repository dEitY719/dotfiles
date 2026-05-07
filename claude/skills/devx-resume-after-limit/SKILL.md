---
name: devx:resume-after-limit
description: >-
  [Claude Code Only] Companion to /devx:rate-limit-guard. Invoked by the
  scheduled cron when token-limit reset arrives — verifies the worktree/
  branch context recorded by the guard, re-runs the original wrapped
  command idempotently, and clears the state file on success. Use when the
  user runs /devx:resume-after-limit, /devx-resume-after-limit, or when a
  /devx:rate-limit-guard cron prompt fires. Accepts an optional <command>
  argument (cron path) or reads `.claude/.rate-limit-guard.json` (manual
  re-trigger). Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read
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

If present, parse `command`, `worktree`, `branch`, `scheduled_for` (use
`jq` or Python).

### 2. Resolve the Command

Precedence:

1. State file's `command` (most reliable).
2. The `<command>` argument (cron-prompt fallback path).
3. If neither: print `재개할 명령을 알 수 없습니다 (state 파일·인자 모두 없음).` and stop.

### 3. Sanity Check Context

```bash
PWD_NOW=$(pwd); BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
```

- If state file present and `PWD_NOW != worktree`: STOP with
  `❌ 워크트리 불일치 — 예상: <worktree>, 현재: <PWD_NOW>. 올바른 워크트리에서 재시도.`
- If state file present and `BRANCH != branch`: warn but continue —
  `⚠️ 브랜치가 <branch> → <BRANCH>로 이동했습니다 (그래도 진행).`

### 4. Announce

```
🔄 [rate-limit-guard] 재개합니다: <command>
  • 워크트리: <PWD_NOW>
  • 브랜치: <BRANCH>
  • 멱등 실행 — 이미 완료된 sub-step은 자동 스킵됩니다.
```

### 5. Execute the Command

Hand off to the wrapped command. Claude executes it normally in this turn;
the wrapped workflow's own idempotency handles already-done sub-steps.

### 6. Cleanup on Success

In the same turn after the wrapped command finishes successfully:

```bash
rm -f .claude/.rate-limit-guard.json
```

Then print `✅ 재개 완료 — 안전망 상태 파일 정리됨`.

The cron job auto-deleted on fire (it was `recurring: false`), so no
`CronDelete` is needed here.

If the wrapped command fails again (transient or otherwise), **leave the
state file in place** — the user can re-invoke `/devx:resume-after-limit`
manually after fixing the underlying issue.

## Constraints

- Never proceed past Step 3 on worktree mismatch — wrong dir = wrong work.
- Never re-schedule a new cron — that is `/devx:rate-limit-guard`'s job.
- Never delete the state file before the wrapped command succeeds.
- Never invoke from inside another skill — cron- or user-triggered only.
