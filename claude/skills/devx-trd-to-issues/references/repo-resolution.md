# devx:trd-to-issues — Repo resolution

Substep procedure for Step 1 "Resolve Repo" — the skill keeps the
workflow in `SKILL.md`; the substeps and error shape live here so
multiple skills can reuse the convention.

## Substeps

1. `git rev-parse --show-toplevel` — confirm we're in a git repo.

2. Determine the target remote:
   - If the user passed `--remote <name>`, use that.
   - Otherwise default to `origin`.

3. Validate the remote and resolve owner/repo:

   ```bash
   git remote get-url <remote-name>
   ```

   On failure, list available remotes (`git remote -v`) and stop:

   ```
   Error: remote '<remote-name>' not found. Available remotes:
   origin    https://github.com/user/repo.git (fetch)
   upstream  https://github.com/org/repo.git (fetch)
   ```

4. Extract `owner/repo` from the URL:

   - `https://github.com/<owner>/<repo>.git` → `<owner>/<repo>`
   - `git@github.com:<owner>/<repo>.git`     → `<owner>/<repo>`

   Stripped of any trailing `.git`.

Store the resolved value as `TARGET_REPO` for use in Step 4 (`--apply`).

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and lands milestones/issues on the wrong repo.
