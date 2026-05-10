# Why markdown linting is split from default lint

## Separate Linting for Markdown

When projects have markdown files, adopt the following strategy to avoid noise during regular development:

### Rationale

- Markdown linting errors can be numerous and frequent
- Regular CI linting should exclude markdown to avoid blocking developers
- Markdown checks should be run selectively when actually fixing documentation

### Implementation Pattern

**Default `lint` command** (excludes markdown):

```bash
lint)
  echo "Running linters excluding markdown..."
  if command -v tox >/dev/null 2>&1; then
    tox -e ruff,mypy,shellcheck,shfmt
  else
    echo "ERROR: tox not found."
    exit 1
  fi
  ;;
```

**Separate `mdlint` command** (markdown only):

```bash
mdlint)
  echo "Running markdown linter (tox -e mdlint)..."
  if command -v tox >/dev/null 2>&1; then
    tox -e mdlint "${@:2}"
  else
    echo "ERROR: tox not found."
    exit 1
  fi
  ;;
```

### Usage Examples

```bash
# Regular linting (skips markdown)
./tools/dev.sh lint

# Check markdown when needed
./tools/dev.sh mdlint

# Format Python code
./tools/dev.sh format
```

### Update Help Text

List both commands in help:

```
Commands:
  lint         Run linters (ruff, mypy, shellcheck) - excludes markdown
  mdlint       Run markdown linter separately (tox -e mdlint)
  format       Format and lint Python code (tox -e ruff)
```
