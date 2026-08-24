---
name: write:insight
description: >-
  현재 대화의 재사용 가능한 패턴/교훈을 `docs/guide/learnings/` 노트로 문서화.
  Use for `/write:insight` or "capture this reusable pattern from the chat".
  Do NOT use for 삽질 blog posts (write:blog-dev-learnings), postmortems
  (write:rca), or work logs (write:task-history).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "short note generation with conversation mining, routing check, README rule re-read, overlap scan, index update"
    claude: prefer
    non_claude: advisory-only
---

# write:insight — Conversation → docs/guide/learnings/ note

If the argument is `help`, read `references/help.md` and output it verbatim, then stop.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<topic-hint>` | 후보 인사이트를 한정할 자유 텍스트 힌트 (예: `git-crypt worktree`) | 없음 — 후보 1–3개 제안 |
| `-h` / `--help` / `help` | `references/help.md` 출력 후 종료 | — |

## Role

Capture one reusable insight from the current chat as a short Korean note in
`<repo-root>/docs/guide/learnings/`, sourced from the conversation (don't make the user retype what they lived through). Output one file path + one-line summary at the end, nothing else.

## Step 1: Resolve repo + read the rulebook

In parallel: `git rev-parse --show-toplevel`, read `<repo-root>/docs/guide/learnings/README.md`,
list existing notes. Missing `docs/guide/learnings/` → stop (repo-specific). README is SSOT for template/length/language; re-read every run.

## Step 2: Identify the candidate

With a hint (`/write:insight <hint>`): anchor on it. Without: propose 1–3 candidates
from recent turns with one-line previews and let the user pick. Don't draft speculatively.

Read `references/routing.md` to check whether the candidate actually belongs in
`docs/guide/learnings/`. Decline topics that belong in `docs/guide/technic/`,
`docs/.ssot/`, `docs/feature/<name>/`, `claude/skills/`, or `memory/` — or in a
sibling write-* skill — using the phrasing template there.

## Step 3: Check for overlap

`grep -li '<keywords>' docs/guide/learnings/*.md` — if a real overlap exists, recommend
updating the existing file instead. Same check against `~/.claude/projects/*/memory/MEMORY.md`
when accessible: learnings holds the body, memory keeps a one-line pointer.

## Step 4: Mine the conversation for sources

Build the note from conversation evidence instead of asking the user to restate
context. Extract from chat: PR numbers, commit SHAs, issue numbers, review threads
and URLs (`discussion_r...`), repro steps, file paths with line ranges.
Provenance-less learning is forgettable trivia — if extraction yields nothing, the
Context section must state the concrete situation ("발견 상황: …"), not vague claims.

## Step 5: Draft the note

Read `references/template.md` for section structure, length policy, filename rules,
and bonus-section criteria. Read `references/examples.md` for tone anchors from the
three notes already in repo. Filename names the **pattern**, not the action.
Output = short Korean note per repo README rules: 5 sections, 50–80 lines, source
links to PR / commit / file:line; past 150 lines → `docs/guide/technic/` instead.

## Step 6: Write the file + update README index

Write `docs/guide/learnings/<slug>.md`. Edit `docs/guide/learnings/README.md` "현재 문서 목록"
section: append a numbered entry matching the existing 3-line format (heading link
+ 2–3 line summary).

## Step 7: Suggest a memory pointer (don't auto-create)

If cross-session reusable, ask: `memory/reference_learnings_<slug>.md` 포인터 추가할까요? (한 줄짜리, 본문은 learnings, memory 는 경로만). Wait for yes — `MEMORY.md` loads every session; churn is expensive.

## Step 8: Report

Output exactly two lines, no preamble, no recap — first line is the structured
verdict, second line is the explicit `Next:` follow-up hint:

```
[OK] file=docs/guide/learnings/<slug>.md lines=<N> summary="<one-line hook — same lead used in README index>"
Next: review the file, then optionally /write:insight again for remaining candidates
```

## Constraints

- **Stop on any step failure** — Steps 1–8 are sequential; on the first error stop and report the failing step, do not proceed silently.
- **Korean body, English headings** — for human teammates per README's language policy. **Don't paraphrase the README** — re-read every run; if rules conflict, README wins.
- **No abstract generalities** — no PR/commit/file:line link → reject (back to Step 4 or decline). **One file per invocation** — multiple insights → pick one, offer the rest as a follow-up run.
- **Never auto-write to `memory/`** — suggest, wait for confirmation. **Never overwrite silently** — existing slug → surface diff, ask update vs. new slug.

## Related skills

작업 로그는 [[write:task-history]], 장애 분석은 [[write:rca]], 서사형 삽질 블로그는 [[write:blog-dev-learnings]] — 전체 라우팅 표는 `references/routing.md`.
