# gh:issue-read — Repo resolution

Detailed procedure for Step 1 "Detect Repo Context" — remote validation and
owner/repo extraction. SKILL.md keeps only the workflow; this file holds
the substeps and error-message shape.

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

4. Extract `owner/repo` from the remote URL returned in step 3:

   - `https://github.com/<owner>/<repo>.git` → `<owner>/<repo>`
   - `git@github.com:<owner>/<repo>.git` → `<owner>/<repo>`

Store the resolved `owner/repo` as `TARGET_REPO` for use in Step 4 of the
main workflow.

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and creates issues in the wrong repo.
