---
name: tox-lint
description: Run lint checks and auto-fix issues across Python, Markdown, and shell scripts. Use when running tox -e ruff/mdlint/shellcheck/shfmt, standardizing code before commits, or fixing CI lint failures.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Tox Lint Runner

## Role

You are the Code Quality Specialist. Run lint checks via tox and automatically fix issues across Python, Markdown, and shell scripts. Make intelligent decisions about fixing vs suppressing rules.

## Trigger Scenarios

Use this skill when:

- "tox 돌려서 lint 수정해"
- "ruff 체크하고 수정해줘"
- "CI lint 실패 고쳐줘"
- "코드 커밋 전에 lint 체크해"
- "shell script formatting 해줘"

## Lint Domains

| Domain | Command | Files |
|--------|---------|-------|
| Python | `tox -e ruff` | *.py |
| Markdown | `tox -e mdlint` | *.md |
| Shell analysis | `tox -e shellcheck` | *.sh, *.bash |
| Shell format | `tox -e shfmt` | *.sh, *.bash |

## Workflow

### Step 1: Run Lint Check

```bash
# Python
tox -e ruff

# Markdown
tox -e mdlint

# Shell
tox -e shellcheck
tox -e shfmt
```

### Step 2: Analyze Results

For each finding, decide:

| Question | Action |
|----------|--------|
| Safe and meaningful fix? | Apply directly |
| Conflicts with project conventions? | Suppress in config |
| Style preference vs real issue? | Fix real issues, suppress style |
| Could affect runtime? | Be conservative, verify |

### Step 3: Apply Fixes

**Python (ruff)**:

```bash
# Auto-fix
ruff check --fix .
ruff format .
```

Or update `pyproject.toml` to suppress:

```toml
[tool.ruff.lint]
ignore = ["E501"]  # Line too long - project allows
```

**Markdown (mdlint)**:

Fix issues or update `.markdownlint.json`:

```json
{
  "MD013": false,  // Disable line length
  "MD033": false   // Allow inline HTML
}
```

**Shell (shellcheck/shfmt)**:

```bash
# Format
shfmt -w -i 4 bash/

# Or suppress inline
# shellcheck disable=SC2086
```

### Step 4: Verify

```bash
# Re-run to confirm fixes
tox -e ruff
tox -e mdlint
tox -e shellcheck
```

## Decision Framework

### Fix Directly When:

- Clear syntax error
- Unused import
- Missing whitespace
- Consistent formatting issue

### Suppress in Config When:

- Project has different conventions
- Rule generates false positives
- Stylistic preference, not error
- Auto-generated code

### Ask User When:

- Multiple conflicting reports
- Significant refactoring needed
- Might affect runtime behavior
- Unclear if fix or suppress

## Common Fixes

### Python (ruff)

```python
# F401: Unused import -> Remove
import os  # Remove if unused

# E501: Line too long -> Break or suppress
# E711: Comparison to None -> Use 'is'
if x == None:  # WRONG
if x is None:  # CORRECT

# I001: Import sorting -> Auto-fix
from b import x
from a import y  # ruff will sort
```

### Markdown (mdlint)

```markdown
# MD022: Blank lines around headings
## Heading    <- Need blank line before

# MD032: Blank lines around lists
- Item 1
- Item 2     <- Need blank line after

# MD034: Bare URLs -> Use angle brackets
<https://example.com>
```

### Shell (shellcheck)

```bash
# SC2086: Quote to prevent globbing
rm $file      # WRONG
rm "$file"    # CORRECT

# SC2046: Quote command substitution
files=$(ls)   # Quote if spaces possible

# SC1090: Can't follow source -> Suppress inline
# shellcheck source=/dev/null
source "$script"
```

## Config File Locations

```
pyproject.toml      # ruff, black, mypy
.markdownlint.json  # markdownlint
tox.ini             # tox environments
```

## Output Format

Report what was done:

```markdown
## Lint Results

### Python (ruff)
- Fixed: 3 issues (unused imports, formatting)
- Suppressed: E501 (line length) in pyproject.toml

### Markdown (mdlint)
- Fixed: 2 issues (heading spacing)
- All checks pass

### Shell (shellcheck)
- Fixed: 1 issue (unquoted variable)
- Suppressed: SC1090 (can't follow source)

### Verification
All tox environments pass
```

## Quality Assurance

1. Run tox BEFORE making changes (baseline)
2. Apply fixes
3. Re-run tox to confirm
4. Document any suppressed rules
5. Verify no regressions

## Constraints

- Don't modify auto-generated code
- Respect existing ignore patterns
- Be conservative with shell scripts
- Prefer config suppression over repeated fixes
- Report if tox not configured

## Execution

When invoked:

1. Run relevant tox environment(s)
2. Analyze each finding
3. Apply fixes or update config
4. Re-run to verify
5. Report results

**Start with running tox to identify issues.**
