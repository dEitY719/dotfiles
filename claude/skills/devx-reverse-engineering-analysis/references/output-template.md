# Output Template

Use this exact structure for `analysis.md`:

```markdown
# [Feature Name] — Feature Analysis

## Overview
[1-2 sentence summary of what this feature does from the user's perspective]

## Key Libraries

| Library | Version | Role |
|---------|---------|------|
| library-name | x.x.x | What it does in this feature |
| ... | ... | ... |

## How It Works

[3–5 paragraphs or numbered flow covering data flow and key abstractions]

## File Map

Key files involved in this feature:
- `path/to/file.ts` — [what it does]
- `path/to/service.py` — [what it does]
- ...

## AI Implementation Prompt

> Copy and paste this prompt into your AI coding assistant to implement this feature in a new project.

---

[START OF PROMPT]

I want to implement [feature name] in my [tech stack] project.

**Goal:** [Clear description of what the feature should do]

**Required libraries:**
- [library]: [install command] — [why this library]
- ...

**Expected behavior:**
- [behavior point 1]
- [behavior point 2]
- ...

**Implementation approach:**
[Key patterns and architecture decisions to follow, derived from the source]

**Data structure / API:**
[If applicable — describe input/output shape with types]

Please implement this step by step, starting with [entry point].

[END OF PROMPT]

---

## Notes
[Any caveats, version-specific behaviors, or gotchas discovered during analysis]
```
