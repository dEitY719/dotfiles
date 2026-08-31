---
name: gh:pr-reply
description: >-
  Reply individually to every review comment on a GitHub PR — bots included —
  and apply the valid fixes. Use for /gh:pr-reply, /gh-pr-reply, "PR 리뷰 코멘트
  확인하고 수정", "PR 123 코멘트 처리해", "reply to review comments". Per-comment
  replies, not a summary comment.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "review comment evaluation + classification + targeted edits + per-comment reply; moderate analysis, not deep implementation"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr-reply — Address PR Review Comments

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md`, output it
verbatim, then stop. No API calls.

## Role

Process every code-review comment on a PR: judge validity, fix valid ones,
reply to each with the outcome. **Politeness rule** — reviewers (humans and
bots alike) must see an explicit response on every thread. Silent fixes are
not acceptable; silent declines are worse.

## Step 1: Resolve Target PR + Repo

Record `START_TS=$(date +%s)` immediately (elapsed tracking in Step 7).

Read `references/target-resolution.md` and follow it: positional args
`<pr-number> [remote]`, PR-number precedence (never guess "the latest PR"), the
`TARGET_REPO` + `TARGET_HOST` binding (both from the `[remote]`'s URL, never
`gh`'s default-repo heuristic), the fork tradeoff. Every later `gh` call runs as
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"` (#1403, #1407).

## Step 2: Fetch All Review Comments

Read `references/comment-fetching.md` for the three API endpoints, field
extraction, and dedup rule. Fetch all three; filter out already-replied
threads. Bot service notices (quota / rate-limit / outage) follow that
reference's "Bot service notices" section (service-notice classification,
single-line ack in Step 5, counted separately in Step 7).

**Step 2.5 early exit:** if this yields **zero unaddressed threads** after
dedup, first run the `reply-pending` removal block of
`references/reply-pending-label-removal.sh.md` (this exit path is why it lives
there and not inline in Step 6), then print exactly `No unaddressed review
comments — nothing to do.` and **stop**: no Steps 3–7, no ai-metrics, no push.

## Step 3: Evaluate Each Comment

For each unaddressed comment, read the referenced file (`path` at `line`)
and classify as **ACCEPT** / **ACCEPT-PARTIAL** / **DECLINE** / **QUESTION**.
Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules; see `references/reply-templates.md` for the full rubric.

Record each item's origin as `<reviewer>:<severity>:<verdict>` into `ORIGINS`
via `_gh_pr_reply_origin_line` (`references/targeted-rereview.md` § Step 3) —
Steps 6 and 7 both read that stream, because a flat accepted/declined count
cannot tell an unresolved BLOCKER from a declined suggestion (#1616).

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

Keep each fix minimal and scoped — no drive-by refactors. Group related
fixes into themed commits (one per theme, not per comment), e.g.
`fix(review): address X …`. Never `--amend` or `--no-verify`.

## Step 5: Reply to Every Comment

**Non-negotiable. Every comment from Step 2 must receive a reply, including
declined ones and bot comments.** Read `references/reply-templates.md` for
POST command shapes, the four body templates, the long-body fallback, and
the consolidated table reply. Reply in the reviewer's language.

## Step 6: Push the Fix Commits + Sync Board + Clear Labels

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs alongside the reply summary. Set
`PUSHED_FIXES` to the count of new SHAs on the remote branch; no fixes /
skipped push → `PUSHED_FIXES=0`. If `PUSHED_FIXES > 0`, push the PR card
back to `In review` per `references/board-sync-in-review.sh.md` (soft-fail;
no-op when `PUSHED_FIXES == 0`).

Invalidate stale review verdicts per `references/verdict-label-removal.sh.md`
(soft-fail, two independent blocks). Drop `review-blocked`
**unconditionally** — Step 5's reply-all contract is the only precondition,
regardless of `PUSHED_FIXES` or the ACCEPT/DECLINE ratio (#1634). Then,
under `PUSHED_FIXES > 0` only, drop `review-passed` — the reviewed commit is
no longer head — and run the targeted re-review lane in
`references/targeted-rereview.md` as a `review-passed` upgrade path: when
every blocking-severity item of an originally-blocking reviewer is
ACCEPT/ACCEPT-PARTIAL, re-invoke `Skill(gh:pr-review, "--ai <r> --paths
<fixed files> <PR> <remote>")` and let its verdict flow through
`devx_pr_review_all_apply_label`, which re-applies `review-blocked` on a
BLOCKING verdict. Never *add* either label by hand, and never assume a pass
the re-verification did not actually return (NF-2).

Then **unconditionally** run the same removal block Step 2.5 does —
`references/reply-pending-label-removal.sh.md`. Between the two call sites the
label is cleared on every exit short of a crash, which is the point:
`devx:pr-review-all`'s `defer` branch adds it and `gh:pr-merge-train` skips any
PR carrying it, so a label left on wedges the PR out of the train (#1524).

## Step 7: Report

Print the summary table per `references/final-summary.md` (Accepted / Declined /
Answered counts, the per-reviewer/severity breakdown, the targeted re-review
outcome line, commit SHAs, skipped comments, and the lingering
`CHANGES_REQUESTED` nudge). Then post the ai-metrics PR comment per
`references/ai-metrics-comment.sh.md` (soft-fail; skip when `GH_DISABLE_AI_METRICS=1`).

## Constraints

Read `references/constraints.md`. Non-negotiables: never skip a reply (bot
comments included), never promote the card to `Approved` (owned by
`gh:pr-approve`, #1350), never resolve threads programmatically, never
`--amend` / `--no-verify` / force-push, and route label/body edits through
`_gh_pr_edit_safe_*`.

## Related Skills

`gh:pr-review` posts one aggregate second-opinion comment instead of per-comment
replies · `gh:pr-approve` owns the approve / request-changes decision.
