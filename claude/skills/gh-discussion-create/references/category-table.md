# Discussion Category Selection

Mirrors the SSOT in `docs/.ssot/discussions-policy.md` -> "카테고리
매트릭스". When the SSOT changes, update this file in lock-step.

## Categories

| Category | When to pick | Default body skeleton |
|---|---|---|
| `Ideas` (default) | "할까말까", RFC, design exploration. The dominant case for this skill. | RFC template (TL;DR + Why + Goals/Non-Goals + Requirements + Design + Alternatives + Open Questions) |
| `Q&A` | Self-referential "왜 X 를 Y 방식으로 했지?" or external questions. | Q (1-line) + Context + Best answer so far + Follow-up |
| `Announcements` | SSOT/policy change broadcasts. Transient. | Announcement (1-2 lines) + Background + Effective date + Links |
| `Lessons` | Reusable learnings (YouTube/문서/PR 회고). Discussion-first per SSOT — files in `docs/guide/learnings/` are a later promotion. | Source link + Summary + Key takeaways + When to revisit |

The body skeleton variants live in
[`rfc-template.md`](rfc-template.md) -> "Category variants".

## Fallback rule

If the conversation does not match any category cleanly, default to
`Ideas`. RFC bodies tolerate ambiguity better than the other three —
Open Questions captures uncertainty without forcing a structure that
does not exist yet.

## Out of scope

Auto-categorisation (NLP-style) is **not** a goal. The user calling
`/gh-discussion-create` with no `[category]` arg has implicitly chosen
`Ideas`. If they want a different category, they pass it.
