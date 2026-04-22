# gh:pr-resolve-conflict — Rebase Flow

## Preconditions (parallel batch)

Run all four in a single tool message. Any failure → stop immediately.

```bash
git rev-parse --is-inside-work-tree
git rev-parse --abbrev-ref HEAD
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
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

## Resolve base branch

Prefer the PR's actual base (not the repo default):

```bash
BASE=$(gh pr view "$PR" --repo "$TARGET_REPO" --json baseRefName -q .baseRefName)
```

Fall back to `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
only when auto-detecting a PR and `gh pr view` returned nothing yet.

## Fetch + rebase

```bash
git fetch "$REMOTE" "$BASE"
BACKUP_SHA=$(git rev-parse HEAD)
echo "backup SHA: $BACKUP_SHA  (git reset --hard $BACKUP_SHA to undo)"
git rebase "$REMOTE/$BASE"
```

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

Rejection modes:

| Reason | Action |
|---|---|
| "stale info" (someone pushed to the branch) | **stop**; print `git fetch $REMOTE && git log --oneline HEAD..$REMOTE/<branch>` hint; do NOT auto re-rebase |
| "protected branch" | stop; the branch is write-protected, user handles it |
| network / auth | stop; surface stderr |

Never substitute `--force` for `--force-with-lease`.

## Verify mergeable

```bash
gh pr view "$PR" --repo "$TARGET_REPO" \
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
