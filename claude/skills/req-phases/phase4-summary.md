# Phase 4: Summary Protocol

Internal reference for req-workflow. NOT user-invocable.

## Purpose

Create documentation, update tracking, and git commit.

## Input

```yaml
req_id: REQ-X-Y
phase1_spec: [specification markdown]
phase2_tests: [test design markdown]
phase3_result: [implementation result]
modified_files: [list of files changed]
```

## Steps

### Step 1: Create Progress File

Location: `docs/progress/REQ-X-Y.md`

```markdown
# REQ-X-Y: [Title]

**Status**: Done (Phase 4)
**Completion Date**: [YYYY-MM-DD]

---

## Summary

[One sentence: what was implemented]

---

## Phase Progress

| Phase | Status | Date |
|-------|--------|------|
| 1: Specification | Done | [date] |
| 2: Test Design | Done | [date] |
| 3: Implementation | Done | [date] |
| 4: Documentation | Done | [date] |

---

## Phase 1: Specification

[Paste Phase 1 output]

---

## Phase 2: Test Design

[Paste Phase 2 output]

---

## Phase 3: Implementation

[Paste Phase 3 output]

---

## Phase 4: Summary

### Documentation
- Progress file: docs/progress/REQ-X-Y.md
- DEV-PROGRESS.md: Updated

### Git Commit
- SHA: [will be filled after commit]
- Message: feat: Implement REQ-X-Y

### Traceability

| Requirement | Test Cases | Implementation |
|-------------|------------|----------------|
| AC-1 | TC-2, TC-4 | [file:line] |
| AC-2 | TC-3, TC-4 | [file:line] |
| AC-3 | TC-4 | [file:line] |

---

## References

- Requirement: docs/feature_requirement_mvp1.md#REQ-X-Y
- Progress Tracking: docs/DEV-PROGRESS.md
```

### Step 2: Update DEV-PROGRESS.md

Find and replace row:

```markdown
# Before
| REQ-X-Y | [Title] | 0 | Backlog | [notes] |

# After
| REQ-X-Y | [Title] | 4 | Done | Commit: [SHA] |
```

### Step 3: Git Commit

```bash
# Stage files
git add docs/progress/REQ-X-Y.md
git add docs/DEV-PROGRESS.md
git add [all modified implementation files]
git add [test files]

# Commit
git commit -m "feat: Implement REQ-X-Y [short title]

Phase 1: Specification extracted and documented
Phase 2: 5 test cases designed and verified
Phase 3: Implementation complete, all tests passing
Phase 4: Progress documentation and tracking updated

Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Step 4: Capture Commit SHA

```bash
git rev-parse HEAD
```

Update progress file and DEV-PROGRESS.md with actual SHA.

## Output Template

```markdown
## Phase 4: SUMMARY

### Documentation Created
- Progress file: docs/progress/REQ-X-Y.md
- DEV-PROGRESS.md: Updated (Phase 0->4, Backlog->Done)

### Git Commit
- SHA: abc1234
- Files committed: X

### Development Complete

REQ-X-Y implementation finished.

| Phase | Status |
|-------|--------|
| 1: Specification | Done |
| 2: Test Design | Done |
| 3: Implementation | Done |
| 4: Documentation | Done |

Progress file: docs/progress/REQ-X-Y.md
```

## Error Handling

### Progress File Write Failed

```yaml
status: WARNING
action: Continue with git commit
fallback: Display progress content for manual creation
```

### DEV-PROGRESS.md Update Failed

```yaml
status: WARNING
action: Provide manual update instructions
```

### Git Commit Failed

```yaml
status: ERROR
action: Provide manual commands
commands:
  - git add [files]
  - git commit -m "[message]"
```

## Validation Checklist

- [ ] Progress file created with all sections
- [ ] All Phase 1-3 content included
- [ ] DEV-PROGRESS.md row updated
- [ ] Git commit successful
- [ ] Commit SHA captured
- [ ] Commit message has proper format
- [ ] Co-Authored-By line present

## Non-Blocking Policy

Phase 4 errors do NOT block completion reporting:
- If documentation fails: warn, continue
- If git fails: provide manual commands
- Always report Phase 3 success to user
