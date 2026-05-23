---
name: gh:pr-reply
description: >-
  Fetch code review comments on a GitHub PR, evaluate each one, apply valid
  fixes, and leave an individual reply on every comment (Accepted with what
  changed, or Declined with reasoning). Use when the user runs /gh:pr-reply,
  /gh-pr-reply, or asks "PR 리뷰 코멘트 확인하고 수정", "리뷰 답변 달아", "PR 123
  코멘트 처리해". Defaults to the PR for the current branch; accepts an explicit
  PR number as an argument. Every comment MUST get a reply — bot comments
  (gemini, sourcery, copilot) included. Accepts `-h`/`--help`/`help` to
  print usage.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# gh:pr-reply — Address PR Review Comments

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Systematically process every code-review comment on a PR: judge validity,
fix valid ones, and reply to each comment with the outcome. **Politeness
rule** — reviewers (humans and bots alike) must see an explicit response on
every thread. Silent fixes are not acceptable; silent declines are worse.

## Step 1: Resolve Target PR

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 7.

Precedence:
1. **Explicit argument** — `/gh:pr-reply 123` → PR #123.
2. **Current branch auto-detect** — `gh pr view --json number,url,headRefName,baseRefName`; if no PR exists, stop and tell the user.
3. Never guess. Never pick "the latest PR in the repo".

Also capture `TARGET_REPO` via `gh repo view --json nameWithOwner -q .nameWithOwner`
(e.g. `owner/repo`). Use `$TARGET_REPO` consistently in all subsequent API calls.

## Step 2: Fetch All Review Comments

Read `references/comment-fetching.md` for the three API endpoints, field
extraction, and dedup rule. Fetch all three; filter out already-replied
threads. Bot service notices (quota / rate-limit / outage) — whether
posted as review summaries OR as conversation comments — follow the
"Bot service notices" section in the same reference: classify as
service-notice, single-line ack in Step 5, count separately in Step 7.

## Step 2.5: Early Exit — No Unaddressed Comments

If Step 2 yields **zero unaddressed threads** after deduplication:

1. Print exactly one line:
   ```
   No unaddressed review comments — nothing to do.
   ```
2. **Stop immediately.** Do not run Steps 3–7. Do not post an ai-metrics
   comment. Do not push anything.

## Step 3: Evaluate Each Comment

For each unaddressed comment, read the referenced file (`path` at `line`)
and classify as **ACCEPT** / **ACCEPT-PARTIAL** / **DECLINE** / **QUESTION**.
Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules. See `references/reply-templates.md` for the full rubric.

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

Keep each fix minimal and scoped — no drive-by refactors. Group related
fixes into themed commits (one per theme, not one per comment) with messages
like `fix(review): address X as suggested in PR #123 review`. Never
`--amend` or `--no-verify`.

## Step 5: Reply to Every Comment

**Non-negotiable. Every comment identified in Step 2 must receive a reply,
including declined ones and bot comments.**

Read `references/reply-templates.md` for POST command shapes (inline thread
vs top-level), the four body templates (Accepted / Accepted-with-modification
/ Declined / Question), the "Long-body fallback" pattern (review body
> 500 chars → cite by review id instead of verbatim blockquote), and the
"Consolidated table reply" template (single review body with N ≥ 3
independent items → one table reply, not N separate ones). Reply in the
reviewer's language.

## Step 6: Push the Fix Commits

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs alongside the reply summary.

Track the push outcome in `PUSHED_FIXES` (count of new commit SHAs that
landed on the remote branch in this step). Step 6.5 reads this variable
to decide whether to move the PR card. When no fixes were committed
(all comments were DECLINE / QUESTION) or `git push` is skipped, set
`PUSHED_FIXES=0` so Step 6.5 becomes a no-op.

## Step 6.5: Sync Project Board (`In review` 복귀)

If Step 6 actually pushed at least one fix commit (i.e. `PUSHED_FIXES > 0`,
new SHAs created on the remote branch), push the PR card back to
`In review` so reviewers see it in their queue. Mirrors the
`/gh-pr-resolve-conflict` Step 5 pattern (issue #591) so both flows
share one board-recovery surface.

Skips when `PUSHED_FIXES == 0` (all comments DECLINE / QUESTION — no
push happened, so the card lifecycle has not changed and there is
nothing to recover). The `--only-from "In progress,Changes requested"`
guard makes the call a no-op for cards already at `In review` /
`Approved` / `Done`, so re-running on an already-recovered card never
demotes status.

Soft-fail — warn on any error, never block the Step 7 report.

```bash
if [ "${PUSHED_FIXES:-0}" -gt 0 ]; then
    # helper-fallback NF-1 (#644): silent-skip when helper missing.
    # Defense-in-depth (#724): also detect "sourced but function undefined".
    _HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
    if [ -r "$_HELPER" ]; then
        . "$_HELPER"
        if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
            printf '[gh-pr-reply] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
                "$_HELPER" >&2
        elif _gh_project_status_sync pr "$PR_NUMBER" "In review" \
                --only-from "In progress,Changes requested"; then
            echo "[OK] PR 카드 \`In review\` 로 복귀됨"
        else
            echo "[WARN] 보드 sync 실패 — 카드 수동 이동 필요할 수 있음"
        fi
    fi
    # helper missing → board sync silently skipped (NF-1).
fi
```

`GH_PROJECT_STATUS_SYNC=0` opt-out is absorbed by the helper itself.
projectV2 보드가 없는 레포는 helper 가 silent 0 반환. `--only-from`
의 missing column 은 helper 가 silently skip 하므로 `Changes requested`
컬럼 없는 보드와도 호환된다.

## Step 7: Report

Print the summary table per `references/final-summary.md` showing
Accepted / Declined / Answered counts, commit SHAs, any skipped
already-replied comments, **and the Step 8 outcome row** (always one
of `[OK] Step 8: …`, `[SKIP] Step 8: …`, or `[WARN] Step 8: …` — see
`references/final-summary.md` for the full row template). The Step 8
row consumes the `STEP8_OUTCOME` variable bound by the auto-approve
gate; if `STEP8_OUTCOME` is empty the gate never ran and the report
is **incomplete** (a regression signal — see issue #662). After the
table, run the "Lingering `CHANGES_REQUESTED` nudge" check from the
same reference: re-query `gh pr view --json reviewDecision`, and if
still `CHANGES_REQUESTED`, emit the one-line nudge so the user knows
replies + fixes alone do not clear the review block — the reviewer
must re-review.

After printing the report, post a PR comment with ai-metrics (soft-fail —
warn on error, never block). `COMMENT_COUNT` is the number of comments
addressed in Step 5 (including declined and bot comments). When
`GH_DISABLE_AI_METRICS=1`, skip the comment entirely (issue #399):

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
HUMAN_H=$(echo "scale=2; $COMMENT_COUNT * 0.25" | bc)
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="---
<details>
<summary>🤖 AI Metrics · 📊 ~${TOKENS:-5000} tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-pr-reply -->
📊 ~${TOKENS:-5000} tokens · 👤 ~$HUMAN_H h · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-pr-reply -->

</details>
리뷰 답변: ~$ELAPSED min · 사람: ~$HUMAN_H h ($COMMENT_COUNT comments × 0.25 h)"
fi
```

On failure: `[WARN] ai-metrics comment failed — continuing.`

## Step 8: Solo-Repo Auto-Approve (opt-in, soft-fail)

After Step 7, optionally move the PR card from `In review` to `Approved`.
**Always evaluate the 4 guards (skip is itself a logged outcome)** —
the move fires only when all four guards pass, but the gate runs on
every invocation so the outcome (fire / skip / warn) is bound to
`STEP8_OUTCOME` and surfaced as a row in the Step 7 report. Never
short-circuit the evaluation based on a prior assumption about env
configuration; the four-guard algorithm is the single source of
truth (issue #662). Guards:

| Guard | Pass condition |
|---|---|
| G1 | `GH_PR_REPLY_AUTO_APPROVE_REPOS` (`owner/repo` CSV) contains `$TARGET_REPO` (case-exact) |
| G2 | Step 2.5 did NOT early-exit (`COMMENT_COUNT >= 1`) |
| G3 | PR `state == OPEN` AND `isDraft == false` |
| G4 | PR `reviewDecision` is empty/`null` or `APPROVED` (never `REVIEW_REQUIRED` / `CHANGES_REQUESTED`) |

On all-pass: emit the audit-trace line and call
`_gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "In review"`
with `_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1` scoped to that single
call (prefix form, never `env` — it is a shell function). Helper rc
0/2 is soft-fail and never blocks the report. Bind `STEP8_OUTCOME`
on every branch (`OK:fired` / `SKIP:<reason>` / `WARN:rc=<N>`) so the
Step 7 report row reflects the actual evaluation result — full
outcome matrix and rendering rules: `references/auto-approve.md`
and `references/final-summary.md`. Full SSOT (4-guard algorithm,
audit format, defense-in-depth, ties to #275/#231/#393/#397):
`references/auto-approve.md`.

## Constraints

- **Never skip a reply** — even "Declined: out of scope" counts. Bot comments included. This is the core contract of the skill.
- Never close or resolve threads programmatically — leave that to the user.
- Never dismiss bot comments as "just a bot".
- Never fix files outside the PR's diff without flagging scope creep first.
- Never `--force-push`. If history rewrite is needed, stop and ask.
- If a future fix flow needs to mutate PR labels or body, route through
  `_gh_pr_edit_safe_label` / `_gh_pr_edit_safe_body`
  (`shell-common/functions/gh_pr_edit_safe.sh`). Bare `gh pr edit
  --add-label` / `--body-file` silently exits 1 on repos with classic
  Projects attached (issue #326 Bug B).
