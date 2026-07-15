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

6. Extract `owner/repo` from the resolved URL for `gh` calls that need
   `--repo` (the destination issue/comment in Step 6):

   - `https://github.com/<owner>/<repo>.git` → `<owner>/<repo>`
   - `git@github.com:<owner>/<repo>.git` → `<owner>/<repo>`

   Store as `DEST_REPO`.

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
