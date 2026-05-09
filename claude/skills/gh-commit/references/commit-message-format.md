# Commit Message Format — for gh:commit skill

Details of the commit message structure, footer conventions, and the HEREDOC commit command used by the `gh:commit` skill.

## Structure Template

```
<type>(<scope>): <concise summary in imperative mood>

<body explaining the WHY, not the WHAT — the diff shows the what>

Closes #<N>      ← when this commit fully resolves the issue
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Rules

- **Why, not what** — the diff already shows what changed. The body explains motivation, trade-offs, and context.
- **Match the repo's conventions** — if recent commits use `feat:` / `fix:` prefixes, follow suit; if they use plain sentences, follow that. Derive style from `git log --oneline -20`.
- **Issue footer selection** — skill 이 생성 가능한 키워드는 두 개만:
  - `Closes #N` — default. commit 이 이슈를 닫을 때.
  - `Fixes #N` — bug fix 일 때 우선.
- **금지 키워드**: `Refs`, `Resolves`, `See`, `References` — skill 은 절대 생성하지 않음.
  - 사유: `Refs` / `See` / `References` 는 GitHub 가 close 안 시킴 (자동화 깨짐),
    `Resolves` 는 GitHub 인식하지만 AgentToolbox 정책 위반.
- 이슈 번호를 commit 에 footer 로 적지 않을 케이스:
  - 진짜 이슈 없음 → footer 자체 생략. 가짜 이슈 번호 절대 만들지 않음.
  - WIP / 부분 진행이라 close 시키고 싶지 않음 → footer 생략하고
    commit 본문 내에 평문 `(part of #N)` 로 언급.

## HEREDOC Commit Command

Always commit using HEREDOC to preserve multi-line formatting:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<body>

Closes #<N>
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

Use single-quoted `'EOF'` to prevent shell expansion inside the message body.
