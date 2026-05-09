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

## Step 1: Parse Args, Resolve Base Branch, Gather State

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

### Step 1a: Parse args + resolve base via stacked-PR detection

Read `references/stacked-pr.md` for the SSOT bash bound to
`parse_stacked_args`, `is_stacked_pr_repo`, and
`find_parent_pr_candidates`, plus the dispatch block ("How Step 1 of
SKILL.md ties it together"). Paste the four functions and the dispatch
block verbatim. They set:

- `BASE_BRANCH` — final base branch for `gh pr create --base`
- `PARENT_PR` — non-empty PR number when the PR is stacked on another
  open PR; empty otherwise
- `ISSUE_NUMBER` — first positional integer arg if any (legacy
  `/gh-pr 123` form)

Honour `parse_stacked_args`'s exit codes:

- rc=2 — mutually-exclusive flags (`--no-stack` / `--parent-pr` /
  `--base`); abort, do not push.
- rc=3 — bad value for `--parent-pr` or `--base`; abort, do not push.

`PARENT_PR` flows into the body template "Depends on #N" rule
(`pr-body-template.md`). `BASE_BRANCH` flows into Step 5's
`gh pr create --base "$BASE_BRANCH"`.

### Step 1b: Gather range + push state (parallel)

Run in a single message, using `$BASE_BRANCH` from Step 1a:

- `git rev-parse --abbrev-ref HEAD` — current branch
- `git status`
- `git fetch origin`
- `git log --oneline "$BASE_BRANCH"..HEAD` — every commit in the range
- `git diff "$BASE_BRANCH"...HEAD` — full diff
- `git rev-parse --symbolic-full-name @{u} 2>/dev/null` — upstream check

**Stop conditions:**

- If current branch equals `BASE_BRANCH` → tell the user to create a
  feature branch first.
- If `git log "$BASE_BRANCH"..HEAD` is empty → tell the user there's
  nothing to PR.

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

Before writing the body to the temp file, compute and append the ai-metrics
footer block (soft-fail — warn on error, never block):

1. `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`
2. Issue type: the conventional-commit prefix from the first commit subject.
3. Human time: look up `gh-issue-create/references/metrics-baseline.md`.
   For `feat`, infer size from the number of files changed.
4. Token estimate: read `references/metrics-helper.md` and paste the
   `compute_pr_tokens` snippet in full. The inputs are **(linked-issue
   body) + (commit log over `<base>..HEAD`)**, NOT the drafted PR body.
   Counting `$BODY` (the PR-body temp file) is the regression that
   produced PR #325's `📊 ~1000 tokens` footer (issue #326).

```bash
# After running the snippet from references/metrics-helper.md, $TOKENS is
# bound to the correct estimate. Now append the footer to $BODY.
printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics:gh-pr -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics:gh-pr -->\n\n</details>\n' \
  "$TOKENS" "$HUMAN_H" "$ELAPSED" "$TOKENS" "$HUMAN_H" "$ELAPSED" >> "$BODY"
```

## Step 5: Push and Create

Read `references/push-and-create.md` for the upstream-state push policy and
the `gh pr create` command (uses `mktemp` body file, `--assignee @me`,
`--base "$BASE_BRANCH"` from Step 1a).

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
