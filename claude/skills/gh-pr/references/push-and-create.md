# Push and Create — branch push policy + PR creation command

Used in Step 5 of the `gh:pr` skill, after the body is drafted.

## Push policy

| Upstream state | Action |
|---|---|
| No upstream tracking | `git push -u origin HEAD` |
| Upstream exists, local ahead, no divergence | `git push` |
| Upstream diverged (force-push needed) | **STOP** — ask the user before force-pushing. Never force-push without explicit approval. |

Detect upstream with `git rev-parse --symbolic-full-name @{u} 2>/dev/null`
(already gathered in Step 1). Compare with `git status -sb` or
`git rev-list --left-right --count @{u}...HEAD`.

## PR creation command

Once the push succeeds, create the PR with the command and flags documented
in `references/pr-body-template.md` (mktemp body file, `--assignee @me`,
labels applied after creation).
