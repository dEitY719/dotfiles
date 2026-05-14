# gh:discussion-create — Repo resolution

Detailed procedure for Step 1 "Detect Repo Context" — remote validation
and `owner/repo` extraction. SKILL.md keeps only the workflow; this
file holds the substeps and error-message shape. Mirrors
`gh-issue-create/references/repo-resolution.md` so behaviour stays
consistent across the gh-* skill family.

## Substeps

1. `git rev-parse --show-toplevel` — confirm we are in a git repo.

2. Determine the target remote:
   - If a non-flag positional that does NOT match a known category
     (`Ideas`, `Q&A`, `Announcements`, `Lessons`) was passed, use it
     as the remote name.
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

Store the resolved `owner/repo` as `TARGET_REPO` for use in Step 4 of
the main workflow.

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and posts Discussions in the wrong repo.

## Why this lives in a separate file

The skill body keeps the workflow scannable. The remote-validation
detail is shared with `gh:issue-create` and (eventually)
`gh:discussion-convert`; centralising the contract here lets each
skill summarise it in two lines while linking to one source of truth.
