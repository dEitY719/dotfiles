# gh:pr-merge-train — Constraints

## Never call `gh:pr-merge-emergency` (NF-2)

Not for a `BLOCKED` PR, not for a missing approval, not "just this once because
the ruleset lookup failed". That skill forces an audit trail — a reason comment
plus a follow-up incident issue — because it is meant for exceptions a human
decided to make. A loop calling it on schedule produces a stream of incident
issues that describe nothing, and trains the reader to ignore them.

An unmergeable PR is `[SKIPPED]` with a reason. A human can then run the
emergency skill deliberately, which is the only way it means anything.

## Never abort the whole train for one PR (F-6)

Any single PR's failure — remediation, merge, unreadable state, blocked by
policy — skips that PR only. The only thing that ends the run is losing the
queue itself (a failed `gh pr list`), because then there is nothing to skip to.

## Never merge without knowing state

A failed `gh pr list` ends the run with an empty report. A failed per-PR
`gh pr view` skips that PR. In no path does the train act on a guess about
mergeability.

## Never process two PRs at once

The serial dependency is the design (D-8): each merge invalidates the rest of
the queue, so a parallel train would be racing its own merges into each other's
base. Do not dispatch sub-agents per PR.

## Never pass a merge strategy

`required_linear_history` forbids merge commits, and rebase is `gh:pr-merge`'s
default, so the train passes no strategy argument at all (D-4). Passing one
explicitly would be a second place for the policy to drift out of sync with the
repo's actual settings.

## Never review, never approve

`gh:issue-flow` Step 2.4 already ran `devx:pr-review-all` on every PR this
train drains. Re-reviewing here would duplicate that work with less context,
and approving is impossible anyway — GitHub forbids approving your own PR, and
`--author @me` means every PR here is yours.

## Never write ai-metrics from the train

Every atom the train calls (`gh:pr-merge`, `gh:pr-resolve-conflict`, …) posts
its own ai-metrics comment where its SSOT says to, each behind its own
`GH_DISABLE_AI_METRICS=1` guard. A train-level comment would land a second
footer on the same PR describing the same work. The train's output is the
Step 5 report, and that goes to the operator (or the cron log), not to GitHub.

Corollary: **this skill makes no writes to GitHub of its own.** Every mutation
it causes happens inside an atom skill that already owns that mutation's rules.

## Never let a PR loop forever

Three remediation attempts per PR (F-5), three polls per wait (train-loop.md).
Both ceilings exist because NF-1 means no second train can come along and make
progress while this one is stuck.

## Never widen the author scope

`--author @me` (D-7). A colleague's PR is out of scope for an unattended merge,
regardless of how mergeable it looks.
