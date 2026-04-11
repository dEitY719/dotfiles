---
name: gh:pr-reply
description: >-
  Fetch code review comments on a GitHub PR, evaluate each one, apply valid
  fixes, and leave an individual reply on every comment (Accepted with what
  changed, or Declined with reasoning). Use when the user runs /gh:pr-reply,
  /gh-pr-reply, or asks "PR 리뷰 코멘트 확인하고 수정", "리뷰 답변 달아", "PR 123
  코멘트 처리해". Defaults to the PR for the current branch; accepts an explicit
  PR number as an argument. Every comment MUST get a reply — bot comments
  (gemini, sourcery, copilot) included.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# gh:pr-reply — Address PR Review Comments

## Role

Systematically process every code-review comment on a PR: judge validity,
fix valid ones in code, and reply to each comment individually with the
outcome. This is the politeness rule — reviewers must see an explicit
response on every thread so they know their feedback was processed.

## Step 1: Resolve Target PR

Precedence:
1. **Explicit argument** — `/gh:pr-reply 123` → PR #123
2. **Current branch auto-detect** — `gh pr view --json number,url,headRefName,baseRefName`
   - If no PR exists for the branch, stop and tell the user.
3. Never guess. Never pick "the latest PR in the repo".

Also capture `owner/repo` via `gh repo view --json nameWithOwner`.

## Step 2: Fetch All Review Comments

PRs have two distinct comment APIs — fetch **both**:

```bash
# Inline code review comments (line-anchored)
gh api "repos/<owner>/<repo>/pulls/<N>/comments" --paginate

# Top-level issue-style comments on the PR conversation
gh api "repos/<owner>/<repo>/issues/<N>/comments" --paginate

# Review summaries (bots often put content here)
gh api "repos/<owner>/<repo>/pulls/<N>/reviews" --paginate
```

For each comment, record: `id`, `user.login`, `path`, `line`, `body`,
`in_reply_to_id` (for threading), and `html_url`.

**Filter out already-replied-to comments**: if a human or Claude has already
posted a reply in the same thread (check `in_reply_to_id` chains), skip it
unless the user explicitly says to re-process.

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
rules — a bot nit about a rename is still a legitimate comment that deserves
a reply.

## Step 4: Apply Fixes (ACCEPT / ACCEPT-PARTIAL only)

- Edit files with the Edit tool. Keep each fix minimal and scoped to the
  comment — don't drive-by refactor.
- Group related fixes into logical commits. If the user hasn't said otherwise,
  make one commit per theme, not one commit per comment.
- Commit message should reference the PR and the comment intent, e.g.:
  `fix(review): address X as suggested in PR #123 review`
- Never use `--amend` or `--no-verify`.

## Step 5: Reply to Every Comment

This is non-negotiable. **Every** comment identified in Step 2 must receive
a reply, even declined ones, even bot comments.

### For inline review comments (Step 2's `/pulls/N/comments`)

Reply in-thread:

```bash
gh api "repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies" \
  -X POST \
  -f body="<reply text>"
```

### For top-level issue comments

```bash
gh api "repos/<owner>/<repo>/issues/<N>/comments" \
  -X POST \
  -f body="> <blockquote of original>

<reply text>"
```

### Reply body templates

**Accepted:**
```
Accepted. Fixed in <short-sha> — <one-line what changed>.
```

**Accepted with deviation:**
```
Accepted with modification. Rather than <their suggestion>, I went with
<actual fix> in <short-sha> because <reason>.
```

**Declined:**
```
Declined. <specific reason tied to the code/context>. <optional: pointer to
docs, other PR, or file that justifies the current design>.
```

**Question answered:**
```
<direct answer>. <optional: link to file:line for reference>.
```

Reply in the language the reviewer used (Korean reviewer → Korean reply).

## Step 6: Push the Fix Commits

If any fixes were committed:
- `git push` (never force-push unless user asked)
- Report new commit SHAs alongside the reply summary

## Step 7: Report

Print a table the user can scan:

```
PR #123 review comments processed: 5 total
  ✓ Accepted: 3 (commits abc1234, def5678)
  ✗ Declined: 1
  ? Answered: 1
  → All comments replied to.
```

If any comments were skipped as "already replied", list them at the bottom.

## Constraints

- **Never skip a reply.** Even a one-line "Declined: out of scope" is
  required. This is the core contract of the skill.
- Never close or resolve threads programmatically — leave that to the user.
- Never dismiss bot comments as "just a bot". Reply to them too.
- Never fix comments that touch files outside the PR's diff without
  flagging it to the user first — that's scope creep.
- Never `--force-push`. If a fix needs history rewrite, stop and ask.
