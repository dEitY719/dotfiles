# gh:issue-proceed — Repo resolution

Detailed procedure for Step 1 remote validation and owner/repo extraction.
SKILL.md keeps only the workflow; this file holds the substeps and
error-message shape. (Same procedure as `/gh:issue-implement` — kept as a
self-contained copy per the dotfiles per-skill references convention.)

## Substeps

1. `git rev-parse --show-toplevel` — confirm we're in a git repo.

2. Determine the target remote:
   - If the user passed an argument, use it as remote name.
   - Otherwise default to `origin`.

3. Validate the remote and resolve owner/repo:

   ```bash
   git remote get-url <remote-name>
   ```

   If this fails, list available remotes (`git remote -v`) and stop with
   an error like:

   ```
   Error: remote '<remote-name>' not found. Available remotes:
   origin  https://github.com/user/repo.git (fetch)
   upstream  https://github.com/org/repo.git (fetch)
   ```

4. Extract `owner/repo` **and the host** from the remote URL returned in
   step 3. Both must come from that one URL — never from two sources:

   ```bash
   . "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
   REMOTE_URL=$(git remote get-url "${REMOTE:-origin}") || exit 1
   TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
   TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
   export GH_HOST="$TARGET_HOST"
   export TARGET_REPO TARGET_HOST
   ```

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

   `gh_host.sh` is the host/URL mapping SSOT — do not copy a domain list or
   regex into this file. `_gh_resolve_host` (setup-mode → host) is only the
   fallback for when there is no remote URL to parse.

Store the results as `TARGET_REPO` and `TARGET_HOST` for use in Step 2 of the
main workflow.

## Host targeting rule (issues #1403 / #1407)

Every `gh` call this skill runs — the Step 2.1 fetch/claim, the Step 3
protocol directives, the Step 4 report — names both host and repo:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo <owner>/<repo>` carries no host, so a bare `gh` follows its own
`gh repo set-default` instead of git's remote. On a dual-host login
(github.com + GHES) the two disagree and the call silently hits the wrong
server — an OPEN issue comes back "not found" (#1403), or worse, a
directive's write (self-assign, comment, close) lands in the wrong repo.

`export GH_HOST` in Step 1 also makes the sourced helpers
(`gh_project_status.sh`) inherit the same host; the reference files still
spell the prefix out so every example stays copy-paste safe.

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and proceeds against the wrong repo.

If `_gh_host_from_url` fails (a remote that is not a github host), fall back
to `_gh_resolve_host` — but never proceed with an empty `TARGET_HOST`, which
is exactly the silent-misroute state #1403 described.
