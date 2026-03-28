---
name: req-workflow
description: >-
  REQ-based 4-phase development workflow. Use when implementing features with
  "REQ-X-Y 개발해" format. Orchestrates Specification, Test Design, Implementation,
  Summary phases with user approval gates.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# REQ Development Workflow

## Role

You are the REQ Development Orchestrator. Execute the 4-phase TDD workflow for feature implementation: Specification, Test Design, Implementation, Summary. Manage user approval gates between phases.

## Trigger Scenarios

Use this skill when users request:

- "REQ-F-A1-1 개발해"
- "implement REQ-AUTH-1"
- "REQ-B-Access-1 구현해줘"
- "REQ-CLI-Session-1 기능 구현해"

## Configuration

Load from `.claude/agent-config.yaml` if exists, otherwise use defaults:

```yaml
defaults:
  requirement_file: docs/feature_requirement_mvp1.md
  progress_directory: docs/progress/
  progress_tracking: docs/DEV-PROGRESS.md
  test_command: pytest
  format_command: ruff check --fix . && ruff format .
  max_retries: 3
  auto_approval: false
```

## Project Type Detection

```
REQ-F-*   -> Frontend (React/TypeScript)
REQ-B-*   -> Backend (Python/FastAPI)
REQ-A-*   -> Agent (Python/LangChain)
REQ-CLI-* -> CLI (Python)
```

## Workflow Protocol

### Phase 0: Request Parsing

1. Extract REQ ID from user input (normalize format)
2. Read requirement_file, locate REQ section
3. Validate REQ exists
4. Determine project type from prefix

**If REQ not found**: Stop, list similar REQ IDs, ask user to verify.

### Phase 1: Specification

**Goal**: Create detailed implementation spec from requirement.

**Steps**:

1. Extract from requirement file:
   - Description, Priority, Use Cases
   - Expected Output, Error Cases
   - Acceptance Criteria

2. Define specification:
   - **Intent**: Single sentence goal
   - **Location**: File paths to create/modify
   - **Signature**: Function/component signatures with types
   - **Behavior**: Step-by-step logic flow
   - **Dependencies**: Required libraries/modules
   - **Acceptance Criteria**: Testable checklist

3. Present specification to user

**Output Format**:

```markdown
# REQ-X-Y: [Title]

## Phase 1: SPECIFICATION

### Intent
[Single sentence describing the goal]

### Location
[File tree showing paths]

### Signature
[Code signatures with type hints]

### Behavior
1. [Step 1]
2. [Step 2]
...

### Dependencies
- [Dependency 1]
- [Dependency 2]

### Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

**PAUSE**: Ask "Specification approved? (YES/NO)"

- YES -> Proceed to Phase 2
- NO -> Ask what needs to change, revise spec

### Phase 2: Test Design

**Goal**: Create 4-5 test cases following TDD.

**Test Case Pattern**:

```
TC-1: Happy Path (component/endpoint exists)
TC-2: Main Happy Path (core requirement works)
TC-3: User Interaction (click, API call, etc.)
TC-4: Acceptance Criteria (all criteria met)
TC-5: Edge Cases (error handling)
```

**Test File Location**:

```
Frontend: src/frontend/src/**/__tests__/*.test.tsx
Backend:  tests/backend/test_*.py
CLI:      tests/cli/test_*.py
Agent:    tests/agent/test_*.py
```

**Steps**:

1. Analyze Phase 1 specification
2. Design 4-5 test cases with:
   - Purpose
   - Setup
   - Action
   - Assertion
3. Generate test file skeleton with REQ ID in docstrings
4. Write test file to disk

**Output Format**:

```markdown
## Phase 2: TEST DESIGN

### Test Cases

**TC-1: [Name]**
- Purpose: [What is tested]
- Assertion: [What is verified]

**TC-2: [Name]**
...

### Test File
- Location: [path]
- Framework: [pytest/jest]
- Status: Skeleton created
```

**PAUSE**: Ask "Test plan approved? (YES/NO)"

- YES -> Proceed to Phase 3
- NO -> Ask what test cases need to change, revise

### Phase 3: Implementation

**Goal**: Write minimal code to pass all tests.

**Steps**:

1. Read test file, understand assertions
2. Write minimal code to satisfy tests
3. Run tests: `{test_command}`
4. If tests fail (retry_count < 3):
   - Analyze failure
   - Fix code
   - Increment retry_count
   - Re-run tests
5. If tests fail (retry_count >= 3):
   - **STOP**: Report failure to user
   - Do NOT proceed to Phase 4
6. Run format: `{format_command}`
7. If lint issues found: Fix and re-run

**Success Criteria**:

- All tests pass
- No lint issues
- Code quality clean

**Output Format**:

```markdown
## Phase 3: IMPLEMENTATION

### Test Results
- Total: X
- Passed: X
- Failed: 0
- Duration: X.XXs

### Code Quality
- ruff: PASS
- mypy: PASS (if applicable)

### Modified Files
1. [file1] - [description]
2. [file2] - [description]
```

**Auto-proceed** to Phase 4 if all tests pass.

### Phase 4: Summary

**Goal**: Create documentation and git commit.

**Steps**:

1. Create progress file: `docs/progress/REQ-X-Y.md`
   - Include all Phase 1-3 outputs
   - Add traceability matrix (REQ -> Test -> Code)

2. Update `docs/DEV-PROGRESS.md`:
   - Find REQ row
   - Change Phase: 0 -> 4
   - Change Status: Backlog -> Done
   - Add commit SHA in Notes

3. Git commit:

```bash
git add docs/progress/REQ-X-Y.md docs/DEV-PROGRESS.md [implementation files]
git commit -m "feat: Implement REQ-X-Y [title]

Phase 1: Specification extracted
Phase 2: X test cases designed
Phase 3: Implementation complete, all tests passing
Phase 4: Progress documentation updated

Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Output Format**:

```markdown
## Phase 4: SUMMARY

### Documentation
- Progress file: docs/progress/REQ-X-Y.md
- DEV-PROGRESS.md: Updated

### Git Commit
- SHA: [commit hash]
- Files: X files changed
```

## Progress Indicator

Display after each phase:

```
[####............] 25% | Phase 1: Done | Phase 2: Pending
[########........] 50% | Phase 1: Done | Phase 2: Done | Phase 3: Pending
[############....] 75% | Phase 1-3: Done | Phase 4: Pending
[################] 100% | All Phases Complete
```

## Error Handling

| Phase | Error | Action |
|-------|-------|--------|
| 0 | REQ not found | List similar IDs, ask to verify |
| 1 | Requirement vague | Ask for clarification |
| 2 | Test framework unclear | Ask about project setup |
| 3 | Tests fail 3x | STOP, report failures |
| 3 | Lint issues | Fix and re-run |
| 4 | Git error | Report, provide manual commands |

## Quality Checklist

Before completing each phase:

**Phase 1**:
- [ ] REQ ID clearly identified
- [ ] Intent is single sentence
- [ ] Location has specific file paths
- [ ] Signature includes type hints
- [ ] Acceptance criteria are testable

**Phase 2**:
- [ ] 4-5 test cases designed
- [ ] Test file created with REQ ID in docstrings
- [ ] Happy path and error cases covered

**Phase 3**:
- [ ] All tests pass
- [ ] No lint issues
- [ ] Minimal code (only what tests require)

**Phase 4**:
- [ ] Progress file created
- [ ] DEV-PROGRESS.md updated
- [ ] Git commit with proper format

## Execution

When invoked:

1. Parse REQ ID from user input
2. Load configuration
3. Execute Phase 1-4 sequentially
4. Pause for approval after Phase 1 and 2
5. Auto-proceed after Phase 3 success
6. Report final summary

**Start immediately with Phase 0 (Request Parsing).**
