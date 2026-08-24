# gh:issue-flow — Binding the GitHub target (#1403)

Step 1 resolves the host and repo from the `[remote]`'s URL once and exports
them, so the composition's own `gh` call cannot drift to another server.

```bash
. "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "${REMOTE:-origin}")
TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL")
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST
```

## Why the host is passed explicitly

Step 2.6's `gh api "repos/$TARGET_REPO/..."` — the only `gh` call this
composition makes directly — takes `GH_HOST="$TARGET_HOST"` explicitly; the
repo slug is already in its path. Without the host, `gh` follows its own
`gh repo set-default` rather than git's `origin`, and on a dual-host login
(github.com + GHES) it hits the wrong server with no error.

## Chain-wide since #1405

The export used to be a best-effort default only: `gh:commit` and `gh:pr` each
re-resolved their own target from `origin`, so `/gh-issue-flow <N> upstream`
still landed the commit's ai-metrics call and the PR itself on `origin` (PR
#1404 review, codex). That gap is closed — `[remote]` is now threaded
explicitly into every sub-skill that talks to GitHub:

| Step | Sub-skill | Receives `[remote]` |
|---|---|---|
| 2.1 | `gh:issue-implement` | yes |
| 2.2 | `gh:commit` | yes (#1405) |
| 2.3 | `gh:pr` | yes (#1405) |
| 2.4 | `devx:pr-review-all` | yes (#1405) |

So `/gh-issue-flow <N> upstream` implements, commits, opens the PR and reviews
it on `upstream`, never on `origin`.
