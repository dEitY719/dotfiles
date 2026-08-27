# Mergeable triage matrix

Step 2 maps the host-pinned `gh pr view --repo "$TARGET_REPO" --json
mergeable,mergeStateStatus,baseRefName,headRefName,url` (see
`references/github-target.md`) to an action:

| `mergeable` | `mergeStateStatus` | Action |
|---|---|---|
| `MERGEABLE` | `CLEAN`/`UNSTABLE` | `[OK] PR은 이미 up-to-date — nothing to do.` exit 0 (NF-1) |
| `MERGEABLE` | `BEHIND` | proceed to Step 3 (the case this skill handles) |
| `CONFLICTING` | — | `[FAIL] PR has merge conflicts — use /gh:pr-resolve-conflict` + exit 3 |
| `UNKNOWN` | — | GitHub still computing; print hint + exit 0 (retry later) |

`BLOCKED` alone (CI/approval pending) is not an out-of-date case — not handled here.

Step 2's `--json` list already carries `headRefName` alongside `baseRefName`;
keep it, `--worktree` mode's push needs it (below).

## Step 3/4 in `--worktree <path>` mode

Same two commands, redirected — no `cd`, and the session's checkout is left
alone:

```bash
git -C "<path>" fetch "$REMOTE" "$BASE"
git -C "<path>" rebase "$REMOTE/$BASE"
```

The push is the one place the command itself changes shape. The scratch
worktree is detached, so `HEAD` alone names no destination branch and `git`
refuses it; spell the refspec out with the `headRefName` from Step 2:

```bash
git -C "<path>" push --force-with-lease "$REMOTE" HEAD:refs/heads/$HEAD_REF
```

Without `--worktree` nothing here changes: bare `git fetch` / `git rebase`, and
`git push --force-with-lease "$REMOTE" HEAD`.

## Step 5 verification

After the push, re-read `--json mergeable,mergeStateStatus,url`:

- `mergeStateStatus ∈ {CLEAN, UNSTABLE, BLOCKED}` → banner cleared
  (`BLOCKED` here = CI/approval pending, normal).
- Still `BEHIND` → push didn't land; print PR URL, do not loop.
