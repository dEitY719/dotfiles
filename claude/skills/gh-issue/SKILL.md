---
name: gh:issue
description: >-
  Save the current conversation as a GitHub issue in the current repository.
  Use when the user runs /gh:issue, /gh-issue, or asks to "이 대화 이슈로 등록",
  "chat을 깃허브 이슈로 남겨", "기록용 이슈 만들어". Summarizes the conversation so
  far into a structured issue body (feature request / error analysis / misc),
  creates it via `gh issue create` on the current repo's origin without asking
  for confirmation, and prints only the issue number and URL. Do NOT over-
  compress — the issue is reused for PR drafts and blog posts, so preserve
  reasoning, decisions, and concrete details.
allowed-tools: Bash, Read, Grep
---

# gh:issue — Conversation → GitHub Issue

## Role

Convert the current chat into a well-structured GitHub issue on the current
repo's origin. Execute immediately without confirmation. Print only the issue
number + URL at the end — the user will open GitHub directly.

## Step 1: Detect Repo Context

Run in parallel:
- `git rev-parse --show-toplevel` — confirm we're in a git repo
- `gh repo view --json nameWithOwner -q .nameWithOwner` — get owner/repo

If either fails, stop and tell the user the skill requires a git repo with a
GitHub remote configured.

## Step 2: Classify the Conversation

Pick exactly one category based on the dominant intent of the chat:

- **feature** — 신규 기능 요청, 개선 제안, 리팩토링 아이디어
- **bug** — 에러 로그 분석, 버그 재현, 원인 추적
- **misc** — 질문/논의/조사/문서화 등 위 두 가지에 속하지 않는 것

The category determines the title prefix and section layout below.

## Step 3: Draft the Issue Body

**DO NOT over-compress.** This issue is reused later for PR descriptions and
blog posts. Preserve concrete file paths, command outputs, decisions, and
reasoning. A 200-line issue is fine if the conversation warranted it.

Write the body in the language the user was speaking (Korean for Korean chats).

### Title format
- feature: `[Feature] <구체적인 한 줄 요약>`
- bug: `[Bug] <증상 한 줄 요약>`
- misc: `[Misc] <주제 한 줄 요약>`

### Body structure (feature)
```markdown
## Context
<왜 이 기능이 필요한가 — 사용자가 말한 배경/동기>

## Proposal
<무엇을 만들 것인가 — 요구사항 목록>

## Discussion Log
<대화에서 오간 의사결정, 대안 검토, 네이밍 논의 등 원문에 가깝게>

## Open Questions
<아직 결정 안 된 것, 확인 필요한 것>

## References
- 관련 파일: `path/to/file.ext`
- 관련 이슈/PR: (있으면)
```

### Body structure (bug)
```markdown
## Symptom
<에러 메시지, 실패 증상>

## Reproduction
<재현 절차 — 대화에서 나온 명령, 환경>

## Root Cause Analysis
<원인 추적 과정과 결론>

## Fix Plan
<수정 방향 — 아직 수정 안 했으면 계획만>

## Logs / Evidence
<로그 발췌, 파일 위치 등>
```

### Body structure (misc)
```markdown
## Topic
<대화 주제>

## Summary
<논의된 내용 정리>

## Decisions
<도출된 결론>

## Notes
<추가 맥락>
```

## Step 4: Create the Issue

Write the body to a temp file (to avoid shell escaping issues), then:

```bash
gh issue create --title "<title>" --body-file /tmp/gh-issue-body.md
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
- Never create the issue on a different repo than the current `origin`.
- Never abbreviate the discussion log to 2–3 bullets — preserve detail.
- Never ask "should I create it?" — the user already said yes by running the
  skill.
