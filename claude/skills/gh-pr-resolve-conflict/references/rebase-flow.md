# gh:pr-resolve-conflict — Rebase Flow

Every `gh` call below assumes `TARGET_HOST` / `TARGET_REPO` are already bound
and exported by Step 1 per `references/github-target.md` (#1403, #1407).

## `--worktree` mode

When Step 1 parsed `--worktree <path>`, every **git** command in this file runs
as `git -C "<path>" ...` — preconditions, base resolution, fetch, rebase,
status, push. The `gh` calls are unaffected: they read the PR from the API, not
from a checkout. The push additionally switches to an explicit refspec (see
"Push"). No `cd`, ever: leaving the session's own working directory alone is
the reason the flag exists.

The path is a detached scratch worktree `gh:pr-merge-train` created for exactly
this call and will remove afterwards (#1493) — this skill never creates or
deletes it.

Without the flag every command below is read literally, unchanged.

## Preconditions (parallel batch)

Run all four in a single tool message. Any failure → stop immediately.

```bash
git rev-parse --is-inside-work-tree
git rev-parse --abbrev-ref HEAD
GH_HOST="$TARGET_HOST" gh repo view --repo "$TARGET_REPO" --json defaultBranchRef -q .defaultBranchRef.name
git status --porcelain
ls "$(git rev-parse --git-path rebase-merge)" \
   "$(git rev-parse --git-path rebase-apply)" \
   "$(git rev-parse --git-path MERGE_HEAD)" \
   "$(git rev-parse --git-path CHERRY_PICK_HEAD)" 2>/dev/null
```

Use `git rev-parse --git-path <name>` instead of hardcoded `.git/<name>`
— in a git worktree the real path is `.git/worktrees/<wt>/<name>`, and
hardcoded paths silently miss the in-progress marker.

Stop conditions:

| Check | Stop reason |
|---|---|
| not a git repo | "not inside a git repository" |
| current branch == default | "refuse to rebase the default branch" |
| any of `rebase-merge` / `rebase-apply` / `MERGE_HEAD` / `CHERRY_PICK_HEAD` exists (resolved via `git rev-parse --git-path`) | "rebase/merge/cherry-pick already in progress — finish or abort first" |

Dirty working tree is NOT a stop — it triggers the stash flow in
`safety.md`.

In `--worktree` mode a freshly created detached worktree is headless and clean,
so `git status --porcelain` is empty by construction (no stash flow) and
`--abbrev-ref HEAD` answers `HEAD` rather than a branch name — the
default-branch refusal is made against `HEAD_REF` instead, per `safety.md` →
"Never run on the default branch". The git-repo and in-progress-marker checks
still run under `-C "<path>"`: a scratch directory left behind by an interrupted
run can be handed over mid-rebase.

## Resolve base branch

Prefer the PR's actual base (not the repo default). Read the head ref in the
same call — `--worktree` mode's push needs it:

```bash
REFS=$(GH_HOST="$TARGET_HOST" gh pr view "$PR" --repo "$TARGET_REPO" \
    --json baseRefName,headRefName)
BASE=$(printf '%s' "$REFS" | jq -r .baseRefName)
HEAD_REF=$(printf '%s' "$REFS" | jq -r .headRefName)
```

Fall back to `GH_HOST="$TARGET_HOST" gh repo view --repo "$TARGET_REPO" --json
defaultBranchRef -q .defaultBranchRef.name` only when auto-detecting a PR and
`gh pr view` returned nothing yet.

## Fetch + rebase

```bash
git fetch "$REMOTE" "$BASE"
BACKUP_SHA=$(git rev-parse HEAD)
echo "backup SHA: $BACKUP_SHA  (git reset --hard $BACKUP_SHA to undo)"
git rebase "$REMOTE/$BASE"
```

`--worktree` mode: `git -C "<path>" fetch ...`, `git -C "<path>" rev-parse HEAD`,
`git -C "<path>" rebase ...`.

Exit codes:

| Exit | Meaning | Action |
|---|---|---|
| 0 | clean rebase | go to push step |
| non-zero + conflicts | conflicts to resolve | enter conflict loop (`conflict-handling.md`) |
| non-zero + other | rebase failed to start | print stderr, suggest `git rebase --abort`, stop |

## Push

Only after `git rebase` exits 0 and `git status` is clean:

```bash
git push --force-with-lease "$REMOTE" HEAD
```

In `--worktree` mode, spell the destination out — the worktree is detached, so
bare `HEAD` gives `git` no branch to push to:

```bash
git -C "<path>" push --force-with-lease "$REMOTE" HEAD:refs/heads/$HEAD_REF
```

Rejection modes:

| Reason | Action |
|---|---|
| "stale info" (someone pushed to the branch) | **stop**; print `git fetch $REMOTE && git log --oneline HEAD..$REMOTE/<branch>` hint; do NOT auto re-rebase |
| "protected branch" | stop; the branch is write-protected, user handles it |
| network / auth | stop; surface stderr |

Never substitute `--force` for `--force-with-lease`.

## Verify mergeable

```bash
GH_HOST="$TARGET_HOST" gh pr view "$PR" --repo "$TARGET_REPO" \
  --json number,mergeable,mergeStateStatus,url
```

| `mergeable` | `mergeStateStatus` | Meaning |
|---|---|---|
| `MERGEABLE` | `CLEAN` / `UNSTABLE` | warning cleared, ready to merge (UNSTABLE = non-required CI pending) |
| `MERGEABLE` | `BEHIND` | rare; user should fetch and retry |
| `CONFLICTING` | `DIRTY` | GitHub still sees conflicts — stop, print URL |
| `UNKNOWN` | * | API hasn't settled; retry once after `sleep 2`, then stop if still unknown |

## Final report format

```
PR #<N> rebased onto <REMOTE>/<BASE>
  Backup SHA:   <sha>          (git reset --hard to undo)
  Pushed:       <new-sha>      (--force-with-lease)
  Mergeable:    <mergeable> / <mergeStateStatus>
  URL:          <pr-url>
```

If a stash was created and popped, append:

```
  Stash:        auto-stashed at preflight, popped after rebase
```

If the skill stopped before pushing, use:

```
gh:pr-resolve-conflict stopped at <step>
  Reason:       <short reason>
  Backup SHA:   <sha>
  Resume:       <command the user should run>
```

## Mergeable preflight (Step 1)

Immediately after resolving `PR_NUMBER`, short-circuit when there is
nothing to resolve:

```bash
MERGEABLE=$(GH_HOST="$TARGET_HOST" gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json mergeable --jq '.mergeable')
```

- `MERGEABLE == MERGEABLE` → print `[OK] PR은 이미 충돌 없음 — skip.` and stop (success).
- `MERGEABLE == UNKNOWN` → GitHub is still computing; continue the flow normally (do not skip).
- Any other value (`CONFLICTING` etc.) → continue.
