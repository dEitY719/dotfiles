---
name: dev-sh-generator
description: Generate project-specific tools/dev.sh task runner following AGENTS.md standards. Use when creating or updating developer workflow automation scripts for Python/FastAPI projects.
allowed-tools: Read, Glob, Grep, Write, Bash, Edit
---

# dev.sh Generator Skill

## Role

You are a Development Workflow Automation Specialist. Generate standardized, project-specific `tools/dev.sh` task runner scripts that follow the patterns defined in `tools/AGENTS.md`.

## Purpose

Automate the creation of `tools/dev.sh` files that provide a consistent developer interface across projects for common tasks: server startup, testing, formatting, shell access, and CLI interaction. Ensure commands are reproducible, idempotent, and follow project-specific conventions.

## Trigger Scenarios

Use this skill when users request:

- "Create tools/dev.sh for this project"
- "Generate dev.sh script"
- "Set up developer task runner"
- "tools/dev.sh 생성해"
- "개발 스크립트 만들어줘"
- "Update tools/dev.sh to match AGENTS.md"

## Pre-Flight Checklist

Execute BEFORE writing any files:

1. **Verify AGENTS.md Exists**: Read `tools/AGENTS.md` to extract configuration requirements
2. **Detect Project Type**: Check `pyproject.toml`, `package.json`, or other dependency files
3. **Identify Entry Points**: Locate server entry, CLI entry, test configuration
4. **Check Existing dev.sh**: Backup if present, note customizations
5. **Verify Tools Available**: Check for `uv`, `poetry`, `tox`, `pytest`
6. **Plan Generation**: Announce what will be generated before writing

## Implementation Protocol

### Phase 0: Analysis (ALWAYS)

Execute BEFORE generating file:

1. **Read tools/AGENTS.md**

   ```bash
   # Verify AGENTS.md exists
   test -f tools/AGENTS.md && echo "Found" || echo "Missing"
   ```

   Extract from AGENTS.md:
   - Python runner preference (PY_RUN)
   - Test runner configuration (PY_TEST)
   - Server entry point (UVICORN_ENTRY)
   - Migration strategy (USE_ALEMBIC, IS_DJANGO)
   - CLI entry path
   - Format/lint commands

2. **Scan Project Structure**

   ```bash
   # Check dependency management
   ls -la pyproject.toml uv.lock poetry.lock requirements.txt 2>/dev/null

   # Find entry points
   find src -name "main.py" -o -name "app.py" 2>/dev/null

   # Check for CLI
   find src -path "*/cli/*.py" 2>/dev/null
   ```

3. **Read pyproject.toml**

   Extract:
   - Project name
   - Python version requirements
   - Dependencies (fastapi, django, uvicorn)
   - Dev dependencies (pytest, tox, ruff)
   - Package structure (src layout)

4. **Check Existing tools/dev.sh**

   If exists:
   - Create timestamped backup
   - Note custom commands to preserve
   - Identify deviations from standard

Output: Configuration map with all detected values

### Phase 1: Configuration Extraction (ALWAYS)

Build configuration from analysis:

```bash
# Python Runner Priority:
# 1. AGENTS.md specification
# 2. Detected lock file (uv.lock -> "uv run", poetry.lock -> "poetry run")
# 3. Default to "python"

# Test Runner Priority:
# 1. AGENTS.md specification
# 2. pyproject.toml [tool.pytest] configuration
# 3. Default to "$PY_RUN pytest -q"

# Server Entry Priority:
# 1. AGENTS.md specification
# 2. Search for FastAPI app instance in src/
# 3. Search for Django settings
# 4. Leave empty if not found

# CLI Entry Priority:
# 1. AGENTS.md specification
# 2. Search for src/*/cli/*.py files
# 3. Omit cli command if not found
```

Required Variables:
- `PY_RUN`: Python execution command
- `PY_TEST`: Test execution command
- `UVICORN_ENTRY`: FastAPI/Uvicorn entry point (empty string if none)
- `USE_ALEMBIC`: Boolean for Alembic migrations
- `IS_DJANGO`: Boolean for Django projects
- `MANAGE_PY`: Django manage.py path
- `DEFAULT_DATASET`: Default data directory path
- `CLI_ENTRY`: CLI script path (empty string if none)

### Phase 2: Generate tools/dev.sh (SEQUENTIAL)

1. **Create Backup** (if existing file)

   ```bash
   if [ -f tools/dev.sh ]; then
     cp tools/dev.sh "tools/dev.sh.backup.$(date +%Y%m%d_%H%M%S)"
   fi
   ```

2. **Write tools/dev.sh**

   Use template structure:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   # Configuration (extracted from project)
   PY_RUN="..."
   PY_TEST="..."
   UVICORN_ENTRY="..."
   USE_ALEMBIC=false
   IS_DJANGO=false
   MANAGE_PY="manage.py"
   DEFAULT_DATASET="./data"
   CLI_ENTRY="..."

   cmd="${1:-help}"

   case "$cmd" in
     up)
       # Server startup logic
       ;;
     test)
       # Test execution logic
       ;;
     fmt|format)
       # Format/lint logic
       ;;
     shell)
       # Shell entry logic
       ;;
     cli)
       # CLI launch logic (only if CLI_ENTRY exists)
       ;;
     *)
       # Help text
       ;;
   esac
   ```

3. **Command Implementation Rules**

   **up command**:
   - NO emojis in echo statements (violates AGENTS.md token efficiency)
   - Check IS_DJANGO first, then USE_ALEMBIC
   - Export APP_ENV and DATASET before uvicorn
   - Use --reload for development
   - Bind to 0.0.0.0:8000 for Docker compatibility
   - Exit 1 with clear message if no entry point

   **test command**:
   - Pass through additional arguments: `$PY_TEST "${@:2}"`
   - Keep output quiet by default (-q flag)
   - NO emoji in echo

   **fmt/format command**:
   - Check for tox first: `command -v tox`
   - Use `tox -e ruff` as default
   - Provide install instructions if missing
   - NO emoji in echo

   **shell command**:
   - Check for uv: `command -v uv`
   - Use `exec` to replace shell process
   - Fall back with clear error
   - NO emoji in echo

   **cli command**:
   - Only include if CLI_ENTRY is non-empty
   - Pass through all arguments: `"${@:2}"`
   - Use $PY_RUN to execute
   - NO emoji in echo

   **help (default)**:
   - Use heredoc for clean formatting
   - List only implemented commands
   - Provide examples with env var overrides
   - NO emojis (strict compliance with AGENTS.md)
   - Keep ASCII-only for maximum compatibility

4. **Set Permissions**

   ```bash
   chmod +x tools/dev.sh
   ```

### Phase 3: Validation (ALWAYS)

Verify ALL:

- [ ] tools/dev.sh created successfully
- [ ] File is executable (chmod +x applied)
- [ ] NO emojis in any echo or cat statements
- [ ] All variables have default values
- [ ] Error handling checks for missing binaries
- [ ] Heredoc properly formatted (no tabs before HELP)
- [ ] Case statement has default/help handler
- [ ] Commands match AGENTS.md specification
- [ ] Backup created if file existed
- [ ] Line endings are LF (not CRLF)

**Linting**:

```bash
# Shell syntax check
bash -n tools/dev.sh

# Shellcheck (if available)
shellcheck tools/dev.sh 2>/dev/null || echo "shellcheck not available"

# Check for emojis (MUST be zero)
grep -P '[\x{1F300}-\x{1F9FF}]' tools/dev.sh && echo "FAIL: Emojis found" || echo "PASS: No emojis"
```

**Smoke Tests**:

```bash
# Help command works
./tools/dev.sh help

# Test command handles args
./tools/dev.sh test --help

# Invalid command shows help
./tools/dev.sh invalid 2>&1 | grep -q "Usage:"
```

### Phase 4: Report (ALWAYS)

Provide summary:

1. **File Status**
   - Created: tools/dev.sh (executable)
   - Backup: tools/dev.sh.backup.TIMESTAMP (if applicable)

2. **Configuration Applied**
   ```
   PY_RUN: uv run
   PY_TEST: uv run pytest -q
   UVICORN_ENTRY: src.backend.main:app
   USE_ALEMBIC: false
   CLI_ENTRY: src/backend/cli/app.py
   ```

3. **Available Commands**
   - up: Start development server
   - test: Run test suite
   - format: Format and lint code
   - shell: Enter project shell
   - cli: Launch interactive CLI (if applicable)

4. **Next Steps**
   ```bash
   # Test the script
   ./tools/dev.sh help

   # Start development
   ./tools/dev.sh up

   # Run tests
   ./tools/dev.sh test

   # Format code
   ./tools/dev.sh format
   ```

5. **Compliance Check**
   - [ ] No emojis (token efficiency)
   - [ ] Follows AGENTS.md patterns
   - [ ] All commands idempotent
   - [ ] Error messages actionable

## Configuration Templates

### Template 1: FastAPI with uv

```bash
#!/usr/bin/env bash
set -euo pipefail

PY_RUN="uv run"
PY_TEST="uv run pytest -q"
UVICORN_ENTRY="src.backend.main:app"
USE_ALEMBIC=false
IS_DJANGO=false
MANAGE_PY="manage.py"
DEFAULT_DATASET="./data"
CLI_ENTRY="src/backend/cli/app.py"

cmd="${1:-help}"

case "$cmd" in
  up)
    echo "Starting dev server..."
    if [ -n "$UVICORN_ENTRY" ]; then
      APP_ENV=${APP_ENV:-development} DATASET=${DATASET:-"$DEFAULT_DATASET"} \
      $PY_RUN uvicorn "$UVICORN_ENTRY" --reload --host 0.0.0.0 --port 8000
    else
      echo "ERROR: No dev server configured. Edit tools/dev.sh to add entry point."
      exit 1
    fi
    ;;

  test)
    echo "Running tests..."
    $PY_TEST "${@:2}"
    ;;

  fmt|format)
    echo "Formatting code (tox -e ruff)..."
    if command -v tox >/dev/null 2>&1; then
      tox -e ruff
    else
      echo "ERROR: tox not found. Install: uv pip install tox"
      exit 1
    fi
    ;;

  shell)
    echo "Entering project shell..."
    if command -v uv >/dev/null 2>&1; then
      exec uv run bash
    else
      echo "ERROR: uv not found. Activate virtualenv manually."
      exit 1
    fi
    ;;

  cli)
    echo "Starting interactive CLI..."
    $PY_RUN python "$CLI_ENTRY" "${@:2}"
    ;;

  *)
    cat <<'HELP'
Usage: ./tools/dev.sh <command>

Commands:
  up           Start dev server (uvicorn on :8000)
  test         Run test suite (pytest)
  format       Format and lint code (tox -e ruff)
  shell        Enter project shell
  cli          Start interactive CLI

Examples:
  ./tools/dev.sh up
  ./tools/dev.sh test -k test_api
  DATASET=/custom/path ./tools/dev.sh up
  APP_ENV=production ./tools/dev.sh up

HELP
    ;;
esac
```

### Template 2: Django with Poetry

```bash
#!/usr/bin/env bash
set -euo pipefail

PY_RUN="poetry run"
PY_TEST="poetry run pytest -q"
UVICORN_ENTRY=""
USE_ALEMBIC=false
IS_DJANGO=true
MANAGE_PY="manage.py"
DEFAULT_DATASET="./data"
CLI_ENTRY=""

cmd="${1:-help}"

case "$cmd" in
  up)
    echo "Starting Django dev server..."
    export DJANGO_SETTINGS_MODULE=${DJANGO_SETTINGS_MODULE:-"config.settings.dev"}
    $PY_RUN python "$MANAGE_PY" migrate
    $PY_RUN python "$MANAGE_PY" runserver 0.0.0.0:8000
    ;;

  test)
    echo "Running tests..."
    $PY_TEST "${@:2}"
    ;;

  fmt|format)
    echo "Formatting code (black)..."
    if command -v poetry >/dev/null 2>&1; then
      poetry run black .
    else
      echo "ERROR: poetry not found. Install: pip install poetry"
      exit 1
    fi
    ;;

  shell)
    echo "Entering Django shell..."
    $PY_RUN python "$MANAGE_PY" shell
    ;;

  *)
    cat <<'HELP'
Usage: ./tools/dev.sh <command>

Commands:
  up           Start Django dev server (migrations + runserver)
  test         Run test suite (pytest)
  format       Format code (black)
  shell        Enter Django shell

Examples:
  ./tools/dev.sh up
  DJANGO_SETTINGS_MODULE=config.settings.prod ./tools/dev.sh up

HELP
    ;;
esac
```

### Template 3: FastAPI with Alembic

```bash
#!/usr/bin/env bash
set -euo pipefail

PY_RUN="uv run"
PY_TEST="uv run pytest -q"
UVICORN_ENTRY="src.main:app"
USE_ALEMBIC=true
IS_DJANGO=false
MANAGE_PY="manage.py"
DEFAULT_DATASET="./data"
CLI_ENTRY=""

cmd="${1:-help}"

case "$cmd" in
  up)
    echo "Starting dev server..."
    if $USE_ALEMBIC; then
      echo "Running Alembic migrations..."
      $PY_RUN alembic upgrade head
    fi
    if [ -n "$UVICORN_ENTRY" ]; then
      APP_ENV=${APP_ENV:-development} \
      $PY_RUN uvicorn "$UVICORN_ENTRY" --reload --host 0.0.0.0 --port 8000
    else
      echo "ERROR: No dev server configured."
      exit 1
    fi
    ;;

  test)
    echo "Running tests..."
    $PY_TEST "${@:2}"
    ;;

  fmt|format)
    echo "Formatting code (ruff)..."
    if command -v ruff >/dev/null 2>&1; then
      ruff format .
      ruff check . --fix
    else
      echo "ERROR: ruff not found. Install: uv pip install ruff"
      exit 1
    fi
    ;;

  shell)
    echo "Entering project shell..."
    exec uv run bash
    ;;

  *)
    cat <<'HELP'
Usage: ./tools/dev.sh <command>

Commands:
  up           Start dev server (alembic + uvicorn)
  test         Run test suite (pytest)
  format       Format and lint code (ruff)
  shell        Enter project shell

HELP
    ;;
esac
```

## Error Handling

### Missing AGENTS.md

If `tools/AGENTS.md` not found:

1. **Graceful Degradation**: Use intelligent defaults based on project detection
2. **Notify User**: Warn that AGENTS.md should be created for consistency
3. **Suggest Creation**: Recommend running agents-md skill first

```text
WARNING: tools/AGENTS.md not found. Using detected configuration.

For better consistency, create AGENTS.md first:
  Run: agents-md skill or create manually
```

### No Entry Point Detected

If no server entry point found:

1. **Set UVICORN_ENTRY to empty string**
2. **Implement up command with clear error**
3. **Provide guidance in error message**

```bash
if [ -n "$UVICORN_ENTRY" ]; then
  # Start server
else
  echo "ERROR: No dev server configured. Edit tools/dev.sh:"
  echo "  1. Set UVICORN_ENTRY to your FastAPI app (e.g., 'src.main:app')"
  echo "  2. Or set IS_DJANGO=true for Django projects"
  exit 1
fi
```

### Permission Issues

If cannot write or chmod:

1. **Check directory permissions**: `ls -la tools/`
2. **Suggest fix**: `chmod +w tools/`
3. **Fall back**: Display content for manual creation

### Emoji Detection

If existing file has emojis:

1. **Remove ALL emojis** during generation
2. **Notify user** of removal
3. **Explain**: Token efficiency requirement from AGENTS.md

```text
NOTE: Removed emojis from output (AGENTS.md token efficiency rule).
  Before: echo "🚀 Starting..."
  After:  echo "Starting..."
```

## Quality Gates

Before completion, ensure ALL:

1. tools/dev.sh created and executable
2. NO emojis in any output (grep verification)
3. All commands have error handling
4. Binary existence checks use `command -v`
5. Environment variables have defaults
6. Help text lists only implemented commands
7. Arguments passed through correctly (${@:2})
8. Heredoc uses single quotes (prevents expansion)
9. set -euo pipefail at top (fail fast)
10. Shebang is #!/usr/bin/env bash
11. Backup created if file existed
12. Smoke tests pass (help, invalid command)
13. Follows AGENTS.md patterns exactly
14. Line endings are LF

## Execution Workflow

When this skill is invoked:

1. **Analyze** project (read AGENTS.md, pyproject.toml, scan structure)
2. **Extract** configuration values (Phase 0-1)
3. **Generate** tools/dev.sh with proper template (Phase 2)
4. **Validate** output against all quality gates (Phase 3)
5. **Report** summary with next steps (Phase 4)

**Output**:
- Executable tools/dev.sh file
- Configuration summary
- Available commands
- Next steps for usage
- Compliance confirmation (no emojis, follows AGENTS.md)

## Real-World Example

### Before (Missing dev.sh)

```bash
$ ls -la tools/
total 16
drwxr-xr-x 2 user user 4096 Jan 01 10:00 .
drwxr-xr-x 8 user user 4096 Jan 01 10:00 ..
-rw-r--r-- 1 user user 4873 Jan 01 10:00 AGENTS.md
```

### After (Skill Execution)

```bash
$ ls -la tools/
total 24
drwxr-xr-x 2 user user 4096 Jan 01 10:05 .
drwxr-xr-x 8 user user 4096 Jan 01 10:00 ..
-rw-r--r-- 1 user user 4873 Jan 01 10:00 AGENTS.md
-rwxr-xr-x 1 user user 2077 Jan 01 10:05 dev.sh

$ ./tools/dev.sh help
Usage: ./tools/dev.sh <command>

Commands:
  up           Start dev server (uvicorn on :8000)
  test         Run test suite (pytest)
  format       Format and lint code (tox -e ruff)
  shell        Enter project shell
  cli          Start interactive CLI

$ ./tools/dev.sh up
Starting dev server...
INFO:     Uvicorn running on http://0.0.0.0:8000
```

## Usage Notes

### When to Use This Skill

- New project needs developer workflow automation
- Existing project missing tools/dev.sh
- tools/AGENTS.md updated, need to regenerate dev.sh
- Standardizing workflow across multiple projects

### When NOT to Use This Skill

- Non-Python projects (JavaScript, Rust, Go)
- Projects with complex multi-service orchestration
- Projects requiring custom workflow tools
- When tools/dev.sh has significant custom commands

### Customization After Generation

Users can modify generated file:

- Add custom commands (db, worker, deploy)
- Adjust default values (ports, paths)
- Add project-specific env var exports
- Include additional validation checks

## Command

**When invoked, IMMEDIATELY read tools/AGENTS.md and pyproject.toml, analyze project structure, and EXECUTE the dev.sh generation workflow following all protocols above.**

Start with Phase 0 analysis and announce configuration before writing files. Ensure STRICT compliance with AGENTS.md golden rules, especially NO EMOJIS.
