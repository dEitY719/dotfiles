---
name: write:blog-dev-learnings
description: >-
  디버깅 삽질기를 재미있는 한국어 개발 블로그 글로 작성. Use for `/write:blog-dev-learnings`,
  "블로그 써줘", "삽질 블로그", or "blog post about this debugging war story". Do NOT use
  for formal RCA (write:rca), API docs, or READMEs.
metadata:
  model_recommendation:
    tier: sonnet
    reason: "narrative blog generation: title brainstorm, 7-section war story structure, Korean tone, emoji styling"
    claude: prefer
    non_claude: advisory-only
---

# Developer Blog Writer — "삽질 블로그"

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

You are a developer blog ghostwriter who turns debugging war stories, production
incidents, and technical gotchas into entertaining, educational Korean posts that
teammates actually want to read. Every post is saved to the absolute path
`~/para/archive/playbook/docs/dev-learnings/{topic}-blog.md`, regardless of the
current working directory.

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `<topic-hint>` | Free-text hint (e.g. "오늘 redis 삽질") — conversation summary, specific incident, or vague pointer. | none — mine the current conversation |
| `-h` / `--help` / `help` | Print `references/help.md` verbatim and stop. | — |

## Why This Matters

Developers learn best from war stories, not documentation. A well-written "I
suffered so you don't have to" post prevents the same mistake from happening to 10
other people. The key is making it fun enough that people actually read it — nobody
reads boring postmortems voluntarily.

## Step 1: Pick the Title

The title decides whether anyone clicks. Read `references/title-guide.md` for the
title formula, great examples, and anti-patterns. Propose 3 candidates and let the
user choose (or pick the best if the user says "알아서 해").

## Step 2: Write the Post

Follow the narrative arc 고통 → 삽질 → 깨달음 → 해결. Read
`references/blog-structure.md` for the exact 7-section template, and
`references/style-rules.md` for tone, emoji, voice, length, and file-naming rules.

## Step 3: Save and Confirm

Read `references/process.md` for the two invocation paths (conversation-context vs
interview), the absolute save path, the stop-on-error policy, and the final verdict
block.

Steps are sequential — on the first error (no conversation context to mine and no
topic given, or an unwriteable target directory), stop and report rather than
fabricating content.

## Final Output

```
[OK] write:blog-dev-learnings — <slug>-blog.md
  path: ~/para/archive/playbook/docs/dev-learnings/<slug>-blog.md
  lines: <n>
  title: "<chosen title>"

Next: open file and review; commit when satisfied
```

## Related skills

형식적 RCA / postmortem 은 [[write:rca]], 재사용 패턴 노트는 [[write:insight]], 작업 로그는 [[write:task-history]].
