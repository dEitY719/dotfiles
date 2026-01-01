# REQ Development Workflow Skill

REQ-based 4-phase TDD development workflow for feature implementation.

## Usage

```
User: "REQ-F-A1-1 개발해"
User: "implement REQ-AUTH-1"
User: "REQ-B-Access-1 구현해줘"
```

## Workflow Phases

| Phase | Name | Approval |
|-------|------|----------|
| 1 | Specification | User approval required |
| 2 | Test Design | User approval required |
| 3 | Implementation | Auto (tests pass) |
| 4 | Summary | Auto |

## What It Does

1. **Phase 1: Specification**
   - Extracts requirement from docs/feature_requirement_mvp1.md
   - Creates detailed implementation spec
   - Pauses for user approval

2. **Phase 2: Test Design**
   - Designs 4-5 test cases (TDD)
   - Creates test file skeleton
   - Pauses for user approval

3. **Phase 3: Implementation**
   - Writes minimal code to pass tests
   - Runs tests (max 3 retries)
   - Runs lint checks
   - Auto-proceeds on success

4. **Phase 4: Summary**
   - Creates progress file
   - Updates DEV-PROGRESS.md
   - Git commit with standard format

## Output Files

- `docs/progress/REQ-X-Y.md` - Full development documentation
- `docs/DEV-PROGRESS.md` - Updated status tracking
- Implementation files as needed
- Test files

## Configuration

Optional `.claude/agent-config.yaml`:

```yaml
project:
  paths:
    requirement_file: docs/feature_requirement_mvp1.md
    progress_directory: docs/progress/
    progress_tracking: docs/DEV-PROGRESS.md
  commands:
    test: pytest
    format: ruff check --fix . && ruff format .
```

## Related Files

- `req-phases/_common.md` - Shared configuration
- `req-phases/phase1-spec.md` - Specification protocol
- `req-phases/phase2-test.md` - Test design protocol
- `req-phases/phase3-impl.md` - Implementation protocol
- `req-phases/phase4-summary.md` - Summary protocol
