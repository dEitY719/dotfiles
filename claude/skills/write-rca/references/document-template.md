# 9-section RCA document spec — YAML frontmatter + Sections 1–9

The output file is a single `.md` at
`${RCA_REPO_PATH:-~/para/archive/rca-knowledge}/docs/analysis/YYYY-MM-DD-{slug}.md`.
It MUST start with the YAML frontmatter below, followed by Sections 1–9 in
order. Section 6 is conditional (skip if not applicable, do not renumber).

## YAML Frontmatter (Required)

```yaml
---
id: "YYYY-MM-DD-{slug}"
title: "{Document Title}"
slug: "{slug}"
date: YYYY-MM-DD
date_created: "ISO-8601-timestamp"
date_modified: "ISO-8601-timestamp"
project: "{project-name}"
category: "{category}"
severity: "{low|medium|high|critical}"
tags: [list, of, tags]
target_audiences: ["postmortem", "blog", "ai-learning", "junior-engineers"]
summary: "One-line summary"
solution_type: "code-refactor|documentation|infrastructure|..."
difficulty_level: "beginner|intermediate|advanced"
reading_time_minutes: 12
blog_ready: true
---
```

## Section 1: Executive Summary (50–100 words)

- Problem one-liner
- Root cause (one sentence)
- Solution summary
- Key learning
- Audience: Everyone (10-second read)

## Section 2: Problem & Context (200–300 words)

- What happened (symptom)
- When and how discovered
- Impact / severity
- Error messages / logs
- Audience: Postmortem + Bloggers

## Section 3: Root Cause Analysis (300–400 words)

- Why this happened
- Contributing factors
- Environment context
- Technical deep-dive
- Audience: All four (core value)

## Section 4: Solution & Implementation (200–300 words)

- What was changed
- Step-by-step fix
- Code before / after
- Reasoning behind solution
- Audience: Junior engineers + AI tools

## Section 5: Deep Dive — Technical Principles (400–600 words)

- Underlying concepts explained
- Industry standards / best practices
- How tools / languages handle this
- Trade-offs discussed
- Audience: AI training + experienced engineers

## Section 6: Compatibility Matrix (if applicable)

Use table format when there are 3+ attributes to compare. Use plain words
(`yes` / `no`) — no glyphs.

```
| Environment | Status | Notes                              |
|-------------|--------|------------------------------------|
| Bash 4+     | yes    | Both mapfile and while-read work   |
| Bash 3      | no     | No mapfile support                 |
| POSIX sh    | no     | mapfile undefined                  |
```

Audience: Developers evaluating solutions.

## Section 7: Prevention & Checklists (200–300 words)

- Prevention measures (numbered list)
- Code review checklist
- Testing strategy
- Monitoring / alerting ideas
- Audience: Postmortem + Junior engineers

## Section 8: Related Issues & Patterns (200–300 words)

- Similar problems (with links if applicable)
- Anti-patterns identified
- When to apply this knowledge
- Audience: AI training + pattern recognition

## Section 9: Quick Reference (100–150 words)

- TL;DR command / fix
- Environment requirements
- Common gotchas
- Further reading
- Audience: Everyone (quick lookup)

## Markdown standards

- Use H2 (`##`) for main sections, H3 (`###`) for subsections.
- Code blocks MUST specify a language (`bash`, `python`, `json`, …).
- Tables: only when 3+ comparison attributes.
- Emphasis: `**bold**` for key terms, backtick `code` for commands.
- Links: relative paths within repo, absolute URLs otherwise.
- No emojis anywhere. Use `[OK]` / `[FAIL]` or `yes` / `no` for status.

## File naming

- Documents: `docs/analysis/YYYY-MM-DD-{slug}.md`
- Media: `_assets/{slug}-{purpose}.{ext}`
  (e.g. `mapfile-compatibility-diagram.png`)
- Reference media from markdown with relative path:
  `![alt](_assets/{slug}-diagram.png)`

## Total document length

Aim for 1500–2500 words. Flexible — see `references/examples.md` for sizing
guidance by RCA shape (small / medium / large).
