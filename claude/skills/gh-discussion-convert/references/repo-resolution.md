# gh:discussion-convert — Repo resolution

Detailed procedure for Step 1 "Detect Repo Context". Mirrors
[`gh-discussion-create/references/repo-resolution.md`](../../gh-discussion-create/references/repo-resolution.md)
so all gh-discussion-* skills behave identically.

## Substeps

1. `git rev-parse --show-toplevel` — confirm we are in a git repo.

2. Determine the target remote:
   - If a second non-flag positional was passed (after the discussion
     number), treat it as the remote name.
   - Otherwise default to `origin`.

3. Validate the remote and resolve owner/repo:

   ```bash
   git remote get-url <remote-name>
   ```

   If this fails, list available remotes (`git remote -v`) and stop
   with an error like:

   ```
   Error: remote '<remote-name>' not found. Available remotes:
   origin    https://github.com/user/repo.git (fetch)
   upstream  https://github.com/org/repo.git  (fetch)
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

   - `https://github.com/<owner>/<repo>.git` -> `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` -> `github.samsungds.net`
     + `<owner>/<repo>`

   `gh_host.sh` is the host/URL mapping SSOT — do not copy a domain list or
   regex into this file. `_gh_resolve_host` (setup-mode -> host) is only the
   fallback for when there is no remote URL to parse.

Store the results as `TARGET_REPO` and `TARGET_HOST`. Split the repo into
`_owner="${TARGET_REPO%%/*}"` and `_repo="${TARGET_REPO##*/}"` for the
GraphQL helpers in `gh_discussion.sh` — they inherit the exported `GH_HOST`,
so the Discussion mutations hit the same server as the Issue creation.

## Host targeting rule (issues #1403 / #1407)

Every `gh` call this skill runs names both host and repo:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo <owner>/<repo>` carries no host, so a bare `gh` follows its own
`gh repo set-default` rather than git's remote. On a dual-host login
(github.com + GHES) the two disagree and the call silently hits the wrong
server. Here that is worse than a bad read: Step 4's idempotency search
would miss an existing Issue and Step 5 would create the promoted Issue in
the wrong repo, splintering the very backlink chain this skill exists to
keep intact.

## Failure rule

If the user-specified remote does not exist, fail immediately with
the list of available remotes. **Do not** fall back to `origin`
silently — that masks typos and converts a Discussion in the wrong
repo, splintering the SSOT chain across forks.

## Why this lives in a separate file

Same reason as the create-side skill: the workflow stays scannable in
SKILL.md while the remote-validation detail lives in one place that
all gh-discussion-* skills can link to. Update both at once — they
must stay byte-equivalent in substance.
