# Finalize a merged PR — the post-merge completion sequence (SSOT)

Issue #1707. This file defines **the order and the membership** of everything
`gh:pr-merge` does *after* a PR is actually merged. It is not a second copy of
those steps — each one already has its own SSOT file, listed below — it is the
one place that says *which* steps make up "the merge is finished" and *in what
order*, so the two callers cannot drift apart:

| Caller | When | Report line |
|---|---|---|
| `gh:pr-merge` Steps 4 + 5 | immediately, in the same run that merged the PR | `[OK] PR #<N> merged (<strategy>)` |
| `gh:pr-merge` `--finalize` | later, on a PR the **merge queue** merged with no session watching | `[FINALIZED] #<N> <title>` |

The second entry point exists because of `--auto` (#1707). With a merge queue
active on the base, `gh pr merge --auto` returns success while the PR is still
`OPEN` — GitHub merges it minutes later, server-side, and nothing is running at
that moment to sync the board, post ai-metrics, drop the label or close the
implementation tab. `gh:pr-merge-train`'s Step 0 sweep finds those PRs on a
later tick (`_gh_pr_merge_train_needs_finalize`) and re-enters here.

## The sequence

Run these **in this order**. Every one is soft-fail: the merge already
happened, so nothing here may change an exit status or suppress the report.

| # | Step | SSOT |
|---|---|---|
| 1 | PR card → `Done`, linked Issue cards → `Done` | `references/project-board-sync.md` |
| 2 | herdr idle-tab hint (read-only, one `[INFO]` line) | `references/herdr-tab-notify.sh.md` |
| 3 | drop the now-readerless `review-passed` label | `references/review-passed-cleanup.sh.md` |
| 4 | ai-metrics PR comment (skipped when `GH_DISABLE_AI_METRICS=1`) | `references/ai-metrics-comment.sh.md` |
| 5 | fetch the merge SHA, print the report line | `references/strategy-selection.md` → "Final report format" |
| 6 | post-merge verification dispatch | `SKILL.md` Step 5's staging block, which reads `claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md` |

Step 3 is **last among the writes on purpose**, and that ordering is
load-bearing beyond tidiness: dropping `review-passed` is what makes
`_gh_pr_merge_train_needs_finalize` stop matching this PR. Drop it first and a
sweep interrupted halfway leaves a PR that is neither finalized nor findable.
Drop it after the other writes and an interrupted sweep simply gets picked up
again on the next tick — every step above is idempotent, so a repeat costs
nothing (the board sync is a no-op on an already-`Done` card, the label delete
absorbs its own 404, the tab is already closed, and the PMV dispatch re-runs
its own registry gate).

The one step that is **not** idempotent in that sense is #4: a second
ai-metrics comment would land a second footer on the same PR. Ordering #3 last
bounds the exposure to a sweep that dies between #4 and #3, which is one API
call wide.

## Required bindings

Identical for both entry points; all of them come from Step 1's single remote
URL plus Step 2's `gh pr view` (`references/github-target.md`, #1403 / #1407):

| Variable | Source |
|---|---|
| `PR_NUMBER` | the positional |
| `TARGET_REPO` / `TARGET_HOST` | the resolved remote |
| `HEAD_REF` / `BASE_BRANCH` | `gh pr view --json headRefName,baseRefName` |
| `REMOTE` | the `[remote]` positional, default `origin` |
| `START_TS` | Step 1's `date +%s` |

`START_TS` is the one binding that differs in meaning between the two entry
points. In the immediate path it measures the merge run, which is what the
ai-metrics footer claims. In a `--finalize` pass it measures the sweep, which
is a few seconds and says nothing about the PR — so a `--finalize` run binds
`START_TS` at its own start anyway and lets the footer report that. Inventing a
retroactive duration would be worse than reporting a short one.

## What is NOT in the sequence

- **The pre-flight gates and the merge itself** (`SKILL.md` Steps 2 and 3).
  `--finalize` skips both by construction: the PR is already merged, so there
  is nothing left to gate and nothing left to merge. It verifies exactly one
  thing before running the sequence — that `state == "MERGED"` — and refuses
  otherwise, because every step here is a write that assumes a merge happened.
- **Anything conditional on the strategy.** By the time this runs, the merge
  method is history; only the report line names it.

## The `[QUEUED]` third outcome

When `--auto` was used and the post-merge `gh pr view` still reports
`state == "OPEN"`, the PR was **enqueued, not merged** — none of the six steps
above may run, because the merge they all assume has not happened yet. That is
neither success nor failure in the existing sense; it is a third outcome with
its own report shape (`SKILL.md` Step 3.5):

```
[QUEUED] PR #<N> added to merge queue — not yet merged
  Branch:  <headRefName> → <baseRefName>
  URL:     <pr-url>
```

The PR keeps its `review-passed` label precisely because step 3 did not run,
and that is what a later `gh:pr-merge-train` Step 0 sweep matches on.
