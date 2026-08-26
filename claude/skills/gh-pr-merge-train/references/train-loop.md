# gh:pr-merge-train — The per-PR loop (F-2 … F-6)

One PR at a time. Merge it, or give up on it, **before** touching the next one
(F-2). Never two in flight — a parallel train would race its own merges into
each other's base.

## The loop

For each PR `N` in the Step 2 queue order:

1. **Re-query state** (F-3). The previous merge invalidated whatever Step 2
   read. `gh pr view` per `routing-table.md`.
2. **Approval gate** — look this PR's own `baseRefName` up in the per-base
   cache Step 3 built (`approval-gate.md`: read once per *distinct base*, not
   once per run — rulesets are branch-scoped). Gate on and `reviewDecision !=
   APPROVED` → `[SKIPPED] approval required`, next PR. Gate **off** but
   `reviewDecision` non-empty and not `APPROVED` → also `[SKIPPED]`, naming the
   value — see the next section for why that check cannot be skipped.
3. **Route** through the D-1 table.
4. **Remediate** with the atom skill the row names, if any.
5. **Re-query and re-route.** An atom returning success does not prove the PR
   is mergeable now.
6. **Merge** — `Skill(gh:pr-merge, "<N>")`. No strategy argument (D-4).
7. **Record** the outcome and continue.

## Gates `gh:pr-merge` owns — check them here, not by calling it

`gh:pr-merge` has hard stops of its own, and the train reaches them *through*
the F-5 attempt counter. A PR that trips one is refused identically on every
attempt and on every later tick, so it burns three attempts, lands `[FAILED]`,
and stays `[FAILED]` — NF-2 forbids `gh:pr-merge-emergency`, the only thing
that would clear it. **Detect these before delegating and record `[SKIPPED]`
with the specific cause.** Two of them matter here:

| `gh:pr-merge` gate | What the train must do |
|---|---|
| Step 2 `reviewDecision != APPROVED` (non-empty, non-`APPROVED` always stops, regardless of any ruleset) | `[SKIPPED] gh:pr-merge refuses reviewDecision=<value>` — see `approval-gate.md` → "Why the gate being off is not sufficient" |
| Step 2-B project-board approval gate — fail-closed on the projectV2 Status column, so a card outside `Approved` is refused | `[SKIPPED] board status <value> (gh:pr-merge Step 2-B)` |

On a board-configured repo the second one is the common case, not an edge:
`gh:issue-flow` opens PRs whose cards start outside `Approved`, and nothing in
this train moves them. Reporting that as a bare `[FAILED]` tells the reader
nothing they can act on; naming the column tells them exactly what to move.

`GH_PR_MERGE_SKIP_BOARD_CHECK=1` exists and this skill **must not set it**. The
board gate is a repo-level policy decision — `gh:pr-approve` owns the write
side, `docs/.ssot/github-project-board.md` owns the column semantics — and an
unattended loop quietly exporting a bypass is exactly the shape of NF-2's
prohibition: a train deciding, on schedule, to stand outside a control a human
put there. A human who wants the bypass sets it deliberately, once.

## Attempt accounting (F-5)

Keep one counter per PR, starting at 0. Increment it on **each remediation
round** — one round is "call an atom skill, re-query, re-route".

- Counter reaches `3` without the PR reaching a merged state → `[FAILED]`, with
  the last failure as the reason. Move on.
- A failing atom skill still costs an attempt. A no-op atom (`gh:pr-resolve-outdated`
  reporting "already up to date") does too — otherwise a PR that keeps being
  pushed `BEHIND` by the train's own merges could loop forever.

Why 3 and not 1: between two of this train's own merges a PR can legitimately
go `BEHIND` again, so one attempt is genuinely too few. Why not unbounded: a PR
whose conflict cannot be resolved would hold the train forever, and NF-1 means
no second train can come along and make progress instead.

## Polling (`UNKNOWN`, and `UNSTABLE` with checks still running)

Both are "wait, then look again", and both are bounded:

- **3 polls maximum**, roughly 30 seconds apart.
- `UNKNOWN` still `UNKNOWN` after 3 → `[SKIPPED] mergeability still UNKNOWN`.
- Checks still `IN_PROGRESS` after 3 → `[SKIPPED] checks still running`.

A `[SKIPPED]` here is not a failure — the state is simply not knowable yet, and
the **next tick re-evaluates it from scratch**. That is why the ceiling is low:
holding a train session open waiting on a 20-minute CI run costs more than
letting the next cron tick pick the PR up.

Polls are *not* remediation attempts and do not increment the F-5 counter — no
skill was called and nothing was changed.

## Failure handling (F-6) — skip the PR, never the train

| What failed | Consequence |
|---|---|
| `gh:pr-resolve-*` | attempt +1; at 3, `[FAILED]`, next PR |
| `gh:pr-merge` | that PR is `[FAILED]`; next PR |
| approval gate | that PR is `[SKIPPED]`; next PR |
| a `gh:pr-merge` gate detected up front (`reviewDecision`, board status) | that PR is `[SKIPPED]` with the cause named; **no attempt is spent** |
| `gh pr view` on one PR | that PR is `[SKIPPED] state unreadable`; next PR |
| `gh pr list` in Step 2 | **the run ends** — with no queue there is nothing to skip *to*, and merging without knowing state is the one thing this skill must never do |

One stuck PR must never hold the others. That is the whole point of the train
over a hand-run sequence: the human version stops at the first hard PR, and the
easy ones behind it wait for the next time someone has an hour.

## Concurrency and the outer guard

This loop assumes it is the only train on this repo. That is guaranteed by the
dispatcher, not by this skill — see `cron-dispatcher.md` (NF-1). Do not spawn
sub-agents to process PRs in parallel; the serial dependency is the design, not
a limitation to optimise away.
