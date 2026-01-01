# Project Setup Skill

A Claude Code skill for initializing Python projects with standardized configuration files for linting, testing, and quality assurance.

## Purpose

Automate the creation of essential Python project configuration files, eliminating manual setup time and ensuring consistency across projects. Sets up a production-ready development environment with best practices for code quality.

## When to Use

Invoke this skill when you need to:

- Initialize a new Python project
- Standardize an existing project's configuration
- Set up quality checks and testing infrastructure
- Create consistent development environments

## Trigger Examples

```bash
# English
"Initialize Python project configuration"
"Set up a new Python project"
"Create standard config files"

# Korean
"프로젝트 초기 설정 파일 생성해"
"Python 프로젝트 환경 구축해"
"tox.ini, pyproject.toml 생성해줘"
```

## What This Skill Does

1. **Analyzes** current directory and git configuration
2. **Backs up** existing files if present
3. **Generates** three configuration files:
   - `.markdownlint.json` - Markdown linting rules
   - `tox.ini` - Test automation orchestration
   - `pyproject.toml` - Project metadata and tool config
4. **Validates** file creation and content
5. **Reports** summary and next steps

## Generated Files

### 1. .markdownlint.json

Markdown linting configuration with sensible defaults:

- Enable all rules by default
- Disable line length limit (MD013)
- Allow inline HTML (MD033)

### 2. tox.ini

Test automation with multiple environments:

- **ruff**: Auto-format and fix code issues
- **mypy**: Static type checking
- **mdlint**: Markdown linting
- **shellcheck**: Shell script validation
- **shfmt**: Shell script formatting
- **py310-py313**: Multi-version Python testing

### 3. pyproject.toml

Project metadata and tool configuration:

- Python 3.10+ requirement
- Rich library dependency
- Dev dependencies (ruff, mypy, pytest, tox)
- Tool configurations (ruff, mypy, black, pylint)
- Auto-populated from git config:
  - Project name (from directory)
  - Author name (from git config user.name)
  - Author email (from git config user.email)

## Example Usage

### Before (Empty Directory)

```bash
$ pwd
/home/user/projects/my-awesome-tool

$ ls -la
total 8
drwxr-xr-x 2 user user 4096 Jan 01 18:00 .
```

### After (Skill Execution)

```bash
$ ls -la
total 20
-rw-r--r-- 1 user user   67 Jan 01 18:05 .markdownlint.json
-rw-r--r-- 1 user user 2048 Jan 01 18:05 tox.ini
-rw-r--r-- 1 user user 3500 Jan 01 18:05 pyproject.toml
```

### Next Steps

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -e .[dev]

# Run quality checks
tox -e ruff      # Format code
tox -e mypy      # Type check
tox -e mdlint    # Lint markdown
```

## Features

### Automatic Git Config Detection

Extracts author information from git configuration:

```bash
git config user.name   → {{AUTHOR_NAME}}
git config user.email  → {{AUTHOR_EMAIL}}
```

Falls back to defaults if git config not found.

### Backup Protection

If files already exist, creates timestamped backups:

```bash
.markdownlint.json.backup.20260101_180500
tox.ini.backup.20260101_180500
pyproject.toml.backup.20260101_180500
```

### Validation Checks

Ensures:

- Valid JSON syntax (.markdownlint.json)
- Valid INI syntax (tox.ini)
- Valid TOML syntax (pyproject.toml)
- Proper placeholder replacement
- File permissions correct

## Error Handling

### Missing Git Configuration

If git config not found, uses defaults and notifies:

```text
Git config not found. Using default values:
- Author: Your Name
- Email: your.email@example.com

To update, run:
  git config --global user.name "Your Name"
  git config --global user.email "your.email@example.com"
```

### Files Already Exist

Creates backups, overwrites with new config, provides rollback instructions.

### Invalid Project Name

Sanitizes directory names with invalid characters, notifies user.

## Customization

After generation, you can customize:

- Dependencies in pyproject.toml
- Tox environments (enable/disable)
- Tool settings (line length, rules)
- Markdown linting rules

## Quality Assurance

Available tox environments for quality checks:

```bash
tox -e ruff       # Auto-format code
tox -e mypy       # Type check
tox -e lint       # Pylint + ruff check
tox -e mdlint     # Markdown lint
tox -e shellcheck # Shell script check
tox -e shfmt      # Shell format check
```

## Related Files

- Skill: `~/dotfiles/claude/skills/project-setup/SKILL.md`

## Version

2.0.0 - Restructured following Claude SKILL patterns with Phase-based protocol

## Author

Generated from Python project setup automation guidelines.
