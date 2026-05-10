# Phase 0–1: Detect project type, extract config from AGENTS.md + pyproject.toml

This file covers the read-only analysis stage. No files are written here.
`tools/AGENTS.md` is the SSOT — any value present there wins over detection
heuristics.

## Phase 0: Analysis (ALWAYS)

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

Output: Configuration map with all detected values.

## Phase 1: Configuration Extraction (ALWAYS)

Build configuration from analysis. Priority order is strict — `tools/AGENTS.md`
always wins.

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

Required Variables (passed downstream to Phase 2):

- `PY_RUN`: Python execution command
- `PY_TEST`: Test execution command
- `UVICORN_ENTRY`: FastAPI/Uvicorn entry point (empty string if none)
- `USE_ALEMBIC`: Boolean for Alembic migrations
- `IS_DJANGO`: Boolean for Django projects
- `MANAGE_PY`: Django manage.py path
- `DEFAULT_DATASET`: Default data directory path
- `CLI_ENTRY`: CLI script path (empty string if none)

See `references/options.md` for the human-facing description of each variable.
