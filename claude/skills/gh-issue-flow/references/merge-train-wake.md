# gh:issue-flow — Wake the merge-train dispatcher (Step 2.4.1, #1482)

Runs immediately after Step 2.4 (`devx:pr-review-all`) has been dispatched,
whenever Step 2.3 (`gh:pr`) produced a PR — regardless of whether Step 2.4
itself succeeded, soft-failed, or warned. It sits between Step 2.4 and Step
2.5 (`gh:pr-resolve-conflict`).

## Why this exists

Before #1482, the only thing that could start a merge attempt on a fresh PR
was `pr_merge_train_cron.sh` firing on its own schedule (`*/23 * * * *`
originally). A PR finished by `gh:issue-flow` could therefore sit idle for up
to 23 minutes before anything looked at it. This step closes part of that gap
by calling the same dispatcher script the cron job calls, once, right after
the PR exists.

**It does not, however, cut the triggering PR's own idle time to zero.** The
dispatcher's target count excludes any PR updated within the last
`_PMT_QUIET_MINUTES` (11 minutes — D-6 quiet period, see
`shell-common/tools/custom/pr_merge_train_cron.sh` →
`_pmt_target_count`, and `gh-pr-merge-train/references/ordering.md` for why
11). The PR this step just created has an `updatedAt` of "just now", so it
fails that filter on this very tick — if no other PR in the queue has already
cleared the quiet period, the wake call ends in "No target PR — nothing to
wake a session for" and the triggering PR is not touched. It only becomes
eligible once its own 11-minute quiet period elapses, and from there the
`*/5 * * * *` cron backstop picks it up within another 5 minutes at most —
so the triggering PR's real idle time is **~11–16 minutes**, not zero.

What this step *does* reliably shorten is the idle time of **other** PRs
already sitting in the queue past their quiet period (the common case when
several `gh:issue-flow` runs are in flight) — those get swept up to 5 minutes
earlier than waiting for the next cron tick would have.

The cron job is not removed. Its backstop period is shortened to `*/5 * * *
*` (`shell-common/tools/custom/cron-jobs.json`) so that a dropped or missed
event trigger — e.g. this step running while a previous train is still
`live` — is still picked up within 5 minutes instead of 23.

## Why the dispatcher, not `gh:pr-merge-train` or `--admin-merge`

Both alternatives were considered and rejected (issue #1482 body, "대안"):

- **Calling `Skill(gh:pr-merge-train)` directly** would bypass NF-1's
  flock + `herdr agent get mt-…` double-lock — if several `gh:issue-flow`
  sessions finish at the same moment, each would start its own train.
  `pr_merge_train_cron.sh` already implements both locks
  (`claude/skills/gh-pr-merge-train/references/cron-dispatcher.md`); calling
  it, not the skill, reuses that protection for free.
- **Adding `--admin-merge` to the flow** was rejected because this repo has
  `required_approving_review_count=0` (no approval to bypass) and an admin
  bypass would also skip the project-board Status gate — a standing
  exception the issue's NF-2 explicitly rules out.

## Guarded to `$HOME/dotfiles`'s own `origin` only (#1498, PR #1539 review)

`pr_merge_train_cron.sh` (the script `aicron run merge-train` launches) only
ever operates on `$HOME/dotfiles`'s own `origin` remote — see "Why the
`$HOME/dotfiles` fallback is intentional" below. Waking it for a PR that
`gh:issue-flow` pushed somewhere the dispatcher can't see nudges a process
that will never find that PR: harmless, but pointless. The call is gated on
whether `<remote>` — the same `[remote]` positional Step 1 resolved
(`references/target-binding.md`) — points at that **same repo**.

Two failure modes were found and closed together, both from PR #1539 review
(agy + codex, independently, both BLOCKER):

- **Don't gate on a re-read of `$REMOTE` from the environment.** An earlier
  draft (dangling commit d3e12471, PR #1489 review) read `${REMOTE:-origin}`
  before Step 1 ever exported it, so the guard was always true. #1498's first
  fix exported `REMOTE` in Step 1 for this to read — but a Bash tool call is
  not guaranteed to inherit a prior call's exports (agy, PR #1539): if the
  export doesn't survive to this call, `${REMOTE:-origin}` silently falls
  back to `origin` and fires anyway — the exact failure this guard exists to
  prevent. **The fix: the executing agent substitutes the literal, already-
  known `<remote>` value into the Bash call it writes for this step — never
  a live `$REMOTE` read.** The agent parsed `[remote]` itself in Step 1; that
  value lives in its own conversational context, not in shell state that can
  reset between tool calls.
- **Don't compare by remote *name* alone.** Comparing `<remote> = "origin"`
  as a string (codex, PR #1539) conflates "named origin" with "is the repo
  the dispatcher watches" — a fork workflow (`origin` = fork, `upstream` =
  canonical) would still wake the wrong train on a same-named-but-different
  remote. The fix: compare the resolved remote's URL against
  `$HOME/dotfiles`'s own `origin` URL, not the two names.

## The call

```bash
_REMOTE="<remote>"   # <- literal value from Step 1's own arg parsing;
                      #    the executing agent substitutes it here — never
                      #    a live `$REMOTE`/`${REMOTE:-origin}` env read.
_MY_URL=$(git remote get-url "$_REMOTE" 2>/dev/null)
_DOTFILES_ORIGIN_URL=$(git -C "$HOME/dotfiles" remote get-url origin 2>/dev/null)
if [ -n "$_MY_URL" ] && [ "$_MY_URL" = "$_DOTFILES_ORIGIN_URL" ]; then
    _AICRON="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/aicron.sh"
    if [ -x "$_AICRON" ]; then
        "$_AICRON" run merge-train >/dev/null 2>&1 &
    else
        printf '[WARN] aicron not found at %s — merge-train dispatcher wake skipped.\n' "$_AICRON" >&2
    fi
fi
```

In the common single-clone dotfiles setup (the session's own worktree shares
its remotes with `$HOME/dotfiles`, and `[remote]` defaults to `origin`),
`$_MY_URL` and `$_DOTFILES_ORIGIN_URL` are the same string, so behavior is
unchanged from the name-based check. The URL comparison only starts to
differ — correctly refusing to fire — on a fork clone or a remote pointed at
a different host/repo than `$HOME/dotfiles`'s own `origin`.

No output on the no-match path — silent skip, matching this skill suite's
convention of staying quiet on an expected, non-error path (e.g.
`gh:issue-implement`'s 3.3b duplicate-PR check). Step 3's report reflects it
as `[SKIP] Step 4.1: merge-train wake  (remote != origin)`
(`references/report-template.md`).

Called by absolute path (mirrors how cron itself invokes `aicron.sh`), not
via the `aicron` shell function/alias — the function is guarded by the
interactive-shell check in `shell-common/functions/aicron.sh` and is not
reliably available in a skill's non-interactive Bash calls.

**Fired in the background, not awaited.** `pr_merge_train_cron.sh` blocks on
`herdr agent prompt --wait --timeout 240000` when it actually launches a
train — up to ~4 minutes, only to confirm the prompt was *accepted*, not that
the train finished. Step 2.5/2.5.1 (the rebase steps right after this one)
don't depend on the train's outcome, so awaiting that confirmation would only
stall the chain for no benefit. The executing agent should launch this call
without waiting for it (harness `run_in_background`, or the trailing `&`
above when run as a plain script) and proceed to Step 2.5 immediately.
One consequence: the dispatcher's own exit code is never observed here —
see "Soft-fail policy" below.

**Why the `$HOME/dotfiles` fallback is intentional, not a portability gap.**
`gh:issue-flow`'s own precondition is a dedicated feature-branch
**worktree**, never the checkout at `$HOME/dotfiles` — but crontab always
calls `$HOME/dotfiles/shell-common/tools/custom/aicron.sh` (see
`crontab -l`), never a worktree path, because a worktree is torn down after
its PR merges while the crontab entry is permanent. Waking the *same*
dispatcher instance cron uses — not a worktree-local copy that may not have
`aicron`'s installed state/manifest, and would vanish with the worktree —
is the correct target. The `${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}`
chain reaches that target in two tiers, not by falling through past a
worktree-scoped value:

1. **`SHELL_COMMON` is already canonical (#589).** An interactive shell that
   started this skill session sourced `bash/main.bash` / `zsh/main.zsh`,
   which calls `_dotfiles_root_canonicalize` (`shell-common/functions/dotfiles_root.sh:110`)
   at loader entry. That function walks a linked worktree back to the main
   worktree via `git rev-parse --git-common-dir` and re-exports both
   `DOTFILES_ROOT` and `SHELL_COMMON` (`dotfiles_root.sh:116`) to the main
   checkout path — the same path crontab uses. So in the common case
   `SHELL_COMMON` is picked first by the `:-` chain and is *already* the
   live checkout; there is no fall-through happening.
2. **`$HOME/dotfiles` is the last-resort tier**, used only when
   `SHELL_COMMON`/`DOTFILES_ROOT` are both unset — a non-interactive
   environment where no loader ran to canonicalize them.

**Caveat on both tiers.** The split above assumes the running shell —
interactive, or a non-interactive agent/automation session — itself sourced
`bash/main.bash` / `zsh/main.zsh`, or inherited its environment from a parent
that did. A shell that instead manually exports `SHELL_COMMON`/`DOTFILES_ROOT`,
or inherits them from a process that never ran the loader, sits outside that
guarantee: tier 1 can pick up a stale or non-canonical `SHELL_COMMON` value,
and tier 2 only fires when both variables are literally unset, not merely
stale. This degrades safely in practice — Step 2.4.1 is a best-effort
background wake, never load-bearing for the flow itself — but the two tiers
above describe the common case, not an invariant.

**Escape hatch interaction.** `DOTFILES_ROOT_NO_CANONICALIZE=1`
(`_resolve_dotfiles_root_canonical` in `dotfiles_root.sh`) disables tier 1's
canonicalization for a shell that intentionally wants to test a worktree's
own dotfiles. If that variable is set in the shell running Step 2.4.1,
`SHELL_COMMON` stays worktree-scoped and this step wakes the
**worktree-local** `aicron.sh` instead of the live checkout — the exact
outcome this section says is undesirable.

## Soft-fail policy (F-2)

This step never stops the chain:

- `<remote>`'s URL doesn't match `$HOME/dotfiles`'s own `origin` URL →
  silent skip, continue. Not a failure — see "Guarded to `$HOME/dotfiles`'s
  own `origin` only" above.
- `aicron.sh` missing at the expected path → one `[WARN]` line, continue.
  This is the only outcome observed synchronously on the `origin` path.
- Once launched in the background, this step does not wait for or inspect
  `aicron run merge-train`'s exit code — including the case where the
  dispatcher declines because a train is already `live` per NF-1, which is
  the expected, common case, not a failure. Any real error surfaces only in
  the dispatcher's own state/log (`aicron status merge-train`), not here.

Step 3's report shows one row for this step: `[OK]` (dispatcher launched,
regardless of what it does after that), `[WARN] (aicron.sh missing)` on the
one synchronous failure path above. It never produces a `stopped at` report
— see `references/report-template.md`.
