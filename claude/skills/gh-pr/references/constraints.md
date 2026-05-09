# Constraints — hard rules the gh:pr skill must never violate

These apply across every step. If any rule would be broken, stop and ask
the user instead of proceeding.

## Force-push

Never force-push without explicit user approval. If the upstream has
diverged from local, surface the divergence and wait for the user to say
either "force push" or "rebase first" — do not pick for them.

## Base branch

The base branch is decided in Step 1a (`references/stacked-pr.md`):

1. Default branch (`gh repo view --json defaultBranchRef`) when the
   repo has no stacked-PR signals — solo / non-stacked workflow.
2. Auto-detected parent PR's head ref when the repo opts into stacked
   PRs *and* exactly one open PR is an ancestor of HEAD.
3. The user-supplied target when one of `--no-stack` / `--parent-pr <N>`
   / `--base <branch>` was passed (mutually exclusive — combining any
   two aborts).

Never target any base outside those three sources. In particular,
never auto-stack on a repo that does not match `is_stacked_pr_repo`,
and never silently downgrade to the default branch when the user
explicitly passed `--parent-pr` or `--base`.

## AI footers

Never include `🤖 Generated with` or any "Claude Code" footer in the PR
body **unless** the repo already uses that convention in existing PRs.
Check recent merged PRs (`gh pr list --state merged --limit 5`) before
deciding.

## Commit coverage

Never skip commits in the Summary because "they're minor" — the commit
range `<base>..HEAD` is the contract. A 5-commit PR mentions all 5
concerns. If commits are truly trivial (e.g. typo fixes), group them but
still acknowledge them.

## Output discipline

The final report contains **only** the PR URL — no preamble, no summary
of what the PR does, no next-step suggestions. Reviewers open GitHub
directly.
