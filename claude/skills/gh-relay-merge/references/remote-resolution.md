# gh:relay-merge — Destination Remote Resolution

Detailed procedure for Step 1's `--remote` resolution. Mirrors
`gh-issue-implement`'s repo-resolution rule: **resolve, hard-error on a
missing remote, never silently fall back.** The convention in this repo's
asymmetric-network setup is `origin` = internal (isolated GHE),
`upstream` = external (github.com).

## Substeps

1. `git rev-parse --show-toplevel` — confirm we're in a git repo.

2. Determine the destination:
   - If `--remote <value>` was passed, use `<value>`.
   - Otherwise default to the remote literally named `upstream`.

3. Decide whether `<value>` is a **name** or a **raw URL**:
   - Contains `://` or matches `git@host:owner/repo` → treat as a raw URL.
   - Otherwise treat as a remote name.

4. **Name path** — validate and resolve the URL:

   ```bash
   git remote get-url "$REMOTE_NAME"
   ```

   If this fails, list available remotes (`git remote -v`) and stop:

   ```
   Error: remote '<name>' not found. Available remotes:
   origin    https://ghe.corp.example/team/repo.git (fetch)
   upstream  https://github.com/org/repo.git (fetch)
   ```

5. **Raw-URL path** — do not require a configured remote. Use the URL
   directly with `git ls-remote <url>` / `git push <url> ...`, or add a
   throwaway remote for the run:

   ```bash
   git remote add relay-tmp "$REMOTE_URL"   # remove in cleanup
   ```

6. Extract `owner/repo` **and the host** from the resolved URL. Both must
   come from that one URL — this skill exists to cross hosts, so a host
   taken from anywhere else (setup-mode, `gh repo set-default`) is exactly
   the #1403 misroute:

   ```bash
   . "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
   REMOTE_URL=$(git remote get-url "$REMOTE_NAME") || exit 1   # or "$REMOTE_URL" on the raw-URL path
   DEST_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
   DEST_HOST=$(_gh_host_from_url "$REMOTE_URL") || DEST_HOST=$(_gh_resolve_host)
   export DEST_REPO DEST_HOST
   ```

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

   `gh_host.sh` is the host/URL mapping SSOT — never copy a domain list or
   regex into this file. `_gh_resolve_host` (setup-mode → host) is only the
   fallback for a URL that parses to no known host.

7. Bind the **source** side the same way, from the source remote's URL
   (`origin` unless the run says otherwise). Step 1's PR-mode `gh pr view`
   reads the origin PR and must not inherit the destination's host:

   ```bash
   SOURCE_URL=$(git remote get-url "${SOURCE_REMOTE:-origin}") || exit 1
   SOURCE_REPO=$(_gh_parse_owner_repo_url "$SOURCE_URL") || exit 1
   SOURCE_HOST=$(_gh_host_from_url "$SOURCE_URL") || SOURCE_HOST=$(_gh_resolve_host)
   export SOURCE_REPO SOURCE_HOST
   ```

Downstream steps (2-6) refer to the resolved destination as `$REMOTE` — the
remote name on the name path, or the `relay-tmp` name added on the raw-URL
path.

## Host targeting rule (issues #1403 / #1407)

This skill talks to **two** hosts in one run, so it never exports a single
global `GH_HOST`. Every `gh` call carries the host of the side it targets,
inline:

```bash
GH_HOST="$SOURCE_HOST" gh <sub-command> ... --repo "$SOURCE_REPO"   # origin side
GH_HOST="$DEST_HOST"   gh <sub-command> ... --repo "$DEST_REPO"     # destination side
```

`--repo <owner>/<repo>` carries no host: `gh` resolves that slug against its
own `gh repo set-default`, not git's remote. On a dual-host login the two
disagree and the call silently succeeds against the wrong server — which for
a relay means posting the apply-guide back onto the isolated origin, where
the destination reader can never see it.

`gh gist create` and `gh api gists/...` are not repo-scoped, so they take the
host prefix only — see `references/gist-relay.md` for why that host is
`$DEST_HOST`.

## The default-`upstream` hard-error rule

If `--remote` was **omitted** and no remote named `upstream` exists, stop
immediately:

```
Error: no 'upstream' remote and no --remote given.
origin is the internal remote and is never a relay destination.
Pass --remote <name-or-URL> explicitly.
```

Do **not** fall back to `origin`. `origin` is the *source* of the relay
payload; relaying to it is always wrong, and a silent fallback would mask
a typo in the remote name.

## Reachability check

Before any patch work, confirm the destination actually answers:

```bash
git fetch "$REMOTE_NAME"          # name path
git ls-remote "$REMOTE_URL" >/dev/null   # raw-URL path
```

Reachability failing here is distinct from a *push* block — fetch is
expected to work even when push is proxy-blocked. If fetch itself fails,
stop and report (the destination is simply unreachable, not push-blocked).
