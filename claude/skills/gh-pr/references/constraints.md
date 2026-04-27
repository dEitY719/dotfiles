# Constraints — hard rules the gh:pr skill must never violate

These apply across every step. If any rule would be broken, stop and ask
the user instead of proceeding.

## Force-push

Never force-push without explicit user approval. If the upstream has
diverged from local, surface the divergence and wait for the user to say
either "force push" or "rebase first" — do not pick for them.

## Base branch

Never target a base other than the repo's default branch (resolved via
`gh repo view --json defaultBranchRef`) unless the user explicitly asked
for a different base on the slash-command invocation.

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
