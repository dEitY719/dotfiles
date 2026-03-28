---
name: cli-dev
description: >-
  CLI feature development skill. Implements CLI commands that wrap backend API
  endpoints. Follows TDD workflow with pytest, Rich console formatting, and
  session management. Use when implementing REQ-CLI-* requirements.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# CLI Feature Development

## Role

You are the CLI Development Specialist. Implement CLI commands that wrap backend API endpoints for developer testing. Follow TDD approach with pytest, use Rich for console output, and manage session state properly.

## Trigger Scenarios

Use this skill when:

- "REQ-CLI-AUTH-1 구현해"
- "CLI에 survey schema 명령어 추가해"
- "auth login 명령어 만들어"
- Implementing any REQ-CLI-* requirement

## Tech Stack

- **Command Parsing**: cmd2 (interactive shell)
- **Output Formatting**: rich (colors, tables, panels)
- **HTTP Client**: httpx (async API calls)
- **Testing**: pytest + unittest.mock

## Project Structure

```
src/cli/
├── main.py              # CLI entry point
├── context.py           # CLIContext (session state)
├── client.py            # APIClient (httpx wrapper)
├── actions/             # Command handlers
│   ├── auth.py
│   ├── survey.py
│   └── ...
tests/cli/
├── test_auth_actions.py
├── test_survey_actions.py
└── ...
```

## Workflow

### Step 1: Read Requirement

Extract from `docs/CLI-FEATURE-REQUIREMENTS.md`:

```yaml
req_id: REQ-CLI-AUTH-1
command: "auth login [username]"
api_endpoint: "POST /auth/login"
session_state: ["token", "user_id"]
error_cases: ["server error", "invalid input"]
```

### Step 2: Write Tests First (TDD)

Create `tests/cli/test_<domain>_actions.py`:

```python
import pytest
from unittest.mock import AsyncMock, patch
from src.cli.actions.auth import AuthActions
from src.cli.context import CLIContext

class TestAuthActions:
    """Tests for REQ-CLI-AUTH-1"""

    @pytest.fixture
    def context(self):
        return CLIContext()

    @pytest.fixture
    def actions(self, context):
        return AuthActions(context)

    @pytest.mark.asyncio
    async def test_login_success(self, actions, context):
        """TC-1: Successful login stores JWT"""
        with patch.object(
            actions.api_client, "post",
            new_callable=AsyncMock,
            return_value={"token": "jwt...", "user_id": "123"}
        ):
            result = await actions.login("user")
            assert result is True
            assert context.session.token == "jwt..."

    @pytest.mark.asyncio
    async def test_login_missing_arg(self, actions):
        """TC-2: Missing username shows usage"""
        result = await actions.login(None)
        assert result is False

    @pytest.mark.asyncio
    async def test_login_api_error(self, actions):
        """TC-3: API error handled gracefully"""
        with patch.object(
            actions.api_client, "post",
            new_callable=AsyncMock,
            side_effect=Exception("Network error")
        ):
            result = await actions.login("user")
            assert result is False
```

### Step 3: Implement Action Handler

Create `src/cli/actions/<domain>.py`:

```python
from rich.console import Console
from src.cli.client import APIClient
from src.cli.context import CLIContext

console = Console()

class AuthActions:
    """Auth CLI actions - REQ-CLI-AUTH-1"""

    def __init__(self, context: CLIContext):
        self.context = context
        self.api_client = APIClient(context)

    async def login(self, username: str | None) -> bool:
        # 1. Validate input
        if not username:
            console.print("Usage: auth login [username]", markup=False)
            return False

        # 2. Call API
        try:
            console.print(f"Logging in as '{username}'...", style="yellow")
            response = await self.api_client.post(
                "/auth/login",
                json={"username": username}
            )

            # 3. Update session
            self.context.session.token = response["token"]
            self.context.session.user_id = response["user_id"]

            # 4. Display success
            console.print(f"Successfully logged in", style="green")
            return True

        except Exception as e:
            # 5. Handle error
            console.print(f"Login failed: {e}", style="red")
            return False
```

### Step 4: Run Tests

```bash
pytest tests/cli/test_<domain>_actions.py -v
```

### Step 5: Run Quality Checks

```bash
ruff check --fix src/cli/
ruff format src/cli/
```

## Key Patterns

### Pattern 1: Input Validation

```python
# CORRECT
if not username:
    console.print("Usage: auth login [username]", markup=False)
    return False

# WRONG - crashes on None
response = await self.api_client.post(...)
```

### Pattern 2: Session State

```python
# CORRECT - persists across commands
self.context.session.token = response["token"]

# WRONG - lost after function returns
token = response["token"]
```

### Pattern 3: Rich Output (markup=False!)

```python
# CORRECT - brackets preserved
console.print("Usage: cmd [ARG]", markup=False)

# WRONG - brackets interpreted as markup tags
console.print("Usage: cmd [ARG]")  # Brackets disappear!
```

### Pattern 4: Auth Check

```python
# CORRECT
if not self.context.session.token:
    console.print("Not authenticated. Run: auth login [user]",
                  markup=False, style="red")
    return False
```

### Pattern 5: Error Handling

```python
# CORRECT - graceful handling
try:
    response = await self.api_client.post(...)
except Exception as e:
    console.print(f"Error: {e}", style="red")
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

## Validation Checklist

Before completing:

- [ ] Tests cover happy path + error cases
- [ ] All tests pass
- [ ] Session state updated correctly
- [ ] `markup=False` for usage messages
- [ ] Error handling (no crashes)
- [ ] Lint checks pass

## Execution

When invoked:

1. Read requirement from CLI-FEATURE-REQUIREMENTS.md
2. Write pytest tests (TDD)
3. Implement action handler
4. Run tests
5. Run lint checks
6. Report results

**Start with reading the requirement.**
