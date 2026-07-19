# gh:issue-flow — Post-PR Quality Gate (Step 2.4, delegated)

Runs after Step 2.3 (`gh:pr`) has produced `<PR_NUM>`, before the rebase
steps 2.5 / 2.5.1. The quality gate is no longer inline in issue-flow — it is
performed by a single delegated call to `devx:pr-review-all`, which owns the
gate logic as SSOT. The whole gate stays **soft-fail**: review and simplify
are additive polish, so any failure warns and the chain continues — never
block.

## The delegated call

```
Skill(devx:pr-review-all, "<PR_NUM> <remote> --defer-reply 8")
```

One call replaces the former inline gate (codex ∥ /simplify + commit/push)
AND the former `devx:schedule` pr-reply step. Inside `devx:pr-review-all`:

- **agy ∥ codex ∥ /simplify** run as parallel Agent subagents in one turn.
  agy review is now included (it was missing from the old inline gate).
  Each lane is soft-fail: a missing CLI or transient error skips that lane and
  the others continue.
- **simplify commit + push** happens **synchronously inside** the skill,
  before it returns. It uses an explicit `-m` message (never a bare
  `git commit`, which would hang on the editor in a non-interactive shell).
- **pr-reply is deferred** — `--defer-reply 8` schedules `/gh-pr-reply
  <PR_NUM>` 8 minutes later (was 5 min in the old `devx:schedule` step),
  giving CI and reviewers time to post before the reply pass runs.

## Ordering is preserved

Because the simplify commit + push runs synchronously **inside**
`devx:pr-review-all` before it returns, any simplify changes are already
committed and pushed by the time Step 2.4 completes. The tree is therefore
clean before the rebase steps 2.5 / 2.5.1 run — the same
simplify-commit-before-rebase guarantee the old inline Step 2.3.3 provided.
**A dirty working tree breaks `git rebase`**, so this ordering is load-bearing.

## Soft-fail policy

- codex/agy absent → that lane skips (not a failure).
- simplify no change → no commit (clean tree).
- Any error in review, simplify, the simplify commit/push, or the reply
  scheduling → the delegated skill emits a `[WARN]`/`[SKIP]` line and the
  flow continues to Step 2.5. The gate never stops the flow.
