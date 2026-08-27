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
4. **Remediate** with the atom skill the row names, if any. For the `BEHIND`
   and `DIRTY` rows that means the scratch-worktree sequence below, not a bare
   `Skill(...)` call.
5. **Re-query and re-route.** An atom returning success does not prove the PR
   is mergeable now.
6. **Merge** — `Skill(gh:pr-merge, "<N>")`. No strategy argument (D-4).
7. **Record** the outcome and continue.

## Detached scratch worktree (step 4, `BEHIND` / `DIRTY` only)

`gh:issue-flow` opens each PR from the dedicated worktree that implemented the
issue, so that PR's head branch is **already checked out somewhere else** by
the time the train reaches it. `git checkout <head>` in this session would fail
with `fatal: '<branch>' is already used by worktree at '<path>'` — and even
when it succeeded it would trample the branch the operator has open in the
worktree they invoked the train from. So the train never checks the head branch
out at all: it makes a throwaway scratch worktree at that branch's tip, hands
the path to the atom, and deletes it.

Before delegating, with `<head>` = the `headRefName` already in `$STATE`:

```bash
git fetch "$REMOTE" "<head>"
GIT_COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir)
SCRATCH_DIR="${GIT_COMMON_DIR}/pr-merge-train-scratch/pr-<N>"

# Stale-leftover guard: a crashed/killed prior run, or an unresolved conflict
# handoff (see "Teardown — the one exception" below), can leave this same
# path behind. Never blindly wipe it — a leftover rebase-in-progress marker
# means a human may be resolving it by hand right now.
if [ -e "$SCRATCH_DIR" ]; then
    if [ -e "$(git -C "$SCRATCH_DIR" rev-parse --git-path rebase-merge 2>/dev/null)" ] ||
       [ -e "$(git -C "$SCRATCH_DIR" rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
        echo "[SKIPPED] scratch worktree at $SCRATCH_DIR still has an unresolved handoff — resolve manually or remove it, then re-run."
        # skip this PR (F-6) — do not touch $SCRATCH_DIR, do not proceed below.
    else
        git worktree remove --force "$SCRATCH_DIR" 2>/dev/null || rm -rf "$SCRATCH_DIR"
        git worktree prune
    fi
fi

mkdir -p "$(dirname "$SCRATCH_DIR")"
git worktree add --detach "$SCRATCH_DIR" "$REMOTE/<head>"
```

The `fetch` is not optional: this session's checkout has no reason to hold a
current `$REMOTE/<head>` — the branch was pushed from a *different* worktree.
Fetching it explicitly first is what makes `$REMOTE/<head>` below trustworthy:
with the standard clone fetch refspec (`+refs/heads/*:refs/remotes/<remote>/*`,
the default for every `git remote add` / `git clone`) a plain `git fetch
"$REMOTE" "<head>"` updates the remote-tracking ref `$REMOTE/<head>` itself,
not only `FETCH_HEAD` — skipping the fetch is what would leave that ref stale
(or absent) and have the atom force-push a rewind over commits it never saw.

`--path-format=absolute` (git 2.31+) matters here: `--git-common-dir` alone
prints a path **relative to the current working directory** in a plain
repository (`.git`, or `../../.git` two levels down) — only a linked
worktree's own `.git` file happens to store an absolute `gitdir:` target,
which is why a relative `GIT_COMMON_DIR` can look harmless while testing from
this repo's own worktree layout and still break the moment `$SCRATCH_DIR` is
read from a different working directory or a plain non-worktree checkout.

`--detach` is what makes this collide-free: the scratch worktree holds a commit,
not the branch *name*, so it never contests the checkout any other worktree
already owns. `git worktree add` failing is an ordinary remediation failure —
attempt +1 (F-5), and at 3 the PR is `[FAILED]` (F-6). It never ends the run.

Then delegate to the atom the D-1 row named, pointing it at that path:

```
Skill(gh:pr-resolve-outdated, "<N> <remote> --worktree $SCRATCH_DIR")
Skill(gh:pr-resolve-conflict, "<N> <remote> --worktree $SCRATCH_DIR")
```

Pass `<remote>` explicitly even when it is the default `origin` — the atoms
read it as positional 2, and omitting it would leave `--worktree` sitting in
that slot.

The atom runs every git command as `git -C "$SCRATCH_DIR" ...` and pushes with
an explicit refspec (`HEAD:refs/heads/<head>`), because a detached HEAD has no
upstream to infer. That contract is the atoms' own — see their
`references/preflight.md` / `references/rebase-flow.md`.

### Teardown — the one exception

Tear down once the atom returns, in every case **except** one:
`gh:pr-resolve-conflict` stopping at one of its own documented stop points
(`references/conflict-handling.md` → "Stop points" — an ambiguous conflict it
refuses to auto-resolve, or a user-side abort). That stop leaves the tree
**deliberately** conflicted for a human to finish by hand — the atom's own
constraint already forbids it from deleting `--worktree`'s path itself; tearing
it down here, right after, would just relocate the same mistake into the
caller and destroy the exact state the atom promised to leave behind. In that
one case: report `$SCRATCH_DIR` in the `[FAILED]` row instead of removing it,
and skip this PR for the rest of the run — a human resumes it manually
(`git -C "$SCRATCH_DIR" ...`, per the atom's own report) or re-runs the train
once it's resolved and pushed. The stale-leftover guard above is what makes a
later run safe to encounter that surviving path again.

Every other outcome — clean success, a mechanical rebase failure
`gh:pr-resolve-outdated` hands off with (exit 4, no human input taken yet),
or `git worktree add` itself failing — tears down unconditionally:

```bash
git worktree remove --force "$SCRATCH_DIR" ||
  { rm -rf "$SCRATCH_DIR" && git worktree prune; }
```

The failure paths are exactly the ones that would leak otherwise: a PR that
lands `[FAILED]` is retried on the next tick, and a train on a cron schedule
would accumulate one abandoned worktree per tick per stuck PR — each one a
full checkout, and each one still registered in `git worktree list`. Tearing
down only on the happy path is how that starts.

Creating, delegating, and tearing down is **one** remediation round: the round
still costs exactly one attempt, unchanged from the accounting below.

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
| `gh:pr-resolve-*`, or the `git worktree add` that stages it | attempt +1; at 3, `[FAILED]`, next PR |
| `gh:pr-resolve-conflict` stops at a documented stop point (ambiguous conflict, user-side abort) | `[FAILED]` naming `$SCRATCH_DIR` for manual resume; **scratch worktree is NOT removed** ("Teardown — the one exception" above); no further attempts this run; next PR |
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
