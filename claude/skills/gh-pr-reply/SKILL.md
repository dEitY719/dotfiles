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

Precedence:
1. **Explicit argument** — `/gh:pr-reply 123` → PR #123.
2. **Current branch auto-detect** — `gh pr view --json number,url,headRefName,baseRefName`; if no PR exists, stop and tell the user.
3. Never guess. Never pick "the latest PR in the repo".

Also capture `owner/repo` via `gh repo view --json nameWithOwner`.

## Step 2: Fetch All Review Comments

Read `references/comment-fetching.md` for the three API endpoints, field
extraction, and dedup rule. Fetch all three; filter out already-replied threads.

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

## Step 7: Sync Project Board Status

Read `references/project-board-sync.md` and run the helper to push the PR's
project card to `Approved` (no-op when no projectV2 board is attached).

## Step 8: Report

Print the summary table per `references/final-summary.md` showing
Accepted / Declined / Answered counts, commit SHAs, and any skipped
already-replied comments.

## Constraints

- **Never skip a reply** — even "Declined: out of scope" counts. Bot comments included. This is the core contract of the skill.
- Never close or resolve threads programmatically — leave that to the user.
- Never dismiss bot comments as "just a bot".
- Never fix files outside the PR's diff without flagging scope creep first.
- Never `--force-push`. If history rewrite is needed, stop and ask.
