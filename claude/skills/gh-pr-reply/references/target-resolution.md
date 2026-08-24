# gh:pr-reply — Resolving the Target PR and Repo (Step 1)

Positional args: `<pr-number> [remote]` (`remote` defaults to `origin`).
Full argument table: `references/help.md`.

## PR number precedence

1. **Explicit arg** — `/gh:pr-reply 123` → PR #123.
2. **Current branch** — `gh pr view --json number,url,headRefName,baseRefName`;
   stop if the branch has no PR.
3. Never guess, and never pick "the latest PR".

## TARGET_REPO

Resolve from the `[remote]` positional, not from `gh`'s default-repo heuristic,
so a repo with two remotes on the same host (e.g. `origin` + `upstream`) replies
to the intended one. Bind `remote` to the positional (default `origin`), source
the SSOT helper, and parse the remote's URL (network-free):

```sh
# DOTFILES_FORCE_INIT=1 is load-bearing: the file's interactive guard
# otherwise returns early in a non-interactive shell and the helper is
# never defined. `remote` is the [remote] positional; ${remote:-origin}
# keeps the block self-contained whether or not it was set.
export DOTFILES_FORCE_INIT=1
. "${SHELL_COMMON}/functions/gh_pr_review.sh"
TARGET_REPO=$(_gh_pr_review_resolve_target_repo "${remote:-origin}") || {
  echo "Cannot resolve remote '${remote:-origin}' to a repo" >&2; exit 1; }
```

Pass `TARGET_REPO` (`--repo "$TARGET_REPO"` / `-R`, or as the
`repos/$TARGET_REPO/...` path) on **every** subsequent `gh` API call.

## Default-remote tradeoff

`[remote]` defaults to `origin`. This is more predictable than the old
`gh repo view` default-repo heuristic, but note the fork workflow where `origin`
is your fork and `upstream` is the canonical repo: there, reply explicitly with
`/gh:pr-reply <N> upstream`. On the `devx:pr-review-all` / `gh:issue-flow` path
the remote is threaded through, so the default only applies to a bare manual
`/gh:pr-reply <N>`.
