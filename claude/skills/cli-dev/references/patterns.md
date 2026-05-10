# cli-dev — 5 패턴 + 출력 포맷 + 명명 규칙

## Pattern 1: Input Validation

```python
# CORRECT
if not username:
    console.print("Usage: auth login [username]", markup=False)
    return False

# WRONG - crashes on None
response = await self.api_client.post(...)
```

## Pattern 2: Session State

```python
# CORRECT - persists across commands
self.context.session.token = response["token"]

# WRONG - lost after function returns
token = response["token"]
```

## Pattern 3: Rich Output (markup=False!)

```python
# CORRECT - brackets preserved
console.print("Usage: cmd [ARG]", markup=False)

# WRONG - brackets interpreted as markup tags
console.print("Usage: cmd [ARG]")  # Brackets disappear!
```

## Pattern 4: Auth Check

```python
# CORRECT
if not self.context.session.token:
    console.print(
        "Not authenticated. Run: auth login [user]",
        markup=False,
        style="red",
    )
    return False
```

## Pattern 5: Error Handling

```python
# CORRECT - graceful handling
try:
    response = await self.api_client.post(...)
except Exception as e:
    console.print(f"Error: {e}", style="red", markup=False)
    return False

# WRONG - crashes CLI
response = await self.api_client.post(...)
```

## Output Formatting

```python
# Success
console.print("Success message", style="green")

# Error
console.print("Error message", style="red")

# Progress
console.print("Processing...", style="yellow")

# Details (indented)
console.print(f"  Detail: {value}", markup=False)
```

## Command Naming

```
CORRECT:
  auth login
  survey schema
  questions generate

WRONG:
  login (too vague)
  get_schema (not CLI style)
```

## Validation Checklist (Step 5 직후)

- [ ] Tests cover happy path + error cases
- [ ] All tests pass
- [ ] Session state updated correctly
- [ ] `markup=False` for usage messages
- [ ] Error handling (no crashes)
- [ ] Lint checks pass
