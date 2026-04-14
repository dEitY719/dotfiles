# Template — Section structure, length policy, filename rules

This is the schema for a learning note. The repo's
`docs/learnings/README.md` is the upstream authoritative source — re-read
it at the start of every run (Step 1). This file is a fast-path summary
of what to put where, derived from that README.

## Filename

`<repo-root>/docs/learnings/<slug>.md`

- `<slug>` is descriptive, lowercase, kebab-case
- Specific over generic: `git-worktree-detection.md` ✓ — `git-tips.md` ✗
- Verb-free nouns: name the **pattern**, not the action

## Frontmatter

None. Learning notes are pure markdown — no YAML block. The README
itself has no frontmatter; match it.

## Required sections (in order)

Headings stay English (`## Context`, `## Pattern`, …) per the in-repo
convention; body is Korean.

1. **`## Context`** — sources first, situation second
   - Bulleted source links: `- **출처**: [PR #N](url)` then `- **커밋**: <sha>` then `- **파일**: <path:line>`
   - Then 1–3 sentences on what discovery prompted this note
2. **`## Pattern`** — the core principle in 1–3 sentences or a short
   numbered list. Explains *why* the code is shaped this way, not *what*
   the code does. If this section grows past one paragraph, the insight
   is a tutorial — route to `docs/technic/`.
3. **`## Code`** — the smallest copy-pastable example, language tag
   included (` ```sh `, ` ```python `, …). No fictional helpers, no `...`
   ellipses inside the snippet.
4. **`## When to use`** — apply / don't-apply as parallel bullet lists.
   The don't-apply column matters more — it's what stops cargo-culting.
5. **`## Related`** — navigation, not citation:
   - Implementation file (function name preferred over line number)
   - Adjacent learnings that compose with this one
   - Upstream doc / man page if relevant

## Optional bonus sections

Two patterns from existing notes — use only when they pull their weight:

- **`## 실제 출력 예시`** — concrete shell session showing the diagnostic
  outputs the Pattern section described. Useful when the pattern is a
  comparison ("if A == B then X").
- **`## 주의점`** — non-obvious gotchas that didn't fit cleanly under
  Pattern (zsh quirks, shellcheck SC codes, side effects).

Don't pad. If a note has both bonus sections plus the 5 required ones, the
content had better justify the length.

## Length policy

| Range | Action |
|---|---|
| 50–80 lines | Target. Existing notes hit 60–90 incl. blanks. |
| 80–150 lines | OK if content earns it. Resist padding to look thorough. |
| 150+ lines | Stop. Recommend `docs/technic/` instead. The repo's README growth-strategy section says so. |

## Tone anchors

Read `references/examples.md` for the tone/depth/link-density anchors
extracted from the three notes already in the repo. Match those, don't
invent a new style.
