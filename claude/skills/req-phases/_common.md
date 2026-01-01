# Common REQ Workflow Configuration

Internal reference file for req-workflow skill. NOT user-invocable.

## Configuration Schema

```yaml
# .claude/agent-config.yaml
project:
  paths:
    requirement_file: docs/feature_requirement_mvp1.md
    progress_directory: docs/progress/
    progress_tracking: docs/DEV-PROGRESS.md
  commands:
    test: pytest
    format: ruff check --fix . && ruff format .

agents:
  req_workflow:
    auto_approval: false
    max_retries: 3
    progress_indicator: true
```

## Defaults (when config not found)

```yaml
requirement_file: docs/feature_requirement_mvp1.md
progress_directory: docs/progress/
progress_tracking: docs/DEV-PROGRESS.md
test_command: pytest
format_command: ruff check --fix . && ruff format .
max_retries: 3
auto_approval: false
```

## Project Type Mapping

| Prefix | Type | Stack | Test Dir | Code Dir |
|--------|------|-------|----------|----------|
| REQ-F-* | Frontend | React/TS | src/**/__tests__/ | src/frontend/ |
| REQ-B-* | Backend | Python/FastAPI | tests/backend/ | src/backend/ |
| REQ-A-* | Agent | Python/LangChain | tests/agent/ | src/agent/ |
| REQ-CLI-* | CLI | Python | tests/cli/ | src/cli/ |

## Status Icons

```
Phase Status:
  Pending:     [ ]
  In Progress: [>]
  Complete:    [x]
  Failed:      [!]

REQ Status:
  Backlog:     Backlog
  In Progress: In Progress
  Done:        Done
```

## Git Commit Format

```
feat: Implement REQ-X-Y [short title]

Phase 1: Specification extracted
Phase 2: X test cases designed
Phase 3: Implementation complete, all tests passing
Phase 4: Progress documentation updated

Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Progress File Template

```markdown
# REQ-X-Y: [Title]

**Status**: Done (Phase 4)
**Completion Date**: YYYY-MM-DD

## Summary
[One sentence summary]

## Phase Progress
| Phase | Status | Date |
|-------|--------|------|
| 1: Specification | Done | YYYY-MM-DD |
| 2: Test Design | Done | YYYY-MM-DD |
| 3: Implementation | Done | YYYY-MM-DD |
| 4: Documentation | Done | YYYY-MM-DD |

## Phase 1: Specification
[Content from Phase 1]

## Phase 2: Test Design
[Content from Phase 2]

## Phase 3: Implementation
[Content from Phase 3]

## Phase 4: Summary
- Progress file: [this file]
- Git commit: [SHA]
```

## DEV-PROGRESS.md Update Pattern

Find row:
```
| REQ-X-Y | Feature Name | 0 | Backlog | Notes |
```

Replace with:
```
| REQ-X-Y | Feature Name | 4 | Done | Commit: [SHA] |
```

## Error Response Format

```yaml
status: SUCCESS | FAILURE | PENDING_APPROVAL
phase: 0-4
message: [human readable]
details:
  - [specific info]
action_required: [next steps if any]
```

## Test Framework Detection

```bash
# Python projects
if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  TEST_CMD="pytest"
fi

# Node projects
if [ -f "package.json" ]; then
  if grep -q "vitest" package.json; then
    TEST_CMD="npm run test"
  elif grep -q "jest" package.json; then
    TEST_CMD="npm test"
  fi
fi
```

## Quality Commands

```bash
# Python
pytest tests/ -v
ruff check --fix .
ruff format .
mypy .

# TypeScript/React
npm run test
npm run lint
npm run build
```
