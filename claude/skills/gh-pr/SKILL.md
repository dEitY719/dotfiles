---
name: gh:pr
description: >-
  Create a GitHub pull request from the current branch, bundling all commits
  since it diverged from the base branch. Use when the user runs /gh:pr,
  /gh-pr, or asks "PR 생성", "풀리퀘 만들어", "지금까지 커밋들로 PR 올려". Pushes
  the branch if needed, drafts a structured PR body covering every commit in
  the range (not just HEAD), auto-links a related issue when known, and
  returns only the PR URL.
allowed-tools: Bash, Read, Grep
---

# gh:pr — Create Pull Request

## Role

Bundle the current branch's commits into a GitHub PR with a well-structured
body. Push the branch if needed. Return the PR URL.

## Step 1: Determine Base Branch and State (parallel)

Run in a single message:
- `git rev-parse --abbrev-ref HEAD` — current branch
- `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` — base
- `git status`
- `git fetch origin` — refresh remote refs

Then:
- `git log --oneline <base>..HEAD` — every commit in the PR range
- `git diff <base>...HEAD` — full diff
- `git rev-parse --symbolic-full-name @{u} 2>/dev/null` — check if branch has
  an upstream

**Stop conditions:**
- If current branch equals base branch → tell the user to create a feature
  branch first.
- If `git log <base>..HEAD` is empty → tell the user there's nothing to PR.

## Step 2: Analyze ALL Commits in the Range

This is critical: the PR body must reflect **every commit** in the range, not
just the latest one. Read `git log <base>..HEAD` output and group changes by
theme. A 5-commit PR should mention all 5 concerns, not just HEAD's change.

## Step 3: Resolve the Issue Number

Same precedence as `gh:commit`:
1. Explicit argument on `/gh:pr` (e.g., `/gh:pr 123`)
2. Scan recent conversation for `#N` or `Issue #N created`
3. Scan commit messages in the range for `Refs #N` / `Closes #N` / `Fixes #N`
4. None — omit the link

## Step 4: Draft Title and Body

**Title** — under 70 chars, imperative mood, matches commit style of the repo.
Do NOT stuff details into the title; they belong in the body.

**Body template** (language: match the repo — Korean if commits are Korean):

```markdown
## Summary
- <1–3 bullets covering the whole PR, not just HEAD>

## Changes
- <commit-scope 1>: <what changed and why>
- <commit-scope 2>: <...>
<one bullet per meaningful commit or logical group>

## Test plan
- [ ] <concrete manual or automated check>
- [ ] <another check>

## Related
Closes #<N>        ← only if issue resolved
Refs #<N>          ← if related but not fully resolving
```

Omit `## Related` entirely if no issue is known.

## Step 5: Push and Create (parallel where possible)

- If no upstream: `git push -u origin HEAD`
- If upstream exists and local is ahead: `git push`
- If upstream is diverged: stop and ask the user before force-pushing
  (never force-push without explicit approval)

Write the body to a temp file, then:

```bash
gh pr create \
  --base <base> \
  --title "<title>" \
  --body-file /tmp/gh-pr-body.md
```

Do NOT set `--draft`, `--reviewer`, `--assignee`, or `--label` unless the user
asked.

## Step 6: Report

Output **only** the PR URL:

```
PR created: https://github.com/owner/repo/pull/<N>
```

No preamble, no summary of what the PR does — the user opens GitHub directly.

## Constraints

- Never force-push without explicit user approval.
- Never target a base other than the repo's default branch unless the user
  said so.
- Never include `🤖 Generated with` or Claude Code footer unless the repo
  already uses that convention in existing PRs.
- Never skip commits in the Summary because "they're minor" — the range is
  the contract.
