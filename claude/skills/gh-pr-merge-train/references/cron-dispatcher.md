# gh:pr-merge-train — The cron dispatcher (D-8, NF-1)

```
cron -> shell-common/tools/custom/pr_merge_train_cron.sh   (thin dispatcher, 1 tick)
          |- 1. flock                    — one tick at a time
          |- 2. herdr agent get pmt-…    — is a train from a previous tick still live
          |- 3. gh pr list --author @me  — is there anything worth waking a session for
          `- 4. herdr workspace -> tab -> claude -> /gh-pr-merge-train <owner/repo>
```

Register it with something like:

```
*/15 * * * * /path/to/pr_merge_train_cron.sh --cwd ~/dotfiles >> ~/.local/state/pr-merge-train/cron.log 2>&1
```

`--dry-run` reports what a tick would launch without taking the lock or opening
a pane.

## Why the train runs inside a claude session, not in the shell

This is the one structural difference from `issue_watcher_cron.sh`, and it is
deliberate.

The issue watcher's dispatches are **independent and parallel**: it opens a
pane per issue, hands each one a prompt, and never needs to know how any of
them ended. Fire-and-forget is sound there, so the whole cycle can live in
shell.

A merge train is **serial, and every step depends on the previous one having
completed**. If the shell fired the steps off, the ordering that D-2 and D-3
exist to create would be destroyed. To keep it, one process must hold the
entire run — and that process needs an LLM at two points (conflict resolution,
CI repair), so it has to be a claude session.

Hence the split: the shell answers "should a train start right now?", and the
session *is* the train.

## NF-1 needs two layers, and neither one is redundant

The dispatcher's flock covers **ticks** — two cron periods overlapping, or a
manual run racing a scheduled one. It cannot cover the train: the tick is
short-lived (seconds), while the session it spawns runs for many minutes. The
tick that started a train has exited and dropped the lock long before that
train reaches its second PR.

So the second layer asks herdr directly whether the deterministically named
train agent (`pmt-<owner>-<repo>`) is still `working` or `blocked`. Together:
the lock stops a second dispatcher, the agent probe stops a second train.

An `idle` agent means the previous train finished but its pane is still open —
the dispatcher prompts that same pane again rather than stacking a new tab on
the workspace every period.

## What the dispatcher deliberately does not do

- It does **not** implement the routing table, the ordering, the attempt cap or
  the report. Those are this skill's text. A shell reimplementation would be a
  second SSOT that drifts.
- It does **not** write to GitHub. Its only `gh` call is a `pr list` read.
- It does **not** decide which PRs the train works on. Its target count is a
  "worth waking a session?" heuristic; this skill re-derives the real queue,
  and re-applies the quiet-period filter authoritatively (`ordering.md`).

## Failure behaviour

| Failure | Dispatcher's response |
|---|---|
| `gh pr list` fails | end the tick, launch nothing — never merge without knowing state |
| herdr launch fails | end the tick; the next tick retries |
| a train is already live | end the tick quietly (NF-1) |
| zero target PRs | end the tick quietly |

Every one of these is "do nothing and try again next period". A dispatcher that
retried harder would be the thing most likely to produce two trains.
