---
name: gh:commit
description: >-
  Create a git commit for the current changes following the repo's style,
  auto-linking a GitHub issue number if it appears in the recent conversation
  or is passed as an argument. Always inspects the current working-tree state
  first — works equally for changes made by Claude in this conversation and
  for changes the user made manually outside the conversation (e.g. quick
  alias additions). Use when the user runs /gh:commit, /gh-commit, or asks
  "커밋해", "지금까지 작업 커밋", "이슈 N번 연결해서 커밋". The user does NOT
  need to prefix with "git status 확인하고" — that is step 1 of this skill.
  Creates a new commit — never amends. Never skips hooks. Accepts
  `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "git commit wrapping, structured"
    claude: prefer
    non_claude: advisory-only
---

# gh:commit — Git Commit with Issue Linking

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Stage the relevant changes and create a new git commit in the repo's commit
style, with a `Closes #N` / `Fixes #N` footer when a GitHub issue is known.
`Refs` / `Resolves` / `See` / `References` keywords are forbidden — they break
GitHub auto-close and project-board automation (see issue #392).

## Step 1: Inspect State (parallel) — ALWAYS FIRST

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 5.

Runs **unconditionally** on every invocation, even bare `/gh-commit` with no
conversation context — the working-tree state is the source of truth, so do
NOT ask "what did you change?". In a single message run: `git status` (never
`-uall`), `git diff` (staged + unstaged), `git diff --staged` if anything is
staged, and `git log --oneline -20` (to mimic the repo's commit style).

## Step 2: Resolve the Issue Number

First hit wins: (1) explicit argument (`/gh:commit 123` or "이슈 123번 연결"
in the latest message); (2) recent conversation — scan the last ~10 messages
for `#N` or "Issue #N created" (gh:issue-create's output); (3) none → skip
the footer, do NOT invent an issue number.

## Step 3: Draft the Commit Message

Read `references/commit-message-format.md` for the message template, HEREDOC
pattern, and `Closes`/`Fixes` rules (`Refs`/`Resolves` forbidden); match the
`git log` style. With no conversation context (manual edits), derive intent
from the diff — paths and names tell you *what* changed; small additions get
a short subject like `chore(aliases): add <name> shortcut` (body optional,
mandatory footers still apply). Only ask the user when the diff is ambiguous
or spans unrelated areas.

## Step 4: Stage and Commit

- Stage only relevant files by name — avoid `git add -A`/`.` to keep secrets
  and unrelated changes out. **Never stage secret-looking files** (`.env`,
  `credentials.json`, keys); if the diff touches such files, stop and warn.
- **NEVER** `--amend` unless explicitly asked. **NEVER** `--no-verify` /
  `--no-gpg-sign`: if a hook fails, fix the cause, re-stage, new commit.
- See `references/commit-message-format.md` for the exact HEREDOC command.

After `git commit` succeeds, emit the step-completion marker so the step-skip
guard (`skill_completion_guard.py`, issue #753) can verify this step ran:
`printf '[step:gh-commit/stage-commit] OK\n'`.

## Step 5: AI Metrics + Sync Project Board Status

The ai-metrics comment POST (`GH_DISABLE_AI_METRICS` branch, token formula,
soft-fail) follows
[`references/ai-metrics-comment.md`](references/ai-metrics-comment.md). The
project-board sync (`--only-from Backlog` guard, helper-fallback NF-1/#724
defense) follows [`references/board-sync.md`](references/board-sync.md) —
skip it entirely when no issue footer was written. After both blocks, emit
`printf '[step:gh-commit/metrics-board-sync] OK\n'`.

## Step 6: Verify

After commit succeeds, run `git status` and report
`Committed <short-hash>: <subject line>` (mention the issue number on a
second line if one was linked). Then emit the report step-completion marker
so the step-skip guard recognizes the skill finished:
`printf '[step:gh-commit/report] OK\n'`.

## Constraints

- One commit per invocation by default. If the diff is clearly two unrelated
  changes, ask the user whether to split before staging.
- Never push (`/gh:pr` handles pushing), create empty commits, or edit git config.
