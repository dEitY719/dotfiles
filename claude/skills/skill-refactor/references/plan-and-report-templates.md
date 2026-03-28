# Plan and Report Templates

## Refactoring Plan Template (Step 2)

Present this before writing any files. Wait for user confirmation.

```
## Refactoring Plan

Current: <path> — <N> lines
Target: ≤ 100 lines

### Extract to references/:
- [Section/block name] (~X lines) → references/<filename>.md
  Contains: <what kind of content>
  SKILL.md loads it when: <trigger condition>

### Keep in SKILL.md:
- Frontmatter (unchanged)
- Phase/step structure (workflow only)
- Pointers to each references/ file

### Expected result:
- SKILL.md: ~<N> lines (down from <current>)
- New reference files: <list>

Proceed?
```

---

## Completion Report Template (Step 4)

```
## Refactoring Complete

### SKILL.md
Before: <N> lines → After: <M> lines (↓ X%)

### References Created
- references/<file>.md — <N> lines — <what it covers>

### Validation
| Check                    | Result    |
|--------------------------|-----------|
| SKILL.md ≤ 100 lines     | PASS/FAIL |
| Frontmatter valid        | PASS/FAIL |
| References linked        | PASS/FAIL |
| Output format preserved  | PASS/FAIL |

### Next step
Run /skill-check to verify the result.
```

---

## What Belongs Where

| Content type | SKILL.md | references/ |
|-------------|----------|-------------|
| Phase names and sequence | ✓ | |
| Decision logic (if X → do Y) | ✓ | |
| One-liner step descriptions | ✓ | |
| Pointer to reference file | ✓ | |
| Full output templates | | ✓ |
| Configuration examples (>10 lines) | | ✓ |
| Domain knowledge / checklists | | ✓ |
| Examples with before/after | | ✓ |
| Large reference tables | | ✓ |
