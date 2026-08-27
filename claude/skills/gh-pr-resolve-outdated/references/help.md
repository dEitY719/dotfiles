# gh:pr-resolve-outdated — Help

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `[pr-number]` | Positional 1 — target PR to sync, e.g. `782`. | PR attached to the current branch |
| `[remote]` | Positional 2 — git remote whose repo owns the PR. | `origin` |
| `--worktree <path>` | Run every git command in `<path>` instead of the current checkout. Requires an explicit `pr-number`. | current checkout |
| `-h` / `--help` / `help` | Print this help verbatim and stop. No API calls. | — |

## Usage

```
/gh-pr-resolve-outdated              # PR attached to current branch, origin
/gh-pr-resolve-outdated 782          # explicit PR, origin
/gh-pr-resolve-outdated 782 upstream # explicit PR, upstream remote
/gh-pr-resolve-outdated 782 origin --worktree /path/to/scratch   # rebase there
/gh-pr-resolve-outdated -h           # this help
```

`--worktree` exists for `gh:pr-merge-train`: the PR's head branch is usually
already checked out in the worktree `gh:issue-flow` opened it from, so the train
hands over a detached scratch worktree it created and will destroy. The push
then uses an explicit `HEAD:refs/heads/<head>` refspec, since a detached HEAD
names no branch.

## When to use this skill

- GitHub shows **"This branch is out-of-date with the base branch"**
  on a PR (banner / "Update branch" button), but there are **no file
  conflicts**.
- A colleague's PR merged first and the base (usually `main`) has
  moved forward, but your changes don't overlap.
- You want a 1-line slash command instead of typing
  `git fetch && git rebase origin/main && git push --force-with-lease`
  every time.

## When NOT to use

- The PR has actual file conflicts → use `/gh-pr-resolve-conflict`
  (the sister skill that walks through each conflicting file).
- The PR is failing CI → use `/gh-pr-resolve-ci-fail`. Out-of-date is
  not the same problem.
- You want a merge commit on your PR instead of a rebase. This skill
  refuses — dotfiles policy is rebase-only.
- You are on the repo's default branch. The skill refuses — switch to
  the feature branch first.

## What the skill does

1. Parses args. Auto-detects the PR from the current branch if omitted.
2. Prints a **backup SHA** so `git reset --hard <sha>` can undo
   everything if the rebase goes wrong.
3. Queries `gh pr view --json mergeable,mergeStateStatus`:
   - `MERGEABLE` + `CLEAN`/`UNSTABLE` → already up-to-date, exit 0.
   - `MERGEABLE` + `BEHIND` → proceed (this skill's job).
   - `CONFLICTING` → delegate to `/gh-pr-resolve-conflict`, exit 3.
   - `UNKNOWN` → GitHub still computing, exit 0 (retry later).
4. `git fetch <remote> <base>`, then `git rebase <remote>/<base>`.
5. Conflicts appear during rebase → `git rebase --abort` and exit 4
   with a pointer to `/gh-pr-resolve-conflict <PR_NUMBER>`. Never
   auto-guesses (same policy as the sister skill).
6. `git push --force-with-lease` (never plain `--force`). Rejected
   push → exit 6, no silent retry.
7. Re-queries `gh pr view` to confirm the banner is cleared.

## Safety

- **Backup SHA** printed before the rebase — `git reset --hard <sha>`
  restores the pre-rebase state; `git reflog` is always available too.
- **Clean tree required** — no auto-stash. A dirty tree means the
  rebase scope isn't clear; commit or stash manually first.
- **`--force-with-lease`** — rejects the push if someone else pushed
  while you rebased. The skill stops; it does NOT silently re-fetch
  and re-rebase (lost-update risk).
- **Default-branch refusal** — exit 2 if run while checked out on
  `main` (or the repo's configured default).
- **Worktree-safe** — only the current worktree's branch is touched, or, with
  `--worktree <path>`, only that path. The skill never creates or removes the
  worktree it is pointed at; the caller owns it.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — banner cleared, or no-op (already up-to-date / UNKNOWN) |
| 2 | Bad arguments / default branch / no PR for current branch / remote missing |
| 3 | PR has merge conflicts — `/gh-pr-resolve-conflict` is the right tool |
| 4 | Rebase produced conflicts — `/gh-pr-resolve-conflict` is the right tool |
| 5 | `gh` CLI not authenticated |
| 6 | `--force-with-lease` rejected (remote advanced — re-fetch and retry) |

## Related skills

- `gh:pr-resolve-conflict` — sister skill for actual file conflicts.
  Same rebase-and-force-with-lease structure, but walks through each
  conflicting file with the user.
- `gh:pr-resolve-ci-fail` — sister skill for `CI fail` label. Reads
  failing check logs, fixes locally, pushes (no force), removes the
  label last.
- `gh:pr-merge` — once the banner clears, merge with rebase/squash/merge.
- `gh:pr-reply` — reply to review comments after syncing the base.
