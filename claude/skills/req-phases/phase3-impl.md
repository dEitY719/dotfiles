# Phase 3: Implementation Protocol

Internal reference for req-workflow. NOT user-invocable.

## Purpose

Write minimal code to pass all test cases.

## Input

```yaml
req_id: REQ-X-Y
specification: [Phase 1 output]
test_design: [Phase 2 output]
test_file_path: [path to test file]
project_type: frontend|backend|cli|agent
```

## Core Principle

**MINIMAL CODE**: Write only what tests require. No over-engineering.

```python
# BAD: Over-engineered
class FeatureManager:
    def __init__(self):
        self.cache = {}
        self.validators = []
        # 50 more lines...

# GOOD: Minimal
def get_feature(id: str) -> Feature:
    return db.query(Feature).get(id)
```

## Execution Flow

```
retry_count = 0
max_retries = 3

while retry_count < max_retries:
    1. Write/fix implementation code
    2. Run tests
    3. If all pass -> goto lint check
    4. If fail -> retry_count++, analyze failure, loop

if retry_count >= max_retries:
    STOP, report failure
```

## Implementation Steps

1. **Read test file**, extract assertions:
   ```
   TC-1 expects: component renders
   TC-2 expects: button with text "Login"
   TC-3 expects: click calls navigate()
   ```

2. **Map tests to code**:
   ```
   Test -> Required Code
   TC-1 -> export const Component = () => {}
   TC-2 -> <button>Login</button>
   TC-3 -> onClick={() => navigate('/path')}
   ```

3. **Write minimal implementation**

4. **Run tests**:
   ```bash
   # Python
   pytest tests/[domain]/test_[feature].py -v

   # TypeScript
   npm test -- --testPathPattern=[feature]
   ```

5. **If tests fail** (retry_count < 3):
   - Read failure message
   - Identify missing code
   - Add only what's needed
   - Increment retry_count
   - Re-run tests

6. **If tests fail** (retry_count >= 3):
   ```yaml
   status: FAILURE
   reason: Tests failed after 3 attempts
   last_failures:
     - test_name: [name]
       error: [message]
   action_required: Review test expectations or requirements
   ```
   **STOP**: Do not proceed to Phase 4

7. **Run quality checks**:
   ```bash
   # Python
   ruff check --fix .
   ruff format .

   # TypeScript
   npm run lint -- --fix
   ```

8. **If lint issues**: Fix and re-run

## Code Standards

### Python

```python
# Type hints required
async def create_user(request: CreateUserRequest) -> User:
    """Create a new user."""
    ...

# Use Pydantic models
class CreateUserRequest(BaseModel):
    name: str
    email: EmailStr
```

### TypeScript/React

```typescript
// Type props
interface Props {
  title: string;
  onClick: () => void;
}

// Functional components
export const Button: React.FC<Props> = ({ title, onClick }) => (
  <button onClick={onClick}>{title}</button>
);
```

## Output Template

```markdown
## Phase 3: IMPLEMENTATION

### Test Results
```
test_feature.py::test_tc1 PASSED
test_feature.py::test_tc2 PASSED
test_feature.py::test_tc3 PASSED
test_feature.py::test_tc4 PASSED
test_feature.py::test_tc5 PASSED

5 passed in 1.23s
```

### Summary
- Total: 5
- Passed: 5
- Failed: 0
- Duration: 1.23s

### Code Quality
- ruff: PASS (0 issues)
- format: PASS

### Modified Files
1. `src/[path]/[file].py` - [description]
2. `src/[path]/[file].py` - [description]
```

## Validation Checklist

- [ ] All tests pass (5/5)
- [ ] No lint issues
- [ ] Code is minimal (only what tests require)
- [ ] Type hints present
- [ ] No commented-out code
- [ ] No hardcoded values

## Failure Report Format

If stopping due to failures:

```markdown
## Phase 3: IMPLEMENTATION FAILED

### Status: FAILURE

### Retry Attempts: 3/3

### Last Test Results
```
test_feature.py::test_tc2 FAILED
  AssertionError: Expected 'Login', got None
```

### Analysis
[Why tests are failing]

### Action Required
- Review test expectations
- Modify requirements if needed
- Ask for guidance
```

## Success Criteria

Proceed to Phase 4 only when:
- All tests pass
- No lint issues
- Code quality clean
