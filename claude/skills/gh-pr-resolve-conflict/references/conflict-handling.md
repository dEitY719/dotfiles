# gh:pr-resolve-conflict — Conflict Handling

## `--worktree <path>`: paths are not relative to this session

Every `git` command below takes `-C "<path>"`, and `git status --short` then
prints paths relative to **that** worktree, not to the session's working
directory. `Read` and `Edit` have no `-C`, so join them yourself — call the
tools on `<path>/<relative-path>` (an absolute path, since the train passes an
absolute `<path>`). Editing the unjoined path silently rewrites the same file
in whatever checkout this session happens to be sitting in — a wrong-repo edit
that no rebase step would catch.

Shell commands have the same gap: run any lockfile regeneration with the
worktree as its working directory, e.g. `(cd "<path>" && uv lock)`, since `uv`
/ `npm` / `pnpm` / `cargo` take no `-C`.

## Per-commit loop

After `git rebase` stops on a conflict, repeat until `git rebase --continue`
succeeds or the user aborts:

1. **List** — `git status --short | grep -E '^(UU|AA|DU|UD|AU|UA|DD) '`.
   If the list is empty (`--continue` was not run yet but there are no
   `U*` paths), fall through and run `git rebase --continue` directly.
2. **Context** — print both:
   - Commits still to apply:
     `git log --oneline "$REMOTE/$BASE"..HEAD` (then the cursor).
   - The commit currently being applied:
     `git log -1 --format='%h %s%n%b' REBASE_HEAD`.
3. **Resolve each file** — for every path:
   - `Read` the file (include conflict markers).
   - Decide intent from the commit message. If the intent is ambiguous
     (both sides touched the same unrelated logic, or the commit
     message is a generic "fix"), **ask the user which side to keep**.
   - Edit the file to resolve; remove all `<<<<<<<`, `=======`, `>>>>>>>`.
   - `git add <file>`.
4. **Sanity check** — `git diff --cached --check` to catch whitespace
   errors, and `git grep -n '^\(<<<<<<<\||=======\|>>>>>>>\)'` to catch
   leftover markers.
5. **Continue** — `git rebase --continue`. If the editor opens for a
   commit message, accept the default unless the user asked to amend.
6. **Loop** — back to step 1 if more conflicts surface.

## When to suggest `git rebase --abort`

Offer `--abort` if any of these apply:

- The user says "stop" / "abort" / "멈춰" / "되돌려".
- The same file conflicts in three or more consecutive commits. That's
  often a sign the rebase is painful and should be planned differently
  (see "Interactive rebase suggestion" below).
- A conflicted file touches >500 lines or a `package-lock.json` /
  `uv.lock` / `pnpm-lock.yaml`. These lockfiles are almost always
  better resolved by regeneration than by hand-merging.

Print the command; do not run it for the user.

```
Rebase looks painful. Consider:
  git rebase --abort
  git reset --hard <BACKUP_SHA>   # back to where you started
Then decide: squash commits first, regenerate lockfiles, or keep pushing.
```

## Interactive rebase suggestion

If the same path conflicts in multiple sequential commits, suggest — but
do NOT run — squashing those commits first:

```
Commits <a>, <b>, <c> all touch the same file and conflict each round.
Consider squashing them before rebasing:
  git rebase --abort
  git reset --hard <BACKUP_SHA>
  git rebase -i "$REMOTE/$BASE"   # mark b, c as 'squash'
  # then re-run /gh-pr-resolve-conflict
```

## Lockfile conflicts

For `uv.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`,
`Cargo.lock`:

1. Accept the base version: `git checkout --theirs <lockfile>`.
2. Regenerate from the matching manifest in this commit:
   `uv lock` / `npm install --package-lock-only` / `pnpm install
   --lockfile-only` / `yarn install` / `cargo generate-lockfile`.
3. `git add <lockfile>`, then continue.

If the manifest itself conflicts, resolve the manifest first, then the
lockfile.

## Detecting user-side abort

If between iterations `.git/rebase-merge` and `.git/rebase-apply` both
disappear and `HEAD` is back to `BACKUP_SHA`, the user ran
`git rebase --abort` in another shell. Stop cleanly:

```
Rebase aborted (HEAD = BACKUP_SHA). No changes pushed.
```

## Stop points (never auto-proceed past these)

- "this file is mine, I'll handle it" / "내가 직접 할게" — stop, print
  `git status` and leave the tree in its conflicted state for the user.
- Conflict in a file the user has not mentioned and whose intent can't
  be inferred from the commit message — stop and ask.
- Any edit that would drop a hunk the user hasn't seen — show the hunk
  first.

In `--worktree` mode, the "leave the tree in its conflicted state" instruction
above still applies — at `<path>`, not the session's own checkout. This skill
never deletes `--worktree`'s path itself (SKILL.md constraint); when the
caller is `gh:pr-merge-train`, it reports `<path>` and leaves it in place too
for the same reason — see `gh-pr-merge-train/references/train-loop.md` →
"Teardown — the one exception".
