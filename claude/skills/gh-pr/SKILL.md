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

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls.

## Role

Bundle the current branch's commits into a GitHub PR with a well-structured
body. Push the branch if needed. Return the PR URL.

## Step 1: Determine Base Branch and State (parallel)

Run in a single message:

- `git rev-parse --abbrev-ref HEAD` — current branch
- `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` — base
- `git status`
- `git fetch origin`
- `git log --oneline <base>..HEAD` — every commit in the range
- `git diff <base>...HEAD` — full diff
- `git rev-parse --symbolic-full-name @{u} 2>/dev/null` — upstream check

**Stop conditions:**

- If current branch equals base branch → tell the user to create a feature
  branch first.
- If `git log <base>..HEAD` is empty → tell the user there's nothing to PR.

## Step 2: Analyze ALL Commits in the Range

The PR body must reflect **every commit** in the range, not just the latest.
Read `git log <base>..HEAD` output and group changes by theme. A 5-commit PR
mentions all 5 concerns.

## Step 3: Resolve the Issue Number

Same precedence as `gh:commit`:

1. Explicit argument on `/gh:pr` (e.g., `/gh:pr 123`)
2. Scan recent conversation for `#N` or `Issue #N created`
3. Scan commit messages in the range for `Refs #N` / `Closes #N` / `Fixes #N`
4. None — omit the link

## Step 4: Draft Title and Body

Read `references/pr-body-template.md` for title rules, body structure, and
the body markdown. Match the language of existing commits (Korean if commits
are Korean).

## Step 5: Push and Create

Read `references/push-and-create.md` for the upstream-state push policy and
the `gh pr create` command (uses `mktemp` body file, `--assignee @me`).

## Step 6: Apply Labels

Derive labels from conventional-commit types in `git log <base>..HEAD` and
PR scope (e.g. `skill` for `claude/skills/` changes). Apply only labels that
exist in the repo (`gh label list`) — never create new ones. See
`references/pr-body-template.md` for the full mapping and safe-apply loop.

## Step 7: Sync Project Board Status

Read `references/project-board-sync.md` for the helper-source snippet that
pushes the new PR's project-board card to `In review`. Auto-skips when no
projectV2 board is attached.

## Step 8: Report

Output **only** the PR URL:

```
PR created: https://github.com/owner/repo/pull/<N>
```

No preamble, no summary — the user opens GitHub directly.

## Constraints

Read `references/constraints.md` for hard rules: no force-push without
approval, default base only, no AI footer unless the repo already uses one,
never skip commits in the Summary.
