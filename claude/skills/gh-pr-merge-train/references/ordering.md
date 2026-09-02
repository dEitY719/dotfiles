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

(Invalidation still happens after #1707 — every merge still moves the base. What
changed is its *price*: on a base with strict checks off it costs a `BEHIND` PR
nothing, and it costs a `DIRTY` PR exactly as much as it always did. The
sentence above is about the expensive half, and the expensive half is `DIRTY`.)

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

### The merge queue does not change D-2 or D-3 (#1707)

`--auto` addresses the **merge wait** — the train no longer blocks until each
PR lands, so the platform can batch the builds. D-2 and D-3 are about the cost
of **local remediation**, which the queue does not touch: a `DIRTY` PR still
needs an LLM to resolve real content conflicts, that work is still invalidated
by every merge ahead of it, and it is therefore still done last and
just-in-time. Both reasonings survive intact; they were never about waiting.

### What did move: `BEHIND` costs no local rebase on a relaxed base (#1707)

D-3's arithmetic above counts a rebase per PR per merge. On a base with
`strict_required_status_checks_policy: false` — which `main` now is
(`references/strict-mode-relaxation.md`) — **the `BEHIND` term drops out
entirely**: GitHub rebases server-side at merge time, so a merely-behind PR
never pays a local rebase or a CI cycle, no matter how many merges landed ahead
of it. The row usually stops appearing at all, because GitHub reports such a PR
as `CLEAN`.

So read the "clean up just-in-time" rationale as being about **`DIRTY`** now.
That row is unchanged and unchangeable: an LLM still has to resolve real
content conflicts, that work is still invalidated by every merge ahead of it,
and it is therefore still ordered last (D-2) and done at the last moment (D-3).
No relaxation and no queue resolves a content conflict.

D-2's ordering itself is untouched. `BEHIND` still sorts at rank 2 — it is now
a cheaper rank, not a differently-ordered one, and on a relaxed base the PRs
that would have filled it arrive as `CLEAN` at rank 1 anyway.

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

So there is now a real signal, checked **regardless of the quiet period**:

| Signal | Set by | Cleared by |
|---|---|---|
| `reply-pending` label | `devx:pr-review-all` Step 5, `defer` branch | `gh:pr-reply` Step 6, unconditionally |

A PR carrying `reply-pending` is not a train target however far outside the
11-minute quiet period it sits.

#### Its sibling signal: the verdict labels (#1564)

`reply-pending` answers *when* — has the reply pass finished. It says nothing
about *what the reviewers concluded*. That second question is answered by a
different pair of labels, on a different schedule, in a different step:

| Signal | Set by | Cleared by |
|---|---|---|
| `review-blocked` / `review-passed` | `devx:pr-review-all` Step 3.5 (the only writer) | `_gh_pr_drop_label` on any head advance (#1563); the opposite label on a re-review |

The train reads them in Step 3.5, not here: they are **not** part of
`_gh_pr_merge_train_filter_targets`, because a PR they stop must appear in the
report with a reason rather than vanish before the queue exists. Table,
rationale, and the reason strings: `references/review-verdict-gate.md`. Unlike
`reply-pending`, these labels have **no staleness window** — absence is
already the blocking state, so there is nothing for time to release.

#### The label expires — 90 minutes, then the quiet period takes over

The hard skip is **bounded**, and the bound is what makes the backstop below
real rather than aspirational. The window is
`_gh_pr_merge_train_reply_pending_stale_minutes` — default `90` minutes,
overridable with `GH_PR_MERGE_TRAIN_REPLY_PENDING_STALE_MINUTES`, defined in
the same `shell-common/functions/gh_pr_merge_train.sh` as the quiet period, and
the `90` written here is a citation of it, not a second definition.

Measured against the same `updatedAt` the quiet period reads: adding a label
bumps a PR's `updatedAt`, so that stamp is "when the label landed" at the
earliest — no separate clock is needed.

| `reply-pending` | `updatedAt` age | Verdict |
|---|---|---|
| yes | `< 90 min` | **dropped** — a deferred reply pass is still plausibly running |
| yes | `>= 90 min` | label is **stale**; falls through to the ordinary quiet-period check |
| no | — | ordinary quiet-period check |

`90` is sized as *longer than any healthy deferred reply pass, shorter than a
wedged PR is tolerable*: 4 minutes of scheduled defer + a `devx:pr-review-all`
fan-out + a `gh:pr-reply` pass that on a heavily reviewed PR walks dozens of
threads, edits, commits and pushes — generously an hour — plus slack. It is
~8x the quiet period, so the two windows can never be mistaken for each other.

Without the bound, a label nobody ever removes excludes its PR from the train
**forever** (PR #1545 review, codex BLOCKER). With it, "the remover died"
degrades to "the PR waits out 90 minutes" — at most six 15-minute cron ticks.

So the quiet period stays on as the **backstop** for the two cases the label
cannot cover:

1. PRs opened by hand or by another tool, which never got the label at all.
2. A session that died between adding the label and removing it. Its PR is held
   for the staleness window and then judged by the quiet period like any other
   — the label is not allowed to be the only gate, and it is not allowed to be
   a permanent one. (A stuck label is still cleared by hand, or by the next
   `gh:pr-reply` run on that PR; expiry only stops it from wedging the train.)

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

### Exemption — the train's own just-finished push (#1708)

The quiet period asks "has outside work on this PR settled?", and `updatedAt`
is its proxy for the answer. The proxy breaks when the train is the one that
moved the PR: a Step 4 `BEHIND` / `DIRTY` remediation rebases and pushes the
head, `updatedAt` becomes *now*, and the next queue build drops the PR the
train just finished fixing. The tick after that re-remediates it and drops it
again. Nothing is inbound on such a PR — there is nothing left to wait for.

So a PR the filter dropped **solely** for the quiet period rejoins the queue
when its current `headRefOid` is one this train recorded pushing:

| Function | Where it runs | What it does |
|---|---|---|
| `_gh_pr_merge_train_record_pushed_sha` | `train-loop.md`, right after the remediation's re-query | stamps the head the atom just pushed as this train's own |
| `_gh_pr_merge_train_readmit_own_pushes` | `SKILL.md` Step 2, after the filter | re-admits the PRs whose current head carries that stamp |
| `_gh_pr_merge_train_forget_pushed_sha` | `train-loop.md` step 8, successful merge only | drops the record so the state dir stays bounded |

**`_gh_pr_merge_train_filter_targets` is not touched by any of this.** The
re-admission is a *second, additive pass over the same raw list*, never a new
clause in the shared filter — which is the point: the filter is the one
implementation this skill and the cron dispatcher both run, and the dispatcher
has no business granting an exemption only the authoritative run can even
record. The filter behaves identically for both callers, before and after
#1708.

`reply-pending` **always wins over the exemption** — a PR carrying it is never
re-admitted, however certain the train is that it pushed the head itself,
because the label answers a different question (is a reply pass still
outstanding) that a rebase does nothing to settle. Plain label presence, no
staleness window: expiry belongs to the label's own lifecycle, defined once by
`_gh_pr_merge_train_reply_pending_stale_minutes` above and not re-derived here.
Drafts are likewise never re-admitted — DRAFT is a D-1 skip row, not a
quiet-period drop, so the exemption has nothing to release.

A head that has moved past the recorded sha stops matching, and the quiet
period stands: someone else's commit is on the branch now, which is exactly
the case D-6 exists for.
