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

4. Extract `owner/repo` from the remote URL returned in step 3:

   - `https://github.com/<owner>/<repo>.git` -> `<owner>/<repo>`
   - `git@github.com:<owner>/<repo>.git`     -> `<owner>/<repo>`

Store the resolved `owner/repo` as `TARGET_REPO`. Split into
`_owner="${TARGET_REPO%%/*}"` and `_repo="${TARGET_REPO##*/}"` for the
GraphQL helpers in `gh_discussion.sh`.

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
