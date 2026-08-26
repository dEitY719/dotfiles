# gh:issue-flow — Wake the merge-train dispatcher (Step 2.4.1, #1482)

Runs immediately after Step 2.4 (`devx:pr-review-all`) has been dispatched,
whenever Step 2.3 (`gh:pr`) produced a PR — regardless of whether Step 2.4
itself succeeded, soft-failed, or warned. It sits between Step 2.4 and Step
2.5 (`gh:pr-resolve-conflict`).

## Why this exists

Before #1482, the only thing that could start a merge attempt on a fresh PR
was `pr_merge_train_cron.sh` firing on its own schedule (`*/23 * * * *`
originally). A PR finished by `gh:issue-flow` could therefore sit idle for up
to 23 minutes before anything looked at it. This step closes that gap by
calling the same dispatcher script the cron job calls, once, right after the
PR exists — cutting the idle time to effectively zero in the common case.

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
The `${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}` chain
mirrors the SSOT fallback used throughout this skill suite (e.g.
`gh-issue-implement/references/claim.md` Step 3.4). Here it does double duty:
`gh:issue-flow`'s own precondition is a dedicated feature-branch **worktree**,
never the checkout at `$HOME/dotfiles` — but crontab always calls
`$HOME/dotfiles/shell-common/tools/custom/aicron.sh` (see
`crontab -l`), never a worktree path, because a worktree is torn down after
its PR merges while the crontab entry is permanent. Waking the *same*
dispatcher instance cron uses — not a worktree-local copy that may not have
`aicron`'s installed state/manifest, and would vanish with the worktree —
is the correct target, so this step deliberately falls through past any
worktree-scoped `SHELL_COMMON`/`DOTFILES_ROOT` to the live checkout.

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
