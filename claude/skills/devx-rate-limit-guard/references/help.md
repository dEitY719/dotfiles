# devx:rate-limit-guard — Help

## Usage

```
/devx:rate-limit-guard --reset HH:MM [--buffer M] <command>
/devx-rate-limit-guard --reset 18:00 /gh-issue-flow 399
/devx:rate-limit-guard -h            # show this help
/devx:rate-limit-guard --help        # show this help
/devx:rate-limit-guard help          # show this help
```

## Examples

```
# Wrap /gh-issue-flow 399, fire safety net at 18:05
/devx:rate-limit-guard --reset 18:00 /gh-issue-flow 399

# Custom buffer (10 min after reset)
/devx:rate-limit-guard --reset 18:00 --buffer 10 /gh-issue-flow 399

# Wrap a natural-language task
/devx:rate-limit-guard --reset 18:00 "PR 200 리뷰 코멘트 처리해"
```

## What it does

Wraps a long-running task with a rate-limit safety net so work resumes
automatically when your token limit resets, even if you walked away.

1. Schedules a `CronCreate(durable=true)` for `<reset + buffer>` whose
   prompt re-runs the wrapped command (with worktree/branch context).
2. Persists state to `.claude/.rate-limit-guard.json` (per worktree).
3. Runs the wrapped command in the current session.
4. On normal completion, removes the cron job and state file.
5. If rate limit hits mid-task, the cron fires later in the (still-idle)
   REPL — or in the next session if you reopen Claude Code in this
   worktree (durable jobs persist via `.claude/scheduled_tasks.json`).

## Prerequisites

- Run `/usage` first to learn your reset time
  (e.g. `Resets 6pm (Asia/Seoul)` → use `--reset 18:00`).
- Pass `--reset` in 24h local format.
- Keep this worktree's Claude Code session open (or reopen Claude Code in
  this worktree) — the durable cron only fires while the REPL is idle.

## When to invoke

- Long workflows you might rate-limit during (`/gh-issue-flow`, `/loop`).
- Leaving for the day with work still queued and wanting auto-resume.
- Any task you'd otherwise have to manually retrigger 2-3 hours later.

## Constraints

- Claude Code only — `CronCreate` is not available on Codex/Gemini CLIs.
- The worktree's Claude Code session must be open or be reopened in this
  worktree for the cron to fire.
- The wrapped command must be reasonably idempotent — re-running should
  detect and skip already-completed sub-steps (e.g. `/gh-issue-flow` will
  not re-create an existing PR or duplicate a commit).
- Default buffer is 5 minutes after reset; tune with `--buffer`.
- Cleanup runs only on definitive success — transient errors leave the
  safety net in place so it can still fire.

## Pairs with

- `/devx:resume-after-limit` — planned companion skill that the cron
  prompt prefers when present. Verifies worktree/branch sanity, then
  re-runs the original command. The cron prompt is self-contained, so it
  also works before this companion skill is built.
- `/devx:restart` — same-session recovery for non-rate-limit API flakes
  (socket disconnect, OOM). Different problem; not a substitute.
- `/devx:schedule` — generic deferred execution; this skill is a
  specialization for the rate-limit case with cleanup semantics.
