# Tone & Structure Anchors

The three notes already in `docs/learnings/` define what "good" looks like
for this skill. Read them before drafting; match their depth, density, and
rhythm — don't invent a new style.

## Existing notes (as of skill creation)

| File | Lines | What it nails |
|---|---|---|
| `docs/learnings/ux-color-hierarchy.md` | 62 | Tight Pattern (numbered color levels) + concrete `ux_*` example block + symmetric apply / don't-apply pairs |
| `docs/learnings/git-worktree-detection.md` | 86 | Diagnostic comparison ("같으면 main repo, 다르면 worktree"), bonus "실제 출력 예시" + "주의점" sections that earn their place |
| `docs/learnings/github-pr-review-reply-api.md` | 87 | Three-endpoint table, real `gh api` invocations, threading rule explained from first principles |

## Patterns worth copying

**Context section opens with bulleted source links.** All three start with
`- **출처**: [PR #N](...)` then `- **커밋**: <sha>` then `- **파일**: <path:line>`.
This is the spine — without it the note degrades into folklore.

**Pattern is short.** 1–3 sentences or a short numbered list. If the
Pattern section grows into multiple paragraphs, the insight isn't a
"learning", it's a tutorial — route to `docs/technic/`.

**Code is minimal and runnable.** No imports of fictional helpers, no
`...` ellipses inside the snippet. A reader pasting the block should see
something that runs (or, for shell, sources cleanly).

**When to use is two columns of intent.** Apply conditions and don't-apply
conditions live as parallel bullet lists. The don't-apply column matters
more — it's what stops cargo-culting.

**Related is for navigation, not citation.** Link to:
- the implementation file (function name preferred over line number — line
  numbers rot)
- adjacent learnings that compose with this one
- the upstream doc / man page if the pattern relies on documented behavior

## Anti-patterns to avoid

- **No PR/commit anywhere** → not a learning, it's a vibe. Reject.
- **Pattern section explains the code line-by-line** → the code already
  does that. Pattern explains *why* the code is shaped that way.
- **150+ lines** → README's growth strategy says promote to `docs/technic/`.
- **Copy-pasted shell session as the entire body** → distill the pattern
  out; the session is at most a "실제 출력 예시" bonus.
- **Generic title like "Git tips"** → titles name the specific pattern
  ("Git worktree 컨텍스트 감지", not "Git stuff I learned").

## Length calibration

If you have to ask "is this enough detail?" — it probably is. Existing
notes hit 60–90 lines including frontmatter and blank lines. Aim for
that band; let the content decide whether you land at 55 or 85.
