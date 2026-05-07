# devx:resume-after-limit — Help

## Usage

```
/devx:resume-after-limit              # read state file, resume
/devx:resume-after-limit <command>    # explicit override (cron path)
/devx:resume-after-limit -h           # show this help
/devx:resume-after-limit --help
/devx:resume-after-limit help
```

## What it does

Companion to `/devx:rate-limit-guard`. When the scheduled cron fires after
the rate-limit reset, this skill:

1. Reads `.claude/.rate-limit-guard.json` to recover the original command
   and the worktree/branch the guard was registered in.
2. Verifies `pwd` matches the recorded worktree (STOPS on mismatch).
3. Warns but continues if the branch has moved.
4. Announces the resume to the user.
5. Re-runs the original command — relying on its idempotency to skip
   already-completed sub-steps.
6. On success, deletes the state file. (The cron itself auto-deleted on
   fire because it was `recurring: false`.)

## When to invoke

- **Automatically**: by the cron prompt scheduled by `/devx:rate-limit-guard`
  when token-limit reset arrives.
- **Manually**: if Claude was closed when the cron should have fired and
  you want to trigger the same recovery flow yourself in the worktree.

## Prerequisites

- Run from inside the same git worktree where `/devx:rate-limit-guard`
  was originally invoked.
- `.claude/.rate-limit-guard.json` exists (auto-created by the guard).
  Without it, the only fallback is an explicit `<command>` argument.

## Constraints

- Stops on worktree mismatch — wrong directory = wrong work.
- Branch movement triggers a warning but does not stop execution
  (you may have rebased or moved HEAD between guard-time and resume-time).
- Never re-schedules a new cron — that is the guard's job.
- The wrapped command must be idempotent (`/gh-issue-flow` etc. are).
- On a second failure (resume itself fails), the state file is preserved
  so you can re-invoke this skill manually after fixing the issue.

## Pairs with

- `/devx:rate-limit-guard` — the scheduler that creates the state and cron
  this skill consumes.
- `/devx:restart` — same-session API-flake recovery (socket disconnect,
  OOM). Different problem; not a substitute.
