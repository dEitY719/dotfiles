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
metadata:
  model_recommendation:
    tier: haiku
    reason: "gh pr create wrap with body draft; structured commit-range bundling + bounded lint/board mutations"
    claude: prefer
    non_claude: advisory-only
---

# gh:pr — Create Pull Request

## Help & Role

If arg #1 is `-h`/`--help`/`help`, read `references/help.md`, output it
verbatim, then stop (no API calls). Otherwise: bundle the current branch's
commits into a GitHub PR with a well-structured body, push if needed, and
return the PR URL. Accepted options: `references/options.md`.

## Step 1: Parse Args, Resolve Base Branch, Gather State

Record `START_TS=$(date +%s)` immediately for Step 4 elapsed-time tracking.
**1a — base via stacked-PR detection:** read `references/stacked-pr.md` and
paste its SSOT functions + dispatch block ("How Step 1 of SKILL.md ties it
together") verbatim. They bind `BASE_BRANCH`, `PARENT_PR`, `ISSUE_NUMBER` and
exit on bad input (`rc=2` mutually-exclusive flags, `rc=3` bad `--base`,
`rc=5` parent PR not `OPEN`). Abort without pushing on any of them.

**1b — gather range + push state (one message):** using `$BASE_BRANCH`, run
`git rev-parse --abbrev-ref HEAD`, `git status`, `git fetch origin`, `git log
--oneline "$BASE_BRANCH"..HEAD`, `git diff "$BASE_BRANCH"...HEAD`, `git
rev-parse --symbolic-full-name @{u} 2>/dev/null`. Stop conditions: current
branch equals `BASE_BRANCH` → ask for a feature branch; empty range → nothing to PR.

## Steps 2-3: Analyze ALL Commits + Resolve Issue

The PR body must reflect **every commit** in the range, not just the latest:
read `git log <base>..HEAD` and group changes by theme (a 5-commit PR mentions
all 5 concerns). Resolve the issue number with the same precedence as
`gh:commit`: (1) explicit `/gh:pr <N>` arg, (2) recent conversation `#N` /
`Issue #N created`, (3) range commit messages (`Refs/Closes/Fixes #N`), (4)
none → omit the link.

## Step 4 + 4.5: Draft Body, then Lint Guard (pre-push)

Read `references/pr-body-template.md` for title rules and body markdown; match
the language of existing commits. Then read `references/ai-metrics-footer.md`
and follow it verbatim to compute `TOKENS`/`HUMAN_H`/`ELAPSED` and append the
footer to `$BODY` (soft-fail, never block; honours `GH_DISABLE_AI_METRICS=1`,
issue #399). Next (Step 4.5) read `references/lint-guard.md` and paste its
"Helper" snippet verbatim — runs against `$BASE_BRANCH` **before** the Step 5
push; hard-fails on lint errors; auto-skips when no tools detected, change set
empty, or `GH_PR_LINT_BYPASS=1`.

## Step 5: Push and Create

Read `references/push-and-create.md` for the upstream-state push policy and
the `gh pr create` command (`mktemp` body file, `--assignee @me`, `--base
"$BASE_BRANCH"`). After the URL returns, emit
`printf '[step:gh-pr/push-and-create] OK\n'` for the step-skip guard
(`skill_completion_guard.py`, issue #753).

## Step 6: Apply Labels

Derive labels from conventional-commit types in `git log <base>..HEAD` and PR
scope (e.g. `skill` for `claude/skills/` changes). Apply only labels that
exist in the repo (`gh label list`) — never create new ones. See
`references/pr-body-template.md` for the full mapping and safe-apply loop.
After the loop (including the all-missing no-op case), emit
`printf '[step:gh-pr/labels] OK\n'`.

## Step 7: Sync Project Board Status

Push the new PR card to `In review` and correct any linked Issue cards the
GitHub builtin mis-moved there (Issues belong in `In progress`). Run the
post-create board sync per `references/project-board-sync.md` — paste the
snippet verbatim. That file also carries the hook auto-skip narrative,
`GH_REPO` requirement, Step 8 report-row mapping, and the
`[step:gh-pr/board-sync] OK` marker.

## Step 8: Report

Read `references/report-template.md` for the success/failure report blocks
(including the defense-in-depth `Board sync:` row, issue #747) and the closing
`[step:gh-pr/report] OK` marker. No extra summary — the user opens GitHub from
the URL.

## Constraints

Read `references/constraints.md` for hard rules: no force-push without approval,
default base only, no AI footer unless the repo already uses one, never skip
commits in the Summary.
