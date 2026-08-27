# gh:pr-merge-train — Queue ordering and the quiet period (D-2, D-3, D-6)

## D-2 — clean first, dirty last

Sort key, highest priority first:

| Rank | `mergeStateStatus` |
|---|---|
| 1 | `CLEAN` |
| 2 | `BEHIND` |
| 3 | `UNSTABLE` |
| 4 | `DIRTY` |

Ties break on **ascending PR number**, so the order is stable across ticks and
an older PR never starves behind a newer one at the same rank.

`UNKNOWN` PRs sort with `BEHIND` (rank 2) as a placeholder — the poll in the
loop resolves them to a real status before anything acts on them, and giving
them their own rank would only encode a guess.

### Why dirty last — the non-obvious part

The intuition says "clear the hard one first, while you still have energy".
That is wrong here, and the reason is mechanical:

> **Every merge invalidates every PR still in the queue.** So the LLM work must
> happen as late as possible.

Resolve `DIRTY` first and each subsequent merge can re-conflict it — the same
file, resolved again, against a base that has moved. Resolve it **last** and it
is resolved exactly once, against the **final** base. One expensive operation
instead of N.

The secondary effect is a real benefit too, not just consolation: the cheap PRs
are already merged by the time the train reaches the one that might defeat it.
A train that dies on the last PR still delivered everything ahead of it.

## D-3 — clean up just-in-time, one PR at a time

Do **not** pre-clean the whole queue and then merge down the list. With four
PRs, pre-cleaning costs:

```
rebase #1 #2 #3 #4      (4)
merge  #1  -> #2 #3 #4 are BEHIND again
rebase #2 #3 #4         (3)
merge  #2  -> #3 #4 are BEHIND again
rebase #3 #4            (2)
...
```

Cleaning immediately before each merge costs one rebase per PR — four total,
with none of them thrown away. This is exactly why **F-3's re-query is
mandatory**: the state you read when you built the queue is stale by the time
you reach the second PR, and acting on it would route the PR down the wrong row
of the D-1 table.

Treat the Step 2 queue as an **ordering**, not as a state snapshot.

## D-6 — the 11-minute quiet period

Drop every PR whose `updatedAt` is within `11` minutes of now. The number lives
in exactly one place — `_gh_pr_merge_train_quiet_minutes` in
`shell-common/functions/gh_pr_merge_train.sh` (overridable with
`GH_PR_MERGE_TRAIN_QUIET_MINUTES`) — and the `11` written here is a citation of
it, not a second definition.

This is a condition that only unattended running creates. `gh:issue-flow`
Step 2.4 calls `devx:pr-review-all` with `--defer-reply 4`, which **schedules
`gh:pr-reply` four minutes after the PR is opened**. A train that merges inside
that window merges a PR that has not yet received its review replies or its
`/simplify` fixes — they land on a branch that no longer has anywhere to go.

A human running the train by hand never hit this, because the minutes passed
naturally while they looked at the PRs. Cron has no such pause.

`11 = 4` (the scheduled defer) `+` the reply pass's own runtime `+` slack.

### `reply-pending` — the hard skip; the quiet period is only the backstop

The quiet period is a **time-based proxy** for the question that actually
matters: *has the deferred review-reply pass finished?* Time is a bad proxy. A
reply pass slower than 11 minutes outlives the window, and the train merges a
PR whose replies and `/simplify` fixes are still in flight — which is what
happened to PR #1522 (issue #1524, bug A).

So there is now a real signal, checked **regardless of elapsed time**:

| Signal | Set by | Cleared by |
|---|---|---|
| `reply-pending` label | `devx:pr-review-all` Step 5, `defer` branch | `gh:pr-reply` Step 6, unconditionally |

A PR carrying `reply-pending` is **never** a train target, no matter how long
ago it was updated. The quiet period stays on as the **backstop** for the two
cases the label cannot cover:

1. PRs opened by hand or by another tool, which never got the label at all.
2. A session that died between adding the label and removing it — its PR would
   otherwise be excluded forever, so the label is not allowed to be the only
   gate either. (A stuck label is cleared by hand, or by the next `gh:pr-reply`
   run on that PR.)

### One filter, two callers — not a coincidence

`shell-common/tools/custom/pr_merge_train_cron.sh` and this skill call the
**literal same function**, `_gh_pr_merge_train_filter_targets` in
`shell-common/functions/gh_pr_merge_train.sh` (issue #1524). Before that fix
the dispatcher had the filter as real `jq` and this skill had it as prose, so
the prose half could be — and was — silently skipped by the LLM executing it.
They cannot drift now: there is one implementation.

The two calls still exist for different reasons. The dispatcher answers "is
there anything worth waking a session for", cheaply, before spending a claude
session on a queue that would come out empty. This skill re-runs the filter
**authoritatively**, because minutes pass between that count and the moment
each PR is actually processed, and a PR can be touched — or labelled — again
in between. Same code, later clock.
