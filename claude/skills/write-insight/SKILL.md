---
name: write:insight
description: >-
  Archive a reusable insight from the current conversation as a short Korean
  learning note under `docs/learnings/<slug>.md`, following this repo's
  README.md conventions (5-section template, 50–80 lines, source links to
  PR / commit / file:line). Use when the user runs `/write:insight`,
  `/write-insight`, or asks "이 내용 learning 으로 정리해줘", "방금 발견한 거
  learnings 에 남겨", "insight 아카이브해줘", or otherwise wants to capture a
  concrete pattern, debugging path, or review-driven discovery from the chat.
  Pulls source material from the live conversation (recent PRs, commits,
  review threads, repro experiments) rather than asking the user to retype
  it. Refuses topics that belong in `docs/technic/`, `docs/standards/`,
  `docs/feature/`, or `claude/skills/` and routes them to the correct home.
  Do NOT trigger for narrative "삽질" blog posts (use `write-blog-dev-learnings`),
  formal RCA postmortems (use `write-rca-doc`), or JIRA/PR description drafts
  (use `write-task-history`) — those write to `~/para/archive/`. This skill
  writes inside the current repo's `docs/learnings/` and is repo-specific.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# write:insight — Conversation → docs/learnings/ note

If the argument is `help`, read `references/help.md` and output it verbatim, then stop.

## Role

Capture one reusable insight from the current chat as a short Korean note in
`<repo-root>/docs/learnings/`. Source comes from the conversation — don't make
the user retype what they already lived through. Output one file path + one-line
summary at the end, nothing else.

## Step 1: Resolve repo + read the rulebook

In parallel: `git rev-parse --show-toplevel`, read `<repo-root>/docs/learnings/README.md`,
list existing notes. If `docs/learnings/` is missing, stop — this skill is repo-specific.
The README is SSOT for template/length/language; re-read it every run.

## Step 2: Identify the candidate

With a hint (`/write:insight <hint>`): anchor on it. Without: propose 1–3 candidates
from recent turns with one-line previews and let the user pick. Don't draft speculatively.

Read `references/routing.md` to check whether the candidate actually belongs in
`docs/learnings/`. If it fits a neighbor directory or sibling write-* skill, decline
using the phrasing template there.

## Step 3: Check for overlap

`grep -li '<keywords>' docs/learnings/*.md` — if a real overlap exists, recommend
updating the existing file instead. Same check against `~/.claude/projects/*/memory/MEMORY.md`
when accessible: learnings holds the body, memory keeps a one-line pointer.

## Step 4: Mine the conversation for sources

Extract from chat: PR numbers, commit SHAs, issue numbers, review URLs
(`discussion_r...`), file paths with line ranges. A learning without provenance
is forgettable trivia — if extraction yields nothing, the Context section must
state the concrete situation ("발견 상황: …"), not vague claims.

## Step 5: Draft the note

Read `references/template.md` for section structure, length policy, filename rules,
and bonus-section criteria. Read `references/examples.md` for tone anchors from the
three notes already in repo. Filename names the **pattern**, not the action.
Target 50–80 lines; past 150 → recommend `docs/technic/` instead.

## Step 6: Write the file + update README index

Write `docs/learnings/<slug>.md`. Edit `docs/learnings/README.md` "현재 문서 목록"
section: append a numbered entry matching the existing 3-line format (heading link
+ 2–3 line summary).

## Step 7: Suggest a memory pointer (don't auto-create)

If the insight is cross-session reusable, ask: `memory/reference_learnings_<slug>.md`
포인터 추가할까요? (한 줄짜리, 본문은 learnings, memory 는 경로만). Wait for yes —
`MEMORY.md` is loaded into every session, churn there is expensive.

## Step 8: Report

Output exactly two lines, no preamble, no recap:

```
docs/learnings/<slug>.md (<N> lines)
<one-line summary — the same hook used in README index>
```

## Constraints

- **Korean body, English headings** — note is for human teammates per README's language policy.
- **No abstract generalities** — no PR/commit/file:line link → reject. Back to Step 4 or decline.
- **Don't paraphrase the README** — re-read every run; if rules conflict, README wins.
- **One file per invocation** — multiple insights → pick one, offer the rest as a follow-up run.
- **Never auto-write to `memory/`** — suggest, wait for confirmation.
- **Never overwrite silently** — existing slug → surface diff, ask update vs. new slug.
