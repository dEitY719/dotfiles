# gh:commit — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | issue-number, or `-h`/`--help`/`help` | auto-detected from chat | Link commit to this GitHub issue via `Refs #N` footer |

## Usage

- `/gh-commit` — inspect working tree, draft a commit, auto-detect issue
  from recent chat (`#N`, `Issue #N created`)
- `/gh-commit 123` — same, but force `Refs #123` in the footer
- `/gh-commit -h` / `--help` / `help` — print this help

## What the skill does

1. Runs `git status`, `git diff`, `git diff --staged`, `git log --oneline -20`
   unconditionally — the working-tree state is the source of truth.
2. Resolves the issue number (explicit arg → recent chat scan → none).
3. Drafts a commit message that mimics the repo's existing style (subject
   line length, conventional-commit prefix usage, footer style).
4. Stages only files relevant to this commit (never `git add -A`).
5. Runs `git commit` via HEREDOC, including the mandatory `Co-Authored-By`
   footer. See `references/commit-message-format.md` for the exact shape.
6. Reports the short hash and subject. Linked issue number printed on a
   second line if one was resolved.

## What the skill will NOT do

- Amend an existing commit (`--amend`) — always creates a new commit.
- Skip hooks (`--no-verify`) or signing (`--no-gpg-sign`).
- Stage `.env`, `credentials.json`, or obvious-secret files — stops and warns.
- Push the commit — that is `/gh:pr`'s job.
- Invent an issue number when none is resolvable.
- Create empty commits.
- Bundle two unrelated changes — asks to split first.

## Good vs. bad invocation

- **Good**: you made edits, type `/gh-commit` — the skill picks a subject
  from the diff, links any recent `#N` from chat, commits, done.
- **Good**: `/gh-commit 42` — same, but forces `Refs #42` regardless of chat.
- **Bad**: calling this to push → use `/gh-pr` instead.
- **Bad**: calling this with no changes in the tree → skill stops with "nothing to commit".
