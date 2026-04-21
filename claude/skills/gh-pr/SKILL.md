---
name: gh:pr
description: >-
  Create a GitHub pull request from the current branch, bundling all commits
  since it diverged from the base branch. Use when the user runs /gh:pr,
  /gh-pr, or asks "PR 생성", "풀리퀘 만들어", "지금까지 커밋들로 PR 올려". Pushes
  the branch if needed, drafts a structured PR body covering every commit in
  the range (not just HEAD), auto-links a related issue when known, and
  returns only the PR URL. Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:pr — Create Pull Request

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

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
- `git rev-parse --symbolic-full-name @{u} 2>/dev/null` — upstream check

**Stop conditions:**
- If current branch equals base branch → tell the user to create a feature
  branch first.
- If `git log <base>..HEAD` is empty → tell the user there's nothing to PR.

## Step 2: Analyze ALL Commits in the Range

Critical: the PR body must reflect **every commit** in the range, not just
the latest one. Read `git log <base>..HEAD` output and group changes by
theme. A 5-commit PR should mention all 5 concerns, not just HEAD's change.

## Step 3: Resolve the Issue Number

Same precedence as `gh:commit`:
1. Explicit argument on `/gh:pr` (e.g., `/gh:pr 123`)
2. Scan recent conversation for `#N` or `Issue #N created`
3. Scan commit messages in the range for `Refs #N` / `Closes #N` / `Fixes #N`
4. None — omit the link

## Step 4: Draft Title and Body

Read `references/pr-body-template.md` for title rules, body structure, and
the `gh pr create` command. Match the language of existing commits (Korean
if commits are Korean).

## Step 5: Push and Create

- If no upstream: `git push -u origin HEAD`
- If upstream exists and local is ahead: `git push`
- If upstream is diverged: **stop and ask the user before force-pushing**
  (never force-push without explicit approval).

Write the body to a unique temp file via `mktemp`, then create the PR with
`--assignee @me` (always self-assigned). Full command in
`references/pr-body-template.md`.

## Step 6: Apply Labels

Derive labels from conventional-commit types in `git log <base>..HEAD`
(`feat` → enhancement, `fix` → bug, `docs` → documentation, `refactor`,
`style`, `perf`, `test`, `chore`, `ci`, `build`) plus judgment-based
labels matching the PR scope (e.g., `skill` for `claude/skills/` changes).
Query existing labels via `gh label list` and apply only labels that
**already exist** in the repo — never create new labels. Details and the
safe-application loop in `references/pr-body-template.md`.

## Step 7: Report

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
