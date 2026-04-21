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
fix valid ones, and reply to each comment with the outcome. This is the
**politeness rule** — reviewers (humans and bots alike) must see an
explicit response on every thread. Silent fixes are not acceptable;
silent declines are worse.

## Step 1: Resolve Target PR

Precedence:
1. **Explicit argument** — `/gh:pr-reply 123` → PR #123
2. **Current branch auto-detect** — `gh pr view --json number,url,headRefName,baseRefName`; if no PR exists for the branch, stop and tell the user.
3. Never guess. Never pick "the latest PR in the repo".

Also capture `owner/repo` via `gh repo view --json nameWithOwner`.

## Step 2: Fetch All Review Comments

Read `references/comment-fetching.md` for the three API endpoints, field
extraction, and dedup rule. Fetch all three; filter out already-replied
threads.

## Step 3: Evaluate Each Comment

For each unaddressed comment, read the referenced file (`path` at `line`) and
classify:

- **ACCEPT** — reviewer is correct; the code should change
- **ACCEPT-PARTIAL** — valid concern, but a different fix is better; note the
  deviation in the reply
- **DECLINE** — reviewer is wrong, misunderstanding the context, or the
  suggestion would regress something; must explain why
- **QUESTION** — reviewer asked for clarification rather than a change;
  answer the question

Bot comments (gemini-code-assist, sourcery-ai, copilot) follow the same
rules — a bot nit is still a legitimate comment that deserves a reply.

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

- Keep each fix minimal and scoped — don't drive-by refactor.
- Group related fixes into logical commits: one per theme, not one per
  comment, unless the user says otherwise.
- Commit message references the PR, e.g.
  `fix(review): address X as suggested in PR #123 review`.
- Never use `--amend` or `--no-verify`.

## Step 5: Reply to Every Comment

**This is non-negotiable. Every comment identified in Step 2 must receive a
reply, even declined ones, even bot comments.**

Read `references/reply-templates.md` for POST command shapes (inline thread
vs top-level) and the four body templates (Accepted / Accepted-with-modification
/ Declined / Question). Reply in the reviewer's language.

## Step 6: Push the Fix Commits

If any fixes were committed: `git push` (never force-push unless the user
asked) and report new commit SHAs alongside the reply summary.

## Step 7: Report

Print a table the user can scan:

```
PR #123 review comments processed: 5 total
  Accepted: 3 (commits abc1234, def5678)
  Declined: 1
  Answered: 1
  -> All comments replied to.
```

If any comments were skipped as "already replied", list them at the bottom.

## Constraints

- **Never skip a reply.** Even a one-line "Declined: out of scope" is
  required. This is the core contract of the skill — bot comments included.
- Never close or resolve threads programmatically — leave that to the user.
- Never dismiss bot comments as "just a bot". Reply to them too.
- Never fix comments that touch files outside the PR's diff without
  flagging it to the user first — that's scope creep.
- Never `--force-push`. If a fix needs history rewrite, stop and ask.
