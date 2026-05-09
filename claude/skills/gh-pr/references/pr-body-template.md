# PR Body Template — for gh:pr skill

Use this template when drafting the title and body in Step 4 of the `gh:pr` skill.

## Title Rules

- Under 70 characters.
- Imperative mood (e.g., "Add", "Fix", "Refactor").
- Match the commit style of the repo (scan recent commits/PRs).
- Do NOT stuff details into the title — they belong in the body.

## Body Template

Language: match the repo. Use Korean if existing commits are Korean.

```markdown
## Summary
- <1–3 bullets covering the whole PR, not just HEAD>

## Changes
- <commit-scope 1>: <what changed and why>
- <commit-scope 2>: <...>
<one bullet per meaningful commit or logical group>

## Test plan
- [ ] <concrete manual or automated check>
- [ ] <another check>

## Related
Closes #<N>
```

- When Step 3 resolved an issue number AND the PR fully addresses it,
  `Closes #<N>` is **mandatory** — not optional. The dotfiles
  Project board relies on this keyword to move the Issue card to
  `Done` on merge (see `docs/standards/github-project-board.md`).
  Omitting it means the Issue stays open and the card never reaches
  `Done`.
- For bug-fix PRs, `Fixes #<N>` is also acceptable.
- **Forbidden keywords**: `Refs`, `Resolves`, `See`, `References` — the skill
  must never generate these. `Refs` / `See` / `References` do not trigger
  GitHub auto-close, and `Resolves` violates the AgentToolbox policy. To
  express partial progress, omit the footer and mention `(part of #N)`
  inline in the body instead (issue #392).
- Omit the `## Related` section entirely only when no issue number
  is known.

### Stacked-PR `Depends on` insertion

When Step 1a set `PARENT_PR` (auto-detected or `--parent-pr <N>` was
passed), insert a `Depends on #<PARENT_PR>` line into the
`## Related` section, alongside `Closes #<N>` / `Refs #<N>` if any:

```markdown
## Related
Closes #42
Depends on #201
```

Rules:

- The line is added **only** when `PARENT_PR` is non-empty. `--no-stack`,
  `--base <branch>`, and the no-signal solo path all leave it empty.
- Order: any `Closes` / `Refs` line first, then `Depends on`. GitHub
  rendering treats both as cross-references; the order is conventional.
- Never mutate the parent PR's body to add a back-reference. Cross-PR
  rollup is the downstream repo's job (e.g. AgentToolbox's
  `stacked-closes-rollup.yml` workflow harvests `Depends on` lines).
- If `## Related` would otherwise be omitted (no issue link), still add
  the section with just the `Depends on` line:

  ```markdown
  ## Related
  Depends on #201
  ```

## Create Command

Write the body to a unique temp file via `mktemp` (avoids concurrent-run
collisions), then run:

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write the drafted body to "$BODY" ...
gh pr create \
  --base "$BASE_BRANCH" \
  --title "<title>" \
  --body-file "$BODY" \
  --assignee @me
```

`$BASE_BRANCH` is bound by Step 1a (`references/stacked-pr.md`); it is
either the repo default branch or — when stacking — a parent PR's
head ref / a user-supplied `--base` value.

`--assignee @me` is always applied — the skill self-assigns every PR.

Do NOT set `--draft` or `--reviewer` unless the user explicitly asked.

## Label Derivation

Labels are applied **after** `gh pr create` via the
`_gh_pr_edit_safe_label` wrapper (sourced from
`shell-common/functions/gh_pr_edit_safe.sh`), because:

1. The label set must be validated against the repo's existing labels first
   (creating labels on the fly is forbidden).
2. A bare `gh pr edit --add-label` call exits 1 with a `Projects (classic)
   is being deprecated` GraphQL warning on repos that still have a classic
   project board attached, silently dropping every label. The wrapper
   detects that warning and falls back to the REST endpoint, which is
   GraphQL-free. See issue #326.

### Mapping from Conventional Commits

Scan `git log <base>..HEAD --format=%s` and collect types from each subject:

| Commit type | Candidate label     |
|-------------|---------------------|
| `feat`      | `enhancement`       |
| `fix`       | `bug`               |
| `docs`      | `documentation`     |
| `refactor`  | `refactor`          |
| `style`     | `style`             |
| `perf`      | `performance`       |
| `test`      | `test`              |
| `chore`     | `chore`             |
| `ci`        | `ci`                |
| `build`     | `build`             |

Multiple commit types → multiple candidate labels (dedup first).

### Judgment-based additions

Add scope labels that match the PR's actual footprint, e.g.:

- `claude/skills/**` changes → `skill`
- `docs/**` or `**/*.md` only → `documentation`
- Changes under a specific package → that package's label if one exists

Use judgment; do not stretch — a label should meaningfully describe the PR.

### Safe application loop

Labels that don't already exist in the repo **must be skipped silently** —
never create new labels. The `_gh_pr_edit_safe_label` wrapper enforces this
even on the REST fallback path: it re-checks `gh label list` before POST.

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"

EXISTING=$(gh label list --repo "$GH_REPO" --limit 200 --json name -q '.[].name')
PR_NUMBER=<the number gh pr create printed>

for LABEL in <candidate-list>; do
  if printf '%s\n' "$EXISTING" | grep -Fxq "$LABEL"; then
    _gh_pr_edit_safe_label "$PR_NUMBER" "$LABEL" --repo "$GH_REPO"
  fi
done
```

`GH_REPO` is `owner/repo` (e.g. `dEitY719/dotfiles`). Resolve via
`gh repo view --json nameWithOwner --jq .nameWithOwner` if not already set.

Report the applied labels (and skipped ones, if any) alongside the PR URL
in Step 7.
