---
name: project-setup
description: >-
  Initialize Python projects with standard configuration files
  (.markdownlint.json, tox.ini, pyproject.toml). Use when starting new Python
  projects or standardizing existing ones.
allowed-tools: Write, Bash, Read, Glob
---

# Project Setup Skill

## Role

You are a Python Project Configuration Specialist. Initialize Python projects with standardized, production-ready configuration files for linting, testing, and formatting.

## Purpose

Automate the creation of essential Python project configuration files, ensuring consistency across projects and reducing manual setup time. Provide a standardized development environment with best practices for code quality, testing, and documentation.

## Trigger Scenarios

Use this skill when users request:

- "Initialize Python project configuration"
- "Set up a new Python project"
- "Create standard config files for Python"
- "프로젝트 초기 설정 파일 생성해"
- "Python 프로젝트 환경 구축해"
- "tox.ini, pyproject.toml 생성해줘"

## Configuration Files Generated

This skill creates three critical configuration files:

1. **.markdownlint.json** - Markdown linting rules
2. **tox.ini** - Test automation and quality checks (ruff, mypy, shellcheck, shfmt, mdlint)
3. **pyproject.toml** - Project metadata, dependencies, and tool configuration

## Implementation Protocol

### Phase 0: Analysis (ALWAYS)

Execute BEFORE creating any files:

1. **Verify Current Directory**

   ```bash
   # Check current location
   pwd

   # List existing files
   ls -la
   ```

2. **Check Existing Configuration**

   - Scan for existing `.markdownlint.json`, `tox.ini`, `pyproject.toml`
   - Identify conflicts and backup needs
   - Determine project name from directory

3. **Extract Git Configuration**

   ```bash
   # Get author information
   git config user.name
   git config user.email
   ```

4. **Plan File Creation**

   - List files to be created
   - Identify placeholders to replace
   - Determine backup strategy for existing files

Output: Project context, git config values, file creation plan

### Phase 1: Backup Existing Files (CONDITIONAL)

Execute ONLY if files already exist:

1. **Backup Strategy**

   ```bash
   # Backup existing files with timestamp
   cp .markdownlint.json .markdownlint.json.backup.$(date +%Y%m%d_%H%M%S)
   cp tox.ini tox.ini.backup.$(date +%Y%m%d_%H%M%S)
   cp pyproject.toml pyproject.toml.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **Inform User**

   - Notify about backups created
   - List backup file locations

### Phase 2: Generate Configuration Files (SEQUENTIAL)

Execute in order:

1. **Create .markdownlint.json**

   ```json
   {
     "default": true,
     "MD013": false,
     "MD033": false
   }
   ```

2. **Create tox.ini**

   Standard template with environments:
   - ruff: Code formatting and linting
   - mypy: Type checking
   - mdlint: Markdown linting
   - shellcheck: Shell script checking
   - shfmt: Shell script formatting
   - py310, py311, py312, py313: Multi-version testing

3. **Create pyproject.toml**

   Replace dynamic placeholders:
   - `{{PROJECT_NAME}}`: Directory name or user-provided name
   - `{{AUTHOR_NAME}}`: From `git config user.name` or "Your Name"
   - `{{AUTHOR_EMAIL}}`: From `git config user.email` or "your.email@example.com"

### Phase 3: Validation (ALWAYS)

Verify ALL:

- [ ] .markdownlint.json created and valid JSON
- [ ] tox.ini created with all required environments
- [ ] pyproject.toml created with correct placeholder replacements
- [ ] All files have proper permissions (readable)
- [ ] Project name matches directory or user input
- [ ] Git config values correctly extracted and applied

### Phase 4: Report (ALWAYS)

Provide summary:

1. **Files Created**

   - List all created files with paths
   - Show placeholder values used

2. **Next Steps**

   ```bash
   # Install dependencies
   pip install -e .[dev]

   # Run quality checks
   tox -e ruff
   tox -e mypy
   tox -e mdlint
   ```

3. **Configuration Details**

   - Project name detected
   - Author information applied
   - Available tox environments

## Configuration Templates

### Template 1: .markdownlint.json

```json
{
  "default": true,
  "MD013": false,
  "MD033": false
}
```

**Purpose**: Markdown linting configuration

- `default: true`: Enable all rules by default
- `MD013: false`: Disable line length limit
- `MD033: false`: Allow inline HTML

### Template 2: tox.ini

```ini
[tox]
envlist = ruff, mypy, mdlint, shellcheck, shfmt
skipsdist = true
skip_missing_interpreters = true

[testenv]
usedevelop = false
deps = .[dev]
setenv =
    target_dir = .
passenv = PATH
allowlist_externals =
    pylint
    mypy
    markdownlint
    pylint-exit
    pytest
    shellcheck
    shfmt

[testenv:lint]
description = Run pylint to check code style and quality
deps =
    .[dev]
commands =
    pylint {env:target_dir}
    ruff check {env:target_dir}

[testenv:ruff]
allowlist_externals = ruff
description = Run ruff to format code and apply auto-fixes
deps = .[dev]
commands =
    ruff format {env:target_dir}
    ruff check {env:target_dir} --fix

[testenv:black]
description = Run black code formatter
deps =
    black
    black[jupyter]
commands = black {env:target_dir}

[testenv:mypy]
description = Run mypy type checker
deps = .[dev]
commands = mypy {env:target_dir}

[testenv:mdlint]
description = Run markdownlint to check markdown files
skip_install = true
allowlist_externals = markdownlint
commands = markdownlint {env:target_dir}/**/*.md

[testenv:shellcheck]
description = Run shellcheck on bash scripts
skip_install = true
allowlist_externals =
    bash
    find
    shellcheck
    xargs
commands = bash -c 'find bash -type f \( -name "*.sh" -o -name "*.bash" \) -print0 | xargs -0 shellcheck -x -e SC1090,SC1091'

[testenv:shfmt]
description = Check shell script formatting with shfmt
skip_install = true
deps =
commands =
    shfmt -w -i 4 bash/

[testenv:shfmt-check]
description = Check shell script formatting with shfmt
skip_install = true
deps =
commands =
    shfmt -d -i 4 bash/

[testenv:py310]
basepython = python3.10
commands = pytest

[testenv:py311]
basepython = python3.11
commands = pytest

[testenv:py312]
basepython = python3.12
commands = pytest

[testenv:py313]
basepython = python3.13
commands = pytest
```

**Purpose**: Test automation and quality orchestration

**Key Environments**:

- `ruff`: Auto-format and fix code issues
- `mypy`: Static type checking
- `mdlint`: Markdown linting
- `shellcheck`: Shell script validation
- `shfmt`: Shell script formatting
- `py310-py313`: Multi-version testing

### Template 3: pyproject.toml

```toml
[build-system]
requires = ["setuptools", "wheel"]
build-backend = "setuptools.build_meta"

[project]
requires-python = ">=3.10"
version = "0.1.0"
name = "{{PROJECT_NAME}}"
description = "Project description here."
authors = [{ name = "{{AUTHOR_NAME}}", email = "{{AUTHOR_EMAIL}}" }]
dependencies = [
    "rich>=14.1.0",
]

[dependency-groups]
dev = ["ruff", "mypy", "pylint-exit", "pytest", "pytest-mock", "tox>=4.26.0"]

[project.optional-dependencies]
dev = [
    "types-toml",
    "types-requests",
    "types-PyYAML",
]

[tool.setuptools]
packages = []

[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]

[tool.black]
line-length = 120
target-version = ['py310', 'py311', "py312", "py313"]
skip-string-normalization = false
exclude = '\.git|\.mypy_cache|\.tox|\.nox|\.venv|build|dist'

[tool.isort]
profile = "black"

[tool.pylint]
max-line-length = 120
ignore = [".venv", ".tox", ".vscode", ".git", "build"]
disable = ["R", "C", "W1203"]

[tool.mypy]
files = ["./"]
strict = true
disallow_untyped_defs = false
disallow_untyped_calls = false
exclude = '(?x)( \.venv/ | \.tox/ | \.vscode/ | \.git/ | build/ | config/tox/ | tests )'

[tool.ruff]
line-length = 120
target-version = "py310"
exclude = [".git", ".mypy_cache", ".tox", ".nox", ".venv", "build", "dist", ".vscode"]

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP"]
ignore = ["G004"]

[tool.ruff.format]
quote-style = "double"
```

**Dynamic Placeholders**:

- `{{PROJECT_NAME}}`: Replaced with directory name
- `{{AUTHOR_NAME}}`: Replaced with git config user.name
- `{{AUTHOR_EMAIL}}`: Replaced with git config user.email

**Purpose**: Project metadata and tool configuration

**Tool Configurations**:

- `ruff`: Line length 120, Python 3.10+ target
- `mypy`: Strict mode with some relaxations
- `pytest`: Test discovery in tests/ directory
- `black`: 120 char lines, multi-version support

## Error Handling

### Missing Git Configuration

If git config not found:

```bash
# Fallback values
AUTHOR_NAME="Your Name"
AUTHOR_EMAIL="your.email@example.com"
```

Notify user:

```text
Git config not found. Using default values:
- Author: Your Name
- Email: your.email@example.com

To update, run:
  git config --global user.name "Your Name"
  git config --global user.email "your.email@example.com"
```

### Files Already Exist

Strategy:

1. Create backups with timestamp
2. Notify user of backup locations
3. Overwrite with new configuration
4. Provide rollback instructions

### Invalid Project Name

If directory name contains invalid characters:

1. Sanitize name (replace spaces/special chars with underscores)
2. Notify user of sanitization
3. Suggest manual update if needed

### Write Permission Issues

If cannot write files:

1. Check permissions: `ls -la .`
2. Suggest: `chmod +w .`
3. Fall back to displaying content for manual creation

## Real-World Example

### Before (Empty Directory)

```bash
$ pwd
/home/user/projects/my-awesome-tool

$ ls -la
total 8
drwxr-xr-x 2 user user 4096 Jan 01 18:00 .
drwxr-xr-x 5 user user 4096 Jan 01 18:00 ..
```

### After (Skill Execution)

```bash
$ ls -la
total 20
drwxr-xr-x 2 user user 4096 Jan 01 18:05 .
drwxr-xr-x 5 user user 4096 Jan 01 18:00 ..
-rw-r--r-- 1 user user   67 Jan 01 18:05 .markdownlint.json
-rw-r--r-- 1 user user 2048 Jan 01 18:05 tox.ini
-rw-r--r-- 1 user user 3500 Jan 01 18:05 pyproject.toml
```

### Generated Content Example

**pyproject.toml** (with placeholders replaced):

```toml
[project]
name = "my-awesome-tool"
authors = [{ name = "John Doe", email = "john@example.com" }]
```

### Next Steps After Setup

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # or `.venv\Scripts\activate` on Windows

# Install project with dev dependencies
pip install -e .[dev]

# Run quality checks
tox -e ruff      # Format code
tox -e mypy      # Type check
tox -e mdlint    # Lint markdown

# Run tests (after creating tests/)
tox -e py312
```

## Execution Workflow

When this skill is invoked:

1. **Analyze** current directory and git config (Phase 0)
2. **Backup** existing files if present (Phase 1)
3. **Generate** all three configuration files (Phase 2)
4. **Validate** file creation and content (Phase 3)
5. **Report** summary and next steps (Phase 4)

**Output**:

- Files created with paths
- Placeholder values used
- Backup locations (if any)
- Next steps for project setup

## Quality Gates

Before completion, ensure ALL:

1. All three files created successfully
2. JSON syntax valid in .markdownlint.json
3. INI syntax valid in tox.ini
4. TOML syntax valid in pyproject.toml
5. Placeholders replaced correctly
6. Git config extracted or defaults applied
7. Backups created if files existed
8. User notified of all actions
9. Next steps provided

## Usage Notes

### When to Use This Skill

- Starting a new Python project
- Standardizing an existing project
- Setting up quality checks and testing
- Creating consistent development environment

### When NOT to Use This Skill

- Non-Python projects (JavaScript, Go, etc.)
- Projects with existing custom configurations you want to preserve
- Simple scripts that don't need full project setup

### Customization After Generation

Users can modify generated files:

- Add more dependencies in pyproject.toml
- Enable/disable tox environments
- Adjust tool settings (line length, etc.)
- Add custom markdown linting rules

## Command

**When invoked, IMMEDIATELY analyze the current directory, extract git configuration, and EXECUTE the project setup workflow following all protocols above.**

Start with Phase 0 analysis and announce the plan before creating any files.
