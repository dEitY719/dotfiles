# Commit Message Format — for gh:commit skill

Details of the commit message structure, footer conventions, and the HEREDOC commit command used by the `gh:commit` skill.

## Structure Template

```
<type>(<scope>): <concise summary in imperative mood>

<body explaining the WHY, not the WHAT — the diff shows the what>

Refs #<N>        ← only if issue number resolved
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Rules

- **Why, not what** — the diff already shows what changed. The body explains motivation, trade-offs, and context.
- **Match the repo's conventions** — if recent commits use `feat:` / `fix:` prefixes, follow suit; if they use plain sentences, follow that. Derive style from `git log --oneline -20`.
- **Issue footer selection**:
  - `Closes #N` — only when the commit fully resolves the issue.
  - `Fixes #N` — preferred when the change is a bug fix for a tracked issue.
  - `Refs #N` — partial progress, or a reference without closing.
- Omit the footer entirely if no issue number was resolved. Never invent one.

## HEREDOC Commit Command

Always commit using HEREDOC to preserve multi-line formatting:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<body>

Refs #<N>
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Use single-quoted `'EOF'` to prevent shell expansion inside the message body.
