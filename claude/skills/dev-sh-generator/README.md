# dev-sh-generator

Generate project-specific `tools/dev.sh` task runner scripts following AGENTS.md standards.

## Quick Start

```bash
# Invoke the skill
/dev-sh-generator

# Or ask naturally
"Create tools/dev.sh for this project"
"tools/dev.sh 생성해줘"
```

## What This Skill Does

Automatically generates a standardized `tools/dev.sh` script that provides a consistent interface for common development tasks:

- **up**: Start development server (FastAPI/Django)
- **test**: Run test suite with pytest
- **format**: Format and lint code (tox -e ruff)
- **shell**: Enter project shell environment
- **cli**: Launch interactive CLI (if present)

## Prerequisites

The skill works best when:

1. **tools/AGENTS.md exists** - Contains project configuration and standards
2. **pyproject.toml present** - Defines project structure and dependencies
3. **Project structure detected** - src/ directory with backend/main.py or similar

## How It Works

1. **Analyzes** your project:
   - Reads tools/AGENTS.md for configuration
   - Scans pyproject.toml for dependencies
   - Detects entry points (FastAPI app, Django settings, CLI)
   - Identifies tool chain (uv, poetry, pip)

2. **Generates** tools/dev.sh:
   - Configures Python runner (uv run, poetry run, python)
   - Sets up test runner (pytest with options)
   - Configures server entry point
   - Adds migration support (Alembic/Django)
   - Includes CLI launcher if detected
   - NO emojis (token efficiency per AGENTS.md)

3. **Validates** output:
   - Checks syntax with bash -n
   - Verifies no emojis present
   - Tests help command
   - Ensures executable permissions

## Generated Script Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# Auto-detected configuration
PY_RUN="uv run"                          # From: uv.lock detection
PY_TEST="uv run pytest -q"               # From: pyproject.toml
UVICORN_ENTRY="src.backend.main:app"     # From: src/ scan
USE_ALEMBIC=false                        # From: AGENTS.md
CLI_ENTRY="src/backend/cli/app.py"       # From: cli/ detection

# Command routing
case "$cmd" in
  up)       # Start server
  test)     # Run tests
  format)   # Lint/format
  shell)    # Enter shell
  cli)      # Launch CLI
  *)        # Help text
esac
```

## Configuration Sources

The skill reads configuration from multiple sources (in priority order):

### 1. tools/AGENTS.md (Highest Priority)

```markdown
# 3. Inputs to Collect Before Editing

- **Python runner**: `uv run`
- **Test runner**: `uv run pytest -q`
- **App entry**: `src.backend.main:app`
- **CLI entry**: `src/backend/cli/app.py`
```

### 2. Project Detection (Medium Priority)

- **Lock files**: uv.lock → "uv run", poetry.lock → "poetry run"
- **Entry points**: Find FastAPI app instances in src/
- **CLI scripts**: Search for src/*/cli/*.py files
- **Migrations**: Detect alembic.ini or Django settings

### 3. Defaults (Fallback)

- PY_RUN: "python"
- PY_TEST: "pytest -q"
- UVICORN_ENTRY: "" (error if empty)
- USE_ALEMBIC: false
- IS_DJANGO: false

## Examples

### Example 1: FastAPI with uv

**Input**: Project with uv.lock, src/backend/main.py (FastAPI app)

**Output**: tools/dev.sh
```bash
PY_RUN="uv run"
PY_TEST="uv run pytest -q"
UVICORN_ENTRY="src.backend.main:app"
CLI_ENTRY="src/backend/cli/app.py"
```

**Usage**:
```bash
./tools/dev.sh up           # Start FastAPI on :8000
./tools/dev.sh test         # Run pytest
./tools/dev.sh format       # Run tox -e ruff
./tools/dev.sh cli          # Launch CLI
```

### Example 2: Django with Poetry

**Input**: Project with poetry.lock, manage.py, Django settings

**Output**: tools/dev.sh
```bash
PY_RUN="poetry run"
PY_TEST="poetry run pytest -q"
IS_DJANGO=true
MANAGE_PY="manage.py"
```

**Usage**:
```bash
./tools/dev.sh up           # Migrate + runserver
./tools/dev.sh test         # Run pytest
./tools/dev.sh shell        # Django shell
```

### Example 3: FastAPI with Alembic

**Input**: Project with alembic.ini, FastAPI app

**Output**: tools/dev.sh
```bash
PY_RUN="uv run"
UVICORN_ENTRY="src.main:app"
USE_ALEMBIC=true
```

**Usage**:
```bash
./tools/dev.sh up           # Alembic upgrade + uvicorn
./tools/dev.sh test         # Run tests
```

## Important Rules

### NO Emojis (Token Efficiency)

Per AGENTS.md golden rules, generated scripts NEVER include emojis:

```bash
# WRONG (old style with emojis)
echo "🚀 Starting dev server..."
echo "🧪 Running tests..."

# CORRECT (AGENTS.md compliant)
echo "Starting dev server..."
echo "Running tests..."
```

### Idempotent Commands

All commands are safe to run multiple times:

```bash
./tools/dev.sh up    # First run: starts server
./tools/dev.sh up    # Second run: fails with clear error (port in use)
```

### Error Handling

All commands check for required tools:

```bash
if command -v tox >/dev/null 2>&1; then
  tox -e ruff
else
  echo "ERROR: tox not found. Install: uv pip install tox"
  exit 1
fi
```

### Argument Pass-Through

Commands accept additional arguments:

```bash
./tools/dev.sh test                    # Run all tests
./tools/dev.sh test -k test_api        # Run specific test
./tools/dev.sh test -v                 # Verbose output
```

## Customization

After generation, you can customize tools/dev.sh:

### Add Custom Commands

```bash
case "$cmd" in
  # ... existing commands ...

  db)
    echo "Running database migrations..."
    $PY_RUN alembic upgrade head
    ;;

  worker)
    echo "Starting background worker..."
    $PY_RUN celery -A src.worker worker
    ;;

  # ... rest of file ...
esac
```

### Adjust Defaults

```bash
# Change port
$PY_RUN uvicorn "$UVICORN_ENTRY" --reload --port 3000

# Add environment variables
export DEBUG=true
export LOG_LEVEL=debug
$PY_RUN uvicorn "$UVICORN_ENTRY" --reload
```

### Add Validation

```bash
up)
  echo "Starting dev server..."

  # Custom validation
  if [ ! -f .env ]; then
    echo "ERROR: .env file missing. Copy from .env.example"
    exit 1
  fi

  # Start server
  $PY_RUN uvicorn "$UVICORN_ENTRY" --reload
  ;;
```

## Troubleshooting

### "No dev server configured"

**Problem**: UVICORN_ENTRY is empty

**Solution**:
1. Check tools/AGENTS.md has App entry specified
2. Or manually edit tools/dev.sh and set UVICORN_ENTRY
3. Or verify FastAPI app exists in src/

```bash
# Fix in tools/dev.sh
UVICORN_ENTRY="src.backend.main:app"  # Your app location
```

### "tox not found"

**Problem**: tox not installed

**Solution**: Install tox
```bash
uv pip install tox
# Or
poetry add --group dev tox
# Or
pip install tox
```

### "permission denied"

**Problem**: tools/dev.sh not executable

**Solution**: Set execute permission
```bash
chmod +x tools/dev.sh
```

### "Emojis detected in output"

**Problem**: Custom commands added emojis

**Solution**: Remove all emojis per AGENTS.md rules
```bash
# Run this to find emojis
grep -P '[\x{1F300}-\x{1F9FF}]' tools/dev.sh

# Replace emojis with text
# Wrong: echo "🚀 Starting..."
# Right: echo "Starting..."
```

## Integration with AGENTS.md

This skill follows the standards defined in tools/AGENTS.md:

1. **Command Contract**: Implements up, test, fmt, shell, cli commands
2. **Configuration Variables**: Uses PY_RUN, PY_TEST, UVICORN_ENTRY patterns
3. **Error Handling**: Checks binaries, provides actionable errors
4. **Token Efficiency**: NO emojis in output
5. **Idempotency**: Safe to run commands multiple times
6. **Extensibility**: Easy to add project-specific commands

## Related Skills

- **agents-md**: Generate tools/AGENTS.md documentation
- **project-setup**: Initialize Python project config files
- **tox-lint**: Run linting and formatting checks

## Workflow Recommendation

1. **First**: Run `agents-md` skill to create tools/AGENTS.md
2. **Second**: Run `dev-sh-generator` skill to create tools/dev.sh
3. **Third**: Run `project-setup` skill for tox.ini, pyproject.toml

This ensures tools/dev.sh has correct configuration from AGENTS.md.

## Output Files

**Created**:
- `tools/dev.sh` (executable, 2-3KB)

**Backed Up** (if existing):
- `tools/dev.sh.backup.YYYYMMDD_HHMMSS`

**Modified**:
- None (only creates new file or overwrites with backup)

## Validation Checklist

After generation, the skill verifies:

- [x] tools/dev.sh created and executable
- [x] NO emojis in any echo/cat statements
- [x] All variables have default values
- [x] Error handling for missing binaries
- [x] Help text shows only implemented commands
- [x] Shebang: #!/usr/bin/env bash
- [x] Fail-fast: set -euo pipefail
- [x] Heredoc uses single quotes
- [x] Arguments passed through: "${@:2}"
- [x] Line endings are LF (not CRLF)

## License

Follows project licensing. See main repository LICENSE file.
