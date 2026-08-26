# gh:issue-flow — Wake the merge-train dispatcher (Step 2.4.5)

Runs after Step 2.4 (`devx:pr-review-all`) completes, before the rebase
steps 2.5 / 2.5.1. Issue #1482.

## The call

```bash
aicron run merge-train || true
```

This is the same invocation the merge-train crontab entry runs on its own
schedule (`shell-common/tools/custom/cron-jobs.json`) — `aicron run
merge-train` executes `pr_merge_train_cron.sh --cwd "$HOME/dotfiles"` under
`aicron`'s own logging/locking. Step 2.4.5 does not add a new code path; it
just triggers the existing one early, once, right when a fresh PR is most
likely to be waiting for it.

## Why the dispatcher, never `gh:pr-merge-train` directly

`gh:pr-merge-train`'s NF-1 ("one train per repo") is enforced by
`pr_merge_train_cron.sh` through two layers: a tick-scoped `flock`, and a
`herdr agent get pmt-<host>-<owner>-<repo>` probe that detects whether a
train from a previous tick (or a previous Step 2.4.5 call) is still
`working`/`blocked`. Calling `Skill(gh:pr-merge-train, ...)` straight from
this chain would skip both layers — if two `gh:issue-flow` runs finish their
PRs close together, both could open a second herdr pane on the same train
name and race. Going through `aicron run merge-train` means every call,
whether it comes from cron or from this step, is serialized through the same
lock.

## Why non-fatal, and why it ignores Step 2.4's outcome

- **`|| true`** — `aicron`, `herdr`, or the dispatcher's own preconditions
  (missing `origin` remote, no open target PR, `gh pr list` failure) can all
  fail here. None of that is this chain's problem: merge is not part of what
  `gh:issue-flow` promises, only a faster nudge toward it. A failure here
  degrades exactly to "the 5-minute crontab tick will find this PR anyway" —
  never a reason to stop a chain that already produced a PR.
- **Runs regardless of Step 2.4's own soft-fail state** — Step 2.4 is
  soft-fail by design (`references/quality-gate-step.md`); by the time this
  step runs, Step 2.4 has always "completed" one way or another. Waiting on
  its outcome would gain nothing: `gh:pr-merge-train`'s own 11-minute quiet
  period (D-6, `claude/skills/gh-pr-merge-train/references/ordering.md`)
  already guarantees the PR isn't touched before its deferred `/gh-pr-reply`
  (scheduled 4 minutes out by Step 2.4) has had time to land. This step is
  only a signal to *check*, not a signal to *merge immediately*.

## What this deliberately does not do

- Does not skip or shorten `gh:pr-merge-train`'s D-6 quiet period.
- Does not touch approval or branch-protection gates (`gh:pr-approve`,
  `--admin-merge`) — this repo requires no PR approval
  (`required_approving_review_count = 0`), and nothing here changes that.
- Does not remove the merge-train crontab entry — it stays as the backstop
  that catches a PR whose dispatch call landed while a train was already
  `live` (the dispatcher drops that case silently by design; see
  `claude/skills/gh-pr-merge-train/references/cron-dispatcher.md`). That
  backstop's interval is shortened separately (issue #1482) so the worst-case
  wait after a dropped nudge stays short.
