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
dedup, print exactly `No unaddressed review comments — nothing to do.` and
**stop** — do not run Steps 3–7, do not post ai-metrics, do not push.

## Step 3: Evaluate Each Comment

For each unaddressed comment, read the referenced file (`path` at `line`)
and classify as **ACCEPT** / **ACCEPT-PARTIAL** / **DECLINE** / **QUESTION**.
Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules; see `references/reply-templates.md` for the full rubric.

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

Keep each fix minimal and scoped — no drive-by refactors. Group related
fixes into themed commits (one per theme, not per comment), e.g.
`fix(review): address X …`. Never `--amend` or `--no-verify`.

## Step 5: Reply to Every Comment

**Non-negotiable. Every comment from Step 2 must receive a reply, including
declined ones and bot comments.** Read `references/reply-templates.md` for
POST command shapes, the four body templates, the long-body fallback, and
the consolidated table reply. Reply in the reviewer's language.

## Step 6: Push the Fix Commits + Sync Board + Clear `reply-pending`

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs alongside the reply summary. Set
`PUSHED_FIXES` to the count of new SHAs on the remote branch; no fixes /
skipped push → `PUSHED_FIXES=0`. If `PUSHED_FIXES > 0`, push the PR card
back to `In review` per `references/board-sync-in-review.sh.md` (soft-fail;
no-op when `PUSHED_FIXES == 0`).

Then **unconditionally** remove the `reply-pending` label per
`references/reply-pending-label-removal.sh.md` — REST DELETE, 404 absorbed as a
soft-fail. `devx:pr-review-all`'s `defer` branch adds it and
`gh:pr-merge-train` hard-skips any PR carrying it, so leaving it on would wedge
the PR out of the train forever (#1524). An inline-reply run never had the
label; the 404 makes that a safe no-op, so there is no branch to write.

## Step 7: Report

Print the summary table per `references/final-summary.md` (Accepted / Declined /
Answered counts, commit SHAs, skipped comments, and the lingering
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
