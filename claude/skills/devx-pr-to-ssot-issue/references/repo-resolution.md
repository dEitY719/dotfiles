# devx:pr-to-ssot-issue — Repo resolution

Substep procedure for Step 1 "Resolve Repo". The convention matches the
sister skills (`devx:trd-to-issues`, `gh:issue-create`, `gh:pr`) so
operators don't have to re-learn it. The substeps live here so multiple
skills can reuse the same shape.

## Substeps

1. `git rev-parse --show-toplevel` — confirm we're in a git repo.

2. Determine the target remote:
   - If the user passed `--remote <name>`, use that.
   - Otherwise default to `origin`.

   The two cases below are NOT in conflict:
   - `--remote` omitted → silently use `origin` (matches `gh-issue-create`
     / `gh-pr` / `gh-pr-resolve-conflict` parity, the dotfiles
     convention).
   - `--remote <name>` passed but `<name>` does not exist → fail-fast.
     The "no silent fallback" rule below applies **only** to this
     second case.

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

4. Extract `owner/repo` from the URL — host-agnostic patterns so
   GitHub Enterprise / GHES / self-hosted forges work the same:

   - `<protocol>://<host>/<owner>/<repo>.git` → `<owner>/<repo>`
   - `<user>@<host>:<owner>/<repo>.git`       → `<owner>/<repo>`

   Stripped of any trailing `.git`. The host is never hardcoded; the
   `<host>` segment is whatever the remote URL points at.

Store the resolved value as `TARGET_REPO` for use in:

- Step 2 — `gh pr view` / `gh pr diff` against `TARGET_REPO`.
- Step 5 — `gh issue create --repo "$TARGET_REPO"` and the optional
  parent backlink comment.

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and would land the SSOT recovery issue on the wrong
repo, where it can't even be cross-referenced from the source PR.

## Cross-repo note

This skill always creates the new SSOT issue on the **same repo** as
the source PR (`TARGET_REPO`). Cross-repo recovery (e.g. SSOT lives in
repo A, PR lives in repo B) is intentionally out of scope — the
exception workflow assumes single-repo ownership of both runtime code
and SSOT docs. If a future variant needs cross-repo, route it through
a sister skill rather than overloading this one.
