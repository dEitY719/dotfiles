---
name: gh:issue-create
description: >-
  Save the current conversation as a GitHub issue in the current repository.
  Use when the user runs /gh:issue-create, /gh-issue-create, or asks to "이 대화 이슈로 등록",
  "chat을 깃허브 이슈로 남겨", "기록용 이슈 만들어". Summarizes the conversation so
  far into a structured issue body (feature request / error analysis / misc),
  creates it via `gh issue create` on the target remote's repo without asking
  for confirmation, and prints only the issue number and URL. Do NOT over-
  compress — the issue is reused for PR drafts and blog posts, so preserve
  reasoning, decisions, and concrete details.
  Accepts an optional remote name argument (e.g., `/gh-issue-create upstream`) to
  target a different remote's repository instead of origin. Accepts
  `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:issue-create — Conversation → GitHub Issue

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Convert the current chat into a well-structured GitHub issue on the target
repo. Execute immediately without confirmation. Print only the issue
number + URL at the end — the user will open GitHub directly.

## Step 1: Detect Repo Context

Confirm we're in a git repo (`git rev-parse --show-toplevel`), then pick
the target remote (arg #1 if given, else `origin`) and resolve it to
`TARGET_REPO=<owner>/<repo>`. If the remote does not exist, list
`git remote -v` and stop — never fall back to `origin` silently.

Read `references/repo-resolution.md` for the full substeps, error-message
template, and `https` / `ssh` URL parsing rules.

## Step 2: Classify the Conversation

Pick exactly one category based on the dominant intent of the chat:

- **feature** — 신규 기능 요청, 개선 제안, 리팩토링 아이디어
- **bug** — 에러 로그 분석, 버그 재현, 원인 추적
- **misc** — 질문/논의/조사/문서화 등 위 두 가지에 속하지 않는 것

The category determines the title prefix and section layout.

## Step 3: Draft the Issue Body

Read `references/issue-body-templates.md` and select the title format + body
structure matching the category from Step 2. Write the body in the language
the user was speaking (Korean for Korean chats).

**DO NOT over-compress.** This issue is reused later for PR descriptions and
blog posts. Preserve concrete file paths, command outputs, decisions, and
reasoning. A 200-line issue is fine if the conversation warranted it. Never
abbreviate the discussion log to 2–3 bullets.

## Step 4: Create the Issue

Write the body to a unique temp file via `mktemp` (avoids shell escaping
issues and concurrent-run collisions), then:

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write the drafted body to "$BODY" ...
gh issue create --repo "$TARGET_REPO" --title "<title>" --body-file "$BODY"
```

Do NOT add `--assignee`, `--label`, or `--milestone` unless the user explicitly
asked. Do NOT ask for confirmation — run it immediately.

## Step 5: Report

Output **only** the issue number and URL, nothing else:

```
Issue #123 created: https://github.com/owner/repo/issues/123
```

No summary, no "I created...", no markdown headings. The user checks GitHub
directly.

## Constraints

- Never use `--assignee @me` or labels unless the user asked.
- Always use `--repo "$TARGET_REPO"` — never rely on implicit repo detection.
- If the user-specified remote does not exist, fail immediately with the list
  of available remotes. Do not fall back to `origin` silently.
- Never abbreviate the discussion log to 2–3 bullets — preserve detail.
- Never ask "should I create it?" — the user already said yes by running the
  skill.
