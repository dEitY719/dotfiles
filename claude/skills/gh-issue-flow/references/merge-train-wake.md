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
  flock + `herdr agent get pmt-…` double-lock — if several `gh:issue-flow`
  sessions finish at the same moment, each would start its own train.
  `pr_merge_train_cron.sh` already implements both locks
  (`claude/skills/gh-pr-merge-train/references/cron-dispatcher.md`); calling
  it, not the skill, reuses that protection for free.
- **Adding `--admin-merge` to the flow** was rejected because this repo has
  `required_approving_review_count=0` (no approval to bypass) and an admin
  bypass would also skip the project-board Status gate — a standing
  exception the issue's NF-2 explicitly rules out.

## The call

```bash
_AICRON="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/aicron.sh"
if [ -x "$_AICRON" ]; then
    "$_AICRON" run merge-train >/dev/null 2>&1 &
else
    printf '[WARN] aicron not found at %s — merge-train dispatcher wake skipped.\n' "$_AICRON" >&2
fi
```

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

**Escape hatch interaction.** `DOTFILES_ROOT_NO_CANONICALIZE=1`
(`_resolve_dotfiles_root_canonical` in `dotfiles_root.sh`) disables tier 1's
canonicalization for a shell that intentionally wants to test a worktree's
own dotfiles. If that variable is set in the shell running Step 2.4.1,
`SHELL_COMMON` stays worktree-scoped and this step wakes the
**worktree-local** `aicron.sh` instead of the live checkout — the exact
outcome this section says is undesirable, since the worktree vanishes once
its PR merges.

## Soft-fail policy (F-2)

This step never stops the chain:

- `aicron.sh` missing at the expected path → one `[WARN]` line, continue.
  This is the only outcome observed synchronously.
- Once launched in the background, this step does not wait for or inspect
  `aicron run merge-train`'s exit code — including the case where the
  dispatcher declines because a train is already `live` per NF-1, which is
  the expected, common case, not a failure. Any real error surfaces only in
  the dispatcher's own state/log (`aicron status merge-train`), not here.

Step 3's report shows one row for this step: `[OK]` (dispatcher launched,
regardless of what it does after that), `[WARN] (aicron.sh missing)` on the
one synchronous failure path above. It never produces a `stopped at` report
— see `references/report-template.md`.
