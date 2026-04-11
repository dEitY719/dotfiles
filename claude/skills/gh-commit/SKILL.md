---
name: gh:commit
description: >-
  Create a git commit for the current changes following the repo's style,
  auto-linking a GitHub issue number if it appears in the recent conversation
  or is passed as an argument. Use when the user runs /gh:commit, /gh-commit,
  or asks "커밋해", "지금까지 작업 커밋", "이슈 N번 연결해서 커밋". Creates a new
  commit — never amends. Never skips hooks.
allowed-tools: Bash, Read, Grep
---

# gh:commit — Git Commit with Issue Linking

## Role

Stage the relevant changes and create a new git commit that follows the
repository's existing commit style, with an optional `Refs #N` / `Closes #N`
footer when a GitHub issue is known.

## Step 1: Inspect State (parallel)

Run these in a single message:
- `git status` (never `-uall`)
- `git diff` (staged + unstaged)
- `git diff --staged` if anything is already staged
- `git log --oneline -20` — mimic the repo's commit message style

## Step 2: Resolve the Issue Number

Check in this order and use the first hit:

1. **Explicit argument** — if the user said `/gh:commit 123` or mentioned
   "이슈 123번 연결" in their latest message.
2. **Recent conversation** — scan the last ~10 messages for `#N` or
   "Issue #N created" (gh:issue's output format). If found, use it.
3. **None** — skip the footer. Do NOT invent an issue number.

## Step 3: Draft the Commit Message

Read `references/commit-message-format.md` for the message template, HEREDOC
pattern, and `Closes` / `Refs` / `Fixes` rules. Match the repo's commit style
derived from `git log`.

## Step 4: Stage and Commit

- Stage only files relevant to this commit. Prefer listing files by name over
  `git add -A` / `git add .` to avoid sweeping in secrets or unrelated changes.
- **Never stage files that look like secrets** (`.env`, `credentials.json`,
  keys). If the diff touches such files, stop and warn the user.
- **NEVER** use `--amend` unless the user explicitly asked.
- **NEVER** use `--no-verify` / `--no-gpg-sign`. If a pre-commit hook fails,
  fix the underlying issue, re-stage, and create a **new** commit.
- See `references/commit-message-format.md` for the exact HEREDOC command.

## Step 5: Verify

After commit succeeds, run `git status` and report:

```
Committed <short-hash>: <subject line>
```

If an issue was linked, mention the issue number on a second line.

## Constraints

- One commit per invocation by default. If the diff is clearly two unrelated
  changes, ask the user whether to split before staging.
- Never push. `/gh:pr` handles pushing.
- Never create empty commits.
- Never edit git config.
