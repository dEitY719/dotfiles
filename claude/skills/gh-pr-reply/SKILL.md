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
extraction, and dedup rule. Fetch all three; filter out already-replied threads.

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
vs top-level) and the four body templates (Accepted / Accepted-with-modification
/ Declined / Question). Reply in the reviewer's language.

## Step 6: Push the Fix Commits

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs alongside the reply summary.

## Step 7: Report

Print the summary table per `references/final-summary.md` showing
Accepted / Declined / Answered counts, commit SHAs, and any skipped
already-replied comments.

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
      -f body="<!-- ai-metrics:gh-pr-reply tokens=${TOKENS:-5000} human_h=$HUMAN_H ai_min=$ELAPSED -->
🤖 리뷰 답변: ~$ELAPSED min · 👤 ~$HUMAN_H h ($COMMENT_COUNT comments × 0.25 h)"
fi
```

On failure: `⚠️  ai-metrics comment failed — continuing.`

## Step 8: Solo-Repo Auto-Approve (opt-in, soft-fail)

After Step 7, optionally move the PR card from `In review` to `Approved`.
**Off by default** — fires only when all four guards pass:

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
0/2 is soft-fail and never blocks the report. Full SSOT (4-guard
algorithm, audit format, defense-in-depth, ties to #275/#231/#393/#397):
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
