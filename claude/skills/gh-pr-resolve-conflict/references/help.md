# gh:pr-resolve-conflict — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<pr-number>` or `-h`/`--help`/`help` | current-branch PR | Target PR, e.g. `168` |
| 2 | remote-name | `origin` | Git remote whose repo owns the PR |

## Usage

```
/gh-pr-resolve-conflict              # PR attached to current branch, origin
/gh-pr-resolve-conflict 168          # explicit PR, origin
/gh-pr-resolve-conflict 168 upstream # explicit PR, upstream remote
/gh-pr-resolve-conflict -h           # this help
```

## When to use this skill

- GitHub shows **"This branch has conflicts that must be resolved"** on a PR.
- A colleague's PR merged first and your PR's base (usually `main`) has moved.
- You want to stay on the `--rebase` policy track — no merge commits.

## When NOT to use

- Conflicts are trivial enough that `gh pr merge --rebase` handles them.
  (Use `/gh-pr-merge` — if it fails with `CONFLICTING`, come back here.)
- You prefer a merge-commit strategy. This skill refuses that; edit the
  PR with `git merge main` manually if that's really what you want.
- You are on the repo's default branch. The skill refuses — create or
  check out the feature branch first.

## What the skill does

1. Parses args. Auto-detects the PR from the current branch if omitted.
2. Prints a **backup SHA** so `git reset --hard <sha>` can undo everything.
3. Stashes a dirty working tree (announced before stashing).
4. Fetches the base branch and runs `git rebase origin/<base>`.
5. On each conflicting commit:
   - lists conflicted paths,
   - shows the rebase context (commit-applying + remaining commits),
   - walks the user through each file,
   - runs `git add` and `git rebase --continue` after confirmation.
6. Pushes with `git push --force-with-lease` (never plain `--force`).
7. Calls `gh pr view --json mergeable,mergeStateStatus` to confirm the
   GitHub warning is cleared.
8. Pops any stash it created.

## Safety

- **Backup SHA** printed before the rebase — `git reset --hard <sha>`
  restores the pre-rebase state; `git reflog` is always available too.
- **Stash** — only auto-applied if preflight detects a dirty tree, and
  always announced. Popped at the end even on failure paths.
- **`--force-with-lease`** — rejects the push if someone else pushed to
  the branch while you rebased. The skill stops; it does NOT silently
  re-fetch and re-rebase.
- **Abort** — if you want out mid-rebase, type `git rebase --abort` in
  a separate shell; the skill will detect the abort on the next
  iteration and stop cleanly.

## What this skill will NOT do

- Create a merge commit. Rebase-only. Non-negotiable.
- Run `git push --force` (without `-with-lease`).
- Run on the repo's default branch.
- Guess how to resolve an ambiguous conflict. If the commit message
  doesn't make the choice obvious, it asks.
- Re-pull-and-rebase after a rejected `--force-with-lease`. It reports
  the divergence and stops, so you can decide.

## Related skills

- `gh:pr-merge` — merge an already-clean PR (rebase/squash/merge).
- `gh:pr-merge-emergency` — admin-bypass merge with audit trail.
- `gh:pr` — create a PR from the current branch.
- `gh:pr-reply` — reply to PR review comments after rebasing.
