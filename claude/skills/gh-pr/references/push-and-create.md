# Push and Create — branch push policy + PR creation command

Used in Step 5 of the `gh:pr` skill, after the body is drafted.

## Push policy

| Upstream state | Action |
|---|---|
| No upstream tracking | `git push -u origin HEAD` |
| Upstream points at a **different-named branch** (`@{u}` ≠ `<remote>/<current-branch>`) | `git push -u origin HEAD` to re-pair. Do NOT use bare `git push` here — under `push.default=upstream` the feature branch's commits land directly on the upstream branch (measured: `feature -> main`); under the default `simple` it aborts. In this state `git status`'s ahead/behind is computed against base, so the "diverged" row's verdict is also unreliable here. |
| Upstream exists, local ahead, no divergence | `git push` |
| Upstream diverged (force-push needed) | **STOP** — ask the user before force-pushing. Never force-push without explicit approval. |

Detect upstream with `git rev-parse --symbolic-full-name @{u} 2>/dev/null`
(already gathered in Step 1b — do not spend another `git`/`gh` round-trip).
Compare with `git status -sb` or
`git rev-list --left-right --count @{u}...HEAD`.

Mispair detection reuses that same `$UPSTREAM`:

```bash
CUR=$(git rev-parse --abbrev-ref HEAD)
UPSTREAM_NORM="${UPSTREAM#refs/remotes/}"
[ -n "$UPSTREAM_NORM" ] && [ "$UPSTREAM_NORM" != "origin/$CUR" ] && MISPAIRED=1
```

The strip is load-bearing: `--symbolic-full-name` yields
`refs/remotes/origin/main`, which never equals `origin/$CUR` — comparing the
raw value would flag *every* branch as mispaired. `gh_pr_normalize_upstream`
in `references/branch-state.md` is the reusable form of that same strip.

This row is the *normal* state after `git worktree add ... -b <branch>` off
`origin/main`: git's `branch.autoSetupMerge` points the new branch at its
start point until the first `-u` push. It is not a rare misconfiguration.

Accepted trade-off: if the user *intentionally* tracks a differently-named
remote branch (local `fix` -> `origin/hotfix-2026-08`), `push -u origin HEAD`
creates a new same-named remote branch instead of respecting the old tracking
target. That is acceptable — `gh:pr`'s job is "open a PR from the current
branch", and a same-named remote branch is the normal/expected state. Known,
accepted side effect.

Executable SSOT for the rows above (`gh_pr_push_action`,
`gh_pr_upstream_is_mispaired`) lives in `references/branch-state.md`, mirrored
1:1 by `tests/bats/skills/_fixtures/gh_pr_push_policy.sh`.

## PR creation command

Once the push succeeds, create the PR with the command and flags documented
in `references/pr-body-template.md` (mktemp body file, `--assignee @me`,
labels applied after creation).

The base branch passed to `gh pr create --base` is `$BASE_BRANCH` from
Step 1a — that variable is set by the stacked-PR detection block (see
`references/stacked-pr.md`) and may be either the repo default branch
or the head ref of an auto-detected / explicitly-overridden parent PR.
Always use the variable; never hard-code the default branch name here.
