# Step 1 — args, repo resolution, and hard preconditions

Positional args: `[pr-number] [remote]`, both optional.

- `pr-number` — if omitted, auto-detect via `gh pr view --json
  number,headRefName,baseRefName,url,mergeable,mergeStateStatus` on the
  current branch. No PR → `[FAIL] no PR for current branch — pass PR#
  explicitly` + exit 2.
- `remote` — default `origin`. Resolve `TARGET_REPO` via `git remote
  get-url <remote>`; missing → `git remote -v` + exit 2.
- `gh` not authenticated → `[FAIL] gh CLI not authenticated — run gh
  auth login` + exit 5.

**Hard preconditions** (any fail → stop):

- inside a git repo
- current branch ≠ repo default (`[FAIL] cannot run on default branch` + exit 2)
- clean working tree (no auto-stash)
- no in-progress rebase / merge / cherry-pick

Capture `BACKUP_SHA=$(git rev-parse HEAD)` and print it for
`git reset --hard <sha>` recovery.
