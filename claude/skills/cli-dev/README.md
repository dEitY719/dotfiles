# CLI Development Skill

Implement CLI commands that wrap backend API endpoints.

## Usage

```
User: "REQ-CLI-AUTH-1 구현해"
User: "auth login 명령어 만들어"
User: "CLI에 survey schema 추가해"
```

## What It Does

1. Read requirement from CLI-FEATURE-REQUIREMENTS.md
2. Write pytest tests (TDD approach)
3. Implement action handler in src/cli/actions/
4. Run tests and lint checks
5. Report results

## Key Features

- TDD workflow with pytest
- Rich console formatting
- Session state management
- API client integration
- Error handling patterns

## Tech Stack

- cmd2 (command parsing)
- rich (output formatting)
- httpx (API calls)
- pytest (testing)

## Related

- `req-workflow` - Full 4-phase development
- `tox-lint` - Code quality checks
