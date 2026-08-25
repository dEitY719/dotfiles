# gh:issue-relay-flow — Destination Remote + Branch Setup

Detailed procedure for Step 2.

## Resolve `--remote`

Resolve exactly as `gh:relay-merge` does in
`claude/skills/gh-relay-merge/references/remote-resolution.md` — same
default (`upstream`), same hard-error-on-missing-remote rule, same
never-fall-back-to-`origin` rule. Do not re-derive this logic here; if that
file's procedure changes, this skill inherits the change by reference.

That procedure also binds `DEST_REPO` **and** `DEST_HOST` from the one
destination remote URL. Both are required downstream: Step 3's issue fetch
runs as `GH_HOST="$DEST_HOST" gh issue view <N> --repo "$DEST_REPO" ...`,
and `gh:relay-merge` re-resolves the same pair for its own calls. Never
export a single global `GH_HOST` in this flow — `origin` and the destination
are deliberately different hosts (#1403 / #1407).

```
Error: no 'upstream' remote and no --remote given.
origin is the internal remote and is never a relay destination.
Pass --remote <name-or-URL> explicitly.
```

## Detect the destination default branch

Unless `--base <branch>` was given:

```bash
DEFAULT_BRANCH=$(git ls-remote --symref "$REMOTE" HEAD \
  | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2}')
git fetch "$REMOTE" "$DEFAULT_BRANCH"
```

If `--base` was given, skip detection and `git fetch "$REMOTE" "$BASE"`
directly; treat `$BASE` as `$DEFAULT_BRANCH` for the rest of this file.

## Branch naming: `issue-<N>-<title-slug>`

Slugify the issue title: lowercase, strip punctuation, collapse
whitespace/special characters to single hyphens. Example: issue #1346
titled "feat(skills): gh:issue-relay-flow 신설 + gh:relay-merge push-probe
버그 수정" → `issue-1346-feat-skills-gh-issue-relay-flow` (truncate an
overlong slug; the issue number prefix is what matters for lookup).

**Why issue-number-first, not `wt/<agent>/<N>`:** this session itself runs
on a worktree branch prefixed `issue-1346` (e.g. `wt/issue-1346/1`), so an
issue-number-first branch name greps consistently alongside it — searching
`issue-1346` finds both the worktree branch and this flow's working branch.
This is deliberately a *different* namespace from `ai-worktree-spawn`'s
`wt/<agent>/<N>` convention — that one names a *worktree* (an agent-owned
sandbox), this one names a *working branch inside an existing worktree*
that will be pushed via relay. Do not conflate the two.

## Create or reuse

```bash
git checkout -b "issue-<N>-<slug>" "$REMOTE/$DEFAULT_BRANCH"
```

If a local branch with that exact name already exists, `checkout -b` fails.
Handle it instead of erroring out:

1. `LOCAL_TIP=$(git rev-parse issue-<N>-<slug>)` and
   `DEST_TIP=$(git rev-parse "$REMOTE/$DEFAULT_BRANCH")`.
2. **`LOCAL_TIP == DEST_TIP`** — the branch is a clean, unmodified snapshot
   of the destination default branch. Just `git checkout issue-<N>-<slug>`
   and continue; no confirmation needed.
3. **`LOCAL_TIP != DEST_TIP`** — check for unique work first:
   ```bash
   git log "$REMOTE/$DEFAULT_BRANCH..issue-<N>-<slug>" --oneline
   ```
   - **Any commits listed** — the branch has work not on the destination.
     **Never reset automatically.** Tell the user: "Branch `issue-<N>-<slug>`
     has N unique commit(s) not on `$REMOTE/$DEFAULT_BRANCH`: <list>. Reset
     to `$REMOTE/$DEFAULT_BRANCH` (discarding them) or keep and continue on
     top of them?" — wait for the answer.
   - **No commits listed** — the branch is just a stale snapshot (destination
     moved forward, or a local no-op commit predates it with no unique diff
     content). Ask before touching it anyway ("branch `issue-<N>-<slug>`
     is stale relative to `$REMOTE/$DEFAULT_BRANCH` but has no unique
     commits — reset it?"), then on yes:
     ```bash
     git checkout issue-<N>-<slug>
     git reset --hard "$REMOTE/$DEFAULT_BRANCH"
     ```

Never silently pick a resolution for case 3 — both branches of it require
an explicit user answer before mutating anything.
