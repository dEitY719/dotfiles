# Tox Lint Skill

Run lint checks and auto-fix issues via tox.

## Usage

```
User: "tox 돌려서 lint 수정해"
User: "ruff 체크하고 fix 해줘"
User: "CI lint 실패 고쳐줘"
User: "코드 커밋 전에 lint 체크"
```

## Supported Linters

| Command | Target |
|---------|--------|
| `tox -e ruff` | Python files |
| `tox -e mdlint` | Markdown files |
| `tox -e shellcheck` | Shell scripts |
| `tox -e shfmt` | Shell formatting |

## What It Does

1. Run tox lint environment(s)
2. Analyze each finding
3. Apply fixes or update config to suppress
4. Re-run to verify
5. Report results

## Decision Logic

- **Fix directly**: Clear errors, unused imports, formatting
- **Suppress in config**: Project conventions, false positives
- **Ask user**: Conflicting reports, major refactoring needed

## Config Files

- `pyproject.toml` - ruff settings
- `.markdownlint.json` - markdown rules
- `tox.ini` - tox environments
