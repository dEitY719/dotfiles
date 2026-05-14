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

## Options

| Argument | Description | Default |
|----------|-------------|---------|
| `[N]` (positional) | Legacy `/gh:pr 123` form — overrides issue auto-detection. | — |
| `--no-stack` | Force a non-stacked PR even when stacked-PR signals fire. | off |
| `--base <branch>` | Explicit base branch; bypasses stacked-PR detection. | repo default |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `GH_PR_LINT_BYPASS=1` (env) | Skip Step 4.5 lint guard. | off |
| `DOTFILES_ROOT` (env) | Root used to source `gh_pr_lint.sh`. | `$HOME/dotfiles` |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

`--no-stack` and `--base` are mutually exclusive — see Step 1a exit codes.

## Step 1: Parse Args, Resolve Base Branch, Gather State

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

### Step 1a: Parse args + resolve base via stacked-PR detection

Read `references/stacked-pr.md` and paste the SSOT functions
(`parse_stacked_args`, `is_stacked_pr_repo`, `find_parent_pr_candidates`)
and the dispatch block ("How Step 1 of SKILL.md ties it together")
verbatim. They bind `BASE_BRANCH`, `PARENT_PR`, and `ISSUE_NUMBER`, and
they exit on bad input — `rc=2` for mutually-exclusive flags, `rc=3`
for a bad `--base` value. Abort without pushing on either.

### Step 1b: Gather range + push state (parallel)

Run in a single message, using `$BASE_BRANCH` from Step 1a:
`git rev-parse --abbrev-ref HEAD`, `git status`, `git fetch origin`,
`git log --oneline "$BASE_BRANCH"..HEAD`, `git diff "$BASE_BRANCH"...HEAD`,
and `git rev-parse --symbolic-full-name @{u} 2>/dev/null`.

Stop conditions: current branch equals `BASE_BRANCH` → ask for a
feature branch; `git log "$BASE_BRANCH"..HEAD` empty → nothing to PR.

## Step 2: Analyze ALL Commits in the Range

The PR body must reflect **every commit** in the range, not just the latest.
Read `git log <base>..HEAD` output and group changes by theme. A 5-commit PR
mentions all 5 concerns.

## Step 3: Resolve the Issue Number

Same precedence as `gh:commit`: (1) explicit `/gh:pr <N>` arg, (2)
recent conversation `#N` / `Issue #N created`, (3) commit messages in
the range (`Refs/Closes/Fixes #N`), (4) none → omit the link.

## Step 4: Draft Title and Body

Read `references/pr-body-template.md` for title rules, body structure,
and the body markdown. Match the language of existing commits (Korean
if commits are Korean).

Then read `references/ai-metrics-footer.md` and follow it verbatim to
compute `TOKENS`, `HUMAN_H`, `ELAPSED` and append the footer to `$BODY`
(soft-fail — warn on error, never block). Honours
`GH_DISABLE_AI_METRICS=1` (issue #399).

## Step 4.5: Lint Guard (pre-push)

Read `references/lint-guard.md` and paste its "Helper" source-and-run
snippet verbatim. Runs against `$BASE_BRANCH` **before** the push in
Step 5. Hard-fails on lint errors; auto-skips when no tools are
detected, when the change set is empty, or when `GH_PR_LINT_BYPASS=1`.

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

Read `references/project-board-sync.md` for the helper-source snippet
that pushes the new PR's project-board card to `In review`. The
reference also documents the PostToolUse hook auto-skip (issue #390)
and the no-projectV2 fallback.

## Step 8: Report

성공 시:

```
[OK] PR: https://github.com/owner/repo/pull/<N>
Next: /gh:pr-reply (after CI green) — replies to review comments
```

Step 1b empty-range / on-base-branch stops, Step 1a `rc=2`/`rc=3`, or
Step 4.5 lint failure:

```
[FAIL] <one-line reason>
Next: <recovery — e.g. switch branch, fix lint, drop conflicting flag>
```

No additional summary — the user opens GitHub directly from the URL.

## Constraints

Read `references/constraints.md` for hard rules: no force-push without
approval, default base only, no AI footer unless the repo already uses one,
never skip commits in the Summary.
