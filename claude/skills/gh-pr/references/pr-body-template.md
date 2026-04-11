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

Write the body to a temp file, then run:

```bash
gh pr create \
  --base <base> \
  --title "<title>" \
  --body-file /tmp/gh-pr-body.md
```

Do NOT set `--draft`, `--reviewer`, `--assignee`, or `--label` unless the user
explicitly asked.
