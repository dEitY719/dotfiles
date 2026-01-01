# Phase 1: Specification Protocol

Internal reference for req-workflow. NOT user-invocable.

## Purpose

Extract requirements and create detailed implementation specification.

## Input

```yaml
req_id: REQ-X-Y
requirement_file: path/to/requirements.md
project_type: frontend|backend|cli|agent
```

## Extraction Steps

1. **Locate REQ** in requirement file:
   ```bash
   grep -A 50 "REQ-X-Y" {requirement_file}
   ```

2. **Extract fields**:
   - Description (from table row)
   - Priority (H/M/L)
   - Use Cases (code examples)
   - Expected Output (JSON/HTML)
   - Error Cases (bullet list)
   - Acceptance Criteria (checklist)

3. **If REQ not found**:
   - List similar REQ IDs
   - Ask user to verify

## Specification Template

```markdown
# REQ-X-Y: [Title from requirement]

## Phase 1: SPECIFICATION

### Requirement Summary
**REQ ID**: REQ-X-Y
**Description**: [From requirement]
**Priority**: [H/M/L]
**Project Type**: [frontend/backend/cli/agent]

### Implementation Spec

#### Intent
[Single sentence: "Enable users to..." or "Provide API for..."]

#### Location
```
src/[domain]/
├── [file1.py/tsx]    # Create
├── [file2.py/tsx]    # Modify
└── [tests]/
    └── test_[feature].py
```

#### Signature
```python
# Backend example
async def feature_name(param: Type) -> ReturnType:
    """Docstring"""
    ...

class FeatureRequest(BaseModel):
    field: Type
```

```typescript
// Frontend example
export const FeatureName: React.FC<Props> = ({ prop }) => {
  ...
}
```

#### Behavior
1. [Step 1: What happens first]
2. [Step 2: What happens next]
3. [Step 3: Expected result]
4. [Step 4: Error handling]

#### Dependencies
- [Library 1] (version)
- [Library 2] (version)
- [Internal module]

#### Acceptance Criteria
- [ ] Criterion 1 (testable)
- [ ] Criterion 2 (testable)
- [ ] Criterion 3 (testable)
```

## Validation Checklist

- [ ] REQ ID matches user request
- [ ] Description extracted from file
- [ ] Intent is single sentence
- [ ] Location has specific file paths
- [ ] Signature has type hints
- [ ] Behavior has numbered steps
- [ ] Dependencies identified
- [ ] Acceptance criteria are testable

## Output

Return specification markdown and ask:

```
Specification complete.

[Display spec]

Specification approved? (YES/NO)
```
