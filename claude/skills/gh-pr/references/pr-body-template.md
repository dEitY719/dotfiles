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
Closes #<N>        ← only if issue resolved
Refs #<N>          ← if related but not fully resolving
```

- Omit the `## Related` section entirely if no issue number is known.

## Create Command

Write the body to a unique temp file via `mktemp` (avoids concurrent-run
collisions), then run:

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write the drafted body to "$BODY" ...
gh pr create \
  --base <base> \
  --title "<title>" \
  --body-file "$BODY" \
  --assignee @me
```

`--assignee @me` is always applied — the skill self-assigns every PR.

Do NOT set `--draft` or `--reviewer` unless the user explicitly asked.

## Label Derivation

Labels are applied **after** `gh pr create` via `gh pr edit --add-label`,
because the label set must be validated against the repo's existing labels
first (creating labels on the fly is forbidden).

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
never create new labels.

```bash
EXISTING=$(gh label list --limit 200 --json name -q '.[].name')
PR_NUMBER=<the number gh pr create printed>

for LABEL in <candidate-list>; do
  if printf '%s\n' "$EXISTING" | grep -Fxq "$LABEL"; then
    gh pr edit "$PR_NUMBER" --add-label "$LABEL"
  fi
done
```

Report the applied labels (and skipped ones, if any) alongside the PR URL
in Step 7.
