# gh:pr-resolve-ci-fail — GitHub target binding (#1403, #1407)

Run this in Step 1, **before any `gh` call**.

## Bind the target

Resolve the host **and** the repo from one and the same remote URL, then export
the host so every sourced helper inherits it:

```bash
REMOTE="${REMOTE:-origin}"
. "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "$REMOTE") || exit 1
TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST
```

- `gh_host.sh` is the SSOT for the URL to host mapping — never copy a regex or a
  domain list into this file.
- `_gh_resolve_host` (setup-mode to host) is the fallback used **only** when
  there is no remote URL to parse.
- An unknown remote stops the run with `git remote -v` — never a silent
  `origin` fallback, which would mask a typo and target the wrong repo.
- Never continue with an empty `TARGET_HOST` — that is exactly the silent
  misroute state of #1403.

## Host targeting rule

Every `gh` call in this skill — SKILL.md and `references/` alike — runs as:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`gh api` is the one exception to the flag: it has no `--repo`, so the repo goes
into the path instead — `gh api "repos/$TARGET_REPO/..."`, never a literal
`{owner}/{repo}`.

## Why

`--repo <owner>/<repo>` carries no host, so a bare `gh` resolves that slug
against gh CLI's own `gh repo set-default` rather than git's `$REMOTE`. On a
dual-host login (github.com + a GHES instance) the two can disagree and `gh`
then hits the wrong server **with no error** — #1403 is the case where an OPEN
issue came back as "not found".

This skill also writes: the Step 7 `CI fail` label DELETE and the ai-metrics
comment are the same misroute with a mutation attached, so the host pin is a
correctness requirement, not a nicety.
