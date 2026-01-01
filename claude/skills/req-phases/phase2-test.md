# Phase 2: Test Design Protocol

Internal reference for req-workflow. NOT user-invocable.

## Purpose

Design 4-5 test cases and generate test file skeleton (TDD approach).

## Input

```yaml
req_id: REQ-X-Y
specification: [Phase 1 output]
project_type: frontend|backend|cli|agent
```

## Test Case Pattern

Design exactly 4-5 test cases:

| TC | Name | Purpose |
|----|------|---------|
| TC-1 | Happy Path Basic | Component/endpoint exists and renders/responds |
| TC-2 | Main Happy Path | Core requirement functionality works |
| TC-3 | User Interaction | Click/submit/API call triggers correct action |
| TC-4 | Acceptance Criteria | All acceptance criteria verified |
| TC-5 | Edge Cases | Error handling, invalid input, timeouts |

## Test File Location

```yaml
frontend:
  pattern: src/frontend/src/**/__tests__/{feature}.test.tsx
  framework: jest | vitest

backend:
  pattern: tests/backend/test_{feature}.py
  framework: pytest

cli:
  pattern: tests/cli/test_{command}.py
  framework: pytest

agent:
  pattern: tests/agent/test_{feature}.py
  framework: pytest
```

## Test Template: Python (pytest)

```python
"""
Test suite for REQ-X-Y: [Title]
"""
import pytest

class TestFeatureName:
    """Tests for [feature] - REQ: REQ-X-Y"""

    def test_tc1_basic_happy_path(self):
        """TC-1: [Component/endpoint] exists and works"""
        # REQ: REQ-X-Y
        # Setup
        # Action
        # Assert
        pass

    def test_tc2_main_functionality(self):
        """TC-2: [Core requirement] works correctly"""
        # REQ: REQ-X-Y
        pass

    def test_tc3_user_interaction(self):
        """TC-3: [User action] triggers correct response"""
        # REQ: REQ-X-Y
        pass

    def test_tc4_acceptance_criteria(self):
        """TC-4: All acceptance criteria met"""
        # REQ: REQ-X-Y
        # AC-1: [criterion]
        # AC-2: [criterion]
        pass

    def test_tc5_error_handling(self):
        """TC-5: Error cases handled gracefully"""
        # REQ: REQ-X-Y
        pass
```

## Test Template: TypeScript (Jest/Vitest)

```typescript
/**
 * Test suite for REQ-X-Y: [Title]
 */
import { render, screen, fireEvent } from '@testing-library/react';
import { FeatureName } from '../FeatureName';

describe('FeatureName', () => {
  // REQ: REQ-X-Y

  test('TC-1: renders without error', () => {
    render(<FeatureName />);
    // Assert component exists
  });

  test('TC-2: displays main functionality', () => {
    render(<FeatureName />);
    // Assert core requirement
  });

  test('TC-3: handles user interaction', () => {
    render(<FeatureName />);
    // Simulate click/input
    // Assert correct behavior
  });

  test('TC-4: meets acceptance criteria', () => {
    render(<FeatureName />);
    // Verify all criteria
  });

  test('TC-5: handles error states', () => {
    render(<FeatureName />);
    // Test error handling
  });
});
```

## Output Template

```markdown
## Phase 2: TEST DESIGN

### Test Case Overview
**Total Test Cases**: 5
**Framework**: [pytest/jest/vitest]
**Coverage Target**: 100% of acceptance criteria

### Test Cases

**TC-1: [Name]**
- Purpose: [What is tested]
- Setup: [Required setup]
- Action: [What action is performed]
- Assertion: [What is verified]

**TC-2: [Name]**
...

**TC-3: [Name]**
...

**TC-4: [Name]**
...

**TC-5: [Name]**
...

### Test File
- Location: [exact path]
- Status: Skeleton created
- Lines: ~[N]
```

## Validation Checklist

- [ ] 4-5 test cases designed
- [ ] TC-1 is basic existence check
- [ ] TC-2 covers core requirement
- [ ] TC-3 covers user interaction
- [ ] TC-4 verifies acceptance criteria
- [ ] TC-5 covers error cases
- [ ] REQ ID in all docstrings
- [ ] Test file written to disk
- [ ] File location matches project type

## Output

Write test file, then ask:

```
Test design complete.

[Display test case summary]

Test file created: [path]

Test plan approved? (YES/NO)
```
