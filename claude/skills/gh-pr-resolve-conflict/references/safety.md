# gh:pr-resolve-conflict — Safety Nets

## Backup SHA

Always captured before `git rebase`:

```bash
BACKUP_SHA=$(git rev-parse HEAD)
```

Printed up front so the user can paste it into a recovery command:

```
backup SHA: <sha>
  undo everything :  git reset --hard <sha>
  inspect history :  git reflog
```

`git reflog` is always a fallback — every rebase step is tracked there
for ~90 days by default, so even `reset --hard` mistakes are usually
recoverable.

## Auto-stash

Triggered only when preflight detects a non-empty working tree
(`git status --porcelain` prints any line).

1. Announce before running:

    ```
    Working tree is dirty. Auto-stashing:
      git stash push -u -m "gh:pr-resolve-conflict auto-stash <timestamp>"
    ```

2. Stash:

    ```bash
    STASH_MSG="gh:pr-resolve-conflict auto-stash $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    git stash push -u -m "$STASH_MSG"
    STASH_REF=$(git rev-parse -q --verify refs/stash)
    ```

3. Proceed with fetch + rebase.

4. After a successful push (or on clean abort), pop:

    ```bash
    git stash pop "$STASH_REF" 2>/dev/null || \
      echo "stash preserved — resolve and then: git stash pop $STASH_REF"
    ```

5. If `pop` itself conflicts, stop and print the stash ref. Never drop
   the stash automatically.

## In-progress operation guard

```bash
for marker in \
  .git/rebase-merge .git/rebase-apply \
  .git/MERGE_HEAD .git/CHERRY_PICK_HEAD .git/REVERT_HEAD; do
    if [ -e "$marker" ]; then
        echo "in-progress operation detected: $marker"
        echo "finish or abort it first:"
        echo "  git rebase --continue / --abort"
        echo "  git merge --continue / --abort"
        echo "  git cherry-pick --continue / --abort"
        exit 1
    fi
done
```

## `--force-with-lease` vs `--force`

`--force-with-lease` refuses the push if the remote ref has moved since
you last fetched. That protects against:

- a reviewer pushing a fix directly to your branch while you rebased,
- an automation bot (dependabot, renovate) rebasing on top of you,
- another machine of yours pushing from the same branch.

Plain `--force` blows past all of that. This skill refuses to use it.

If `--force-with-lease` rejects the push, the upstream moved. Show:

```
Push rejected by --force-with-lease: upstream has new commits you haven't seen.
  git fetch <remote>
  git log --oneline HEAD..<remote>/<branch>
Decide whether to merge those in or discard them, then re-run this skill.
```

## Never run on the default branch

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
if [ "$CURRENT" = "$DEFAULT" ]; then
    echo "refuse: currently on the default branch ($DEFAULT)."
    echo "check out the PR's head branch first."
    exit 1
fi
```

The default branch should never be force-pushed by this skill. If the
PR's head IS the default branch (cross-fork PR where the head came from
a fork), that's out of scope — tell the user and stop.

## Recovery cheat-sheet (for the final report)

```
If something went wrong:
  git rebase --abort                 # during rebase
  git reset --hard <BACKUP_SHA>      # after rebase, before push
  git reflog                          # rummage for any lost ref
  git stash list                      # auto-stash survives even if pop fails
```
