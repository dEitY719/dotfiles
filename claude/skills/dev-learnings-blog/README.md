# Dev-Learnings Blog Writer Skill

Turns real debugging sessions, incidents, and technical challenges into engaging Korean blog posts.

## Installation

Already installed at: `~/.claude/skills/dev-learnings-blog/`

Personal skill -- available across all projects.

## Usage

### v1 Draft: Write a new blog

```
/dev-learnings-blog docs/raw-notes/my-incident.md
/dev-learnings-blog "오늘 겪은 일: Redis 캐시가 TTL 무시하고..."
```

Provide either a file path or raw text. Claude will produce a structured blog post at `docs/dev-learnings/<slug>-blog.md`.

### v2 Refinement: Merge peer insights

After v1 is written, provide peer AI documents for refinement:

```
v2 업데이트해. 동료 문서:
- docs/dev-learnings/sso-blog-codex.md
- docs/dev-learnings/sso-blog-gemini.md
```

Claude will cherry-pick 1-2 best elements from each peer and merge them into `<slug>-blog-v2.md`.

## Blog Structure

1. Catchy Korean title + feat. subtitle
2. TL;DR (one sentence)
3. Problem narrative (1st person, with error messages)
4. Root causes (with code/config examples)
5. Why it took so long (meta-analysis)
6. Prevention checklist
7. Conclusion (memorable takeaway)

## Output

- v1: `docs/dev-learnings/<slug>-blog.md`
- v2: `docs/dev-learnings/<slug>-blog-v2.md`
- Target length: 200-400 lines
- Language: Korean with English technical terms

## Three AI Authors

This skill supports a workflow where 3 AI authors (Claude, Codex, Gemini) each write a v1 draft, then one author creates a v2 by cherry-picking the best 1-2 insights from the other two.
