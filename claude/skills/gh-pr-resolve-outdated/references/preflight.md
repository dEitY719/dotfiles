# Step 1 — args, repo resolution, and hard preconditions

Positional args: `[pr-number] [remote]`, both optional.

- `remote` — default `origin`; missing → `git remote -v` + exit 2. Bind
  `TARGET_HOST` + `TARGET_REPO` from that one remote URL **before any `gh`
  call**, per `references/github-target.md` (#1403).
- `pr-number` — if omitted, auto-detect via `GH_HOST="$TARGET_HOST" gh pr view
  --json number,headRefName,baseRefName,url,mergeable,mergeStateStatus` on the
  current branch. No PR → `[FAIL] no PR for current branch — pass PR#
  explicitly` + exit 2. `--repo` is deliberately omitted **on this one call**:
  `gh` requires an explicit PR argument whenever `--repo` is set (`argument
  required when using the --repo flag`), which would defeat the branch
  detection. The `GH_HOST=` prefix still pins the server and `gh` infers the
  repo from the current checkout's remotes on that host — see
  `references/github-target.md` → "Exception". Every later `gh pr view <N>`
  passes a positional and keeps `--repo "$TARGET_REPO"`.
- `gh` not authenticated → `[FAIL] gh CLI not authenticated — run gh
  auth login` + exit 5.

**Hard preconditions** (any fail → stop):

- inside a git repo
- current branch ≠ repo default (`[FAIL] cannot run on default branch` + exit 2)
- clean working tree (no auto-stash)
- no in-progress rebase / merge / cherry-pick

Capture `BACKUP_SHA=$(git rev-parse HEAD)` and print it for
`git reset --hard <sha>` recovery.
