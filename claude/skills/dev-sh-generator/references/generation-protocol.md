# Phase 2–4: Generate tools/dev.sh, validate against quality gates, emit verdict report

## Phase 2: Generate tools/dev.sh (SEQUENTIAL)

1. **Create Backup** (if existing file)

   ```bash
   if [ -f tools/dev.sh ]; then
     cp tools/dev.sh "tools/dev.sh.backup.$(date +%Y%m%d_%H%M%S)"
   fi
   ```

2. **Write tools/dev.sh**

   Use template structure (pick T1/T2/T3 from `references/templates.md`):

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

   **lint command**:
   - Run linters excluding markdown: `tox -e ruff,mypy,shellcheck,shfmt`
   - Covers: ruff (Python format/lint), mypy (type check), shellcheck (bash), shfmt (bash format)
   - Markdown linting available separately via `mdlint` command
   - Rationale: Markdown errors can be numerous; separate for selective use
   - NO emoji in echo

   **mdlint command** (optional, separate):
   - Only include if project has markdown files
   - Run markdown linter: `tox -e mdlint "${@:2}"`
   - Allows users to run markdown checks on-demand
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

## Phase 3: Validation (ALWAYS)

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

## Phase 4: Report (ALWAYS)

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
