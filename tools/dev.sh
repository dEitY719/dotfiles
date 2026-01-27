#!/usr/bin/env bash
# DO NOT use 'set -e' or 'set -euo pipefail' at top level
# This causes the script to exit when subprocess fails
set -uo pipefail

# Configuration (dotfiles project - bash configuration management)

# Helper function to check help function integrity
_check_help_integrity() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  local my_help_path="$repo_root/shell-common/functions/my_help.sh"
  if [ ! -f "$my_help_path" ]; then
    echo "ERROR: my_help.sh not found."
    return 1
  fi

  local found=0
  local checked=0
  local violations=""

  # Find all public help functions in shell-common/functions (exclude internal _* functions)
  while IFS= read -r file; do
    [ -z "$file" ] && continue

    # Extract function names ending with 'help' (excluding those starting with _)
    local funcs
    funcs=$(grep -E '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z][a-zA-Z0-9_-]*help[[:space:]]*(\(\))?[[:space:]]*\{' "$file" | \
      sed -E 's/^[[:space:]]*(function[[:space:]]+)?//; s/[[:space:]]*(\(\))?[[:space:]]*\{.*//' | \
      grep -v '^_')

    while read -r func; do
      [ -z "$func" ] && continue
      ((checked++))

      # Check if registered in my_help.sh
      # Try both underscore and dash versions since they can be registered either way
      local dash_version="${func//_/-}"
      local underscore_version="${func//-/_}"

      if ! grep -Eq "HELP_DESCRIPTIONS\\[\"?${func}\"?\\]|HELP_DESCRIPTIONS\\[\"?${dash_version}\"?\\]|HELP_DESCRIPTIONS\\[\"?${underscore_version}\"?\\]" "$my_help_path"; then
        violations="${violations}  ⚠ $file: Public function '$func' not registered in HELP_DESCRIPTIONS\\n"
        ((found++))
      fi
    done <<< "$funcs"
  done < <(find "$repo_root/shell-common/functions" -name "*.sh" -type f)

  if [ $checked -eq 0 ]; then
    echo "No help functions found."
    return 0
  fi

  if [ $found -eq 0 ]; then
    echo "✓ All $checked help functions are properly registered."
    return 0
  else
    echo ""
    echo "⚠ Found $found unregistered help function(s) out of $checked checked:"
    echo ""
    echo -e "$violations"
    return 1
  fi
}

# Helper function to check for unused internal functions
_check_deadcode() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  if [ ! -d "$repo_root/shell-common/functions" ]; then
    echo "ERROR: shell-common/functions directory not found."
    return 1
  fi

  local found=0
  local checked=0

  while IFS= read -r file; do
    [ -z "$file" ] && continue

    # Find all internal functions: ^_function_name()
    while IFS= read -r line_num line_text; do
      [ -z "$line_num" ] && continue

      # Extract function name
      local func_name
      func_name=$(echo "$line_text" | sed -E 's/^[[:space:]]*([a-z_][a-z0-9_]*)\(\).*/\1/')

      ((checked++))

      # Count occurrences in entire repo (grepping for the function name)
      # Use word boundaries to avoid partial matches
      local count
      count=$(grep -rw "$func_name" "$repo_root" \
        --include="*.sh" --include="*.zsh" --include="*.bash" 2>/dev/null | \
        wc -l)

      # If only 1 match (the definition line itself), potentially unused
      if [ "$count" -eq 1 ]; then
        local file_relative
        file_relative="${file#$repo_root/}"
        echo "  ⚠ $file_relative:$line_num - Potentially unused: $func_name()"
        ((found++))
      fi
    done < <(grep -n "^[[:space:]]*_[a-z_][a-z0-9_]*()[[:space:]]*{" "$file")
  done < <(find "$repo_root/shell-common/functions" -name "*.sh" -type f)

  echo ""
  if [ $checked -eq 0 ]; then
    echo "No internal functions found."
    return 0
  elif [ $found -eq 0 ]; then
    echo "✓ All $checked internal functions are in use."
    return 0
  else
    echo "⚠ Found $found potentially unused internal function(s) out of $checked checked."
    return 1
  fi
}

cmd="${1:-help}"
EXIT_CODE=0

case "$cmd" in
  test)
    echo "Running tests via tests/test..."
    if [ -x "./tests/test" ]; then
      ./tests/test "${@:2}"
      EXIT_CODE=$?
    else
      echo "ERROR: tests/test not found or not executable."
      EXIT_CODE=1
    fi
    ;;

  fmt|format)
    echo "Formatting code (tox -e ruff)..."
    if command -v tox >/dev/null 2>&1; then
      tox -e ruff
      EXIT_CODE=$?
    else
      echo "ERROR: tox not found. Install: uv pip install tox"
      EXIT_CODE=1
    fi
    ;;

  lint)
    echo "Running linters excluding markdown (ruff, mypy, shellcheck, shfmt)..."
    if command -v tox >/dev/null 2>&1; then
      tox -e ruff,mypy,shellcheck,shfmt
      EXIT_CODE=$?
    else
      echo "ERROR: tox not found. Install: uv pip install tox"
      EXIT_CODE=1
    fi
    ;;

  mdlint)
    echo "Running markdown linter (tox -e mdlint)..."
    if command -v tox >/dev/null 2>&1; then
      tox -e mdlint "${@:2}"
      EXIT_CODE=$?
    else
      echo "ERROR: tox not found. Install: uv pip install tox"
      EXIT_CODE=1
    fi
    ;;

  lint-helpfunc)
    echo "Checking help function integrity (*help)..."
    echo ""
    _check_help_integrity
    EXIT_CODE=$?
    ;;

  lint-deadcode)
    echo "Checking for potentially unused internal functions (_*)..."
    echo ""
    _check_deadcode
    EXIT_CODE=$?
    ;;

  setup)
    echo "Running setup (symlinks)..."
    if [ -f ./setup.sh ]; then
      ./setup.sh "${@:2}"
      EXIT_CODE=$?
    else
      echo "ERROR: setup.sh not found."
      EXIT_CODE=1
    fi
    ;;

  install)
    echo "Running full installation..."
    if [ -f ./install.sh ]; then
      ./install.sh "${@:2}"
      EXIT_CODE=$?
    else
      echo "ERROR: install.sh not found."
      EXIT_CODE=1
    fi
    ;;

  shell)
    echo "Entering project shell..."
    if command -v uv >/dev/null 2>&1; then
      exec uv run bash
    else
      echo "ERROR: uv not found. Falling back to system bash."
      exec bash
    fi
    ;;

  *)
    cat <<'HELP'
Usage: ./tools/dev.sh <command>

Commands:
  test            Run test suite (tests/test)
  format          Format and lint Python code (tox -e ruff)
  lint            Run linters (ruff, mypy, shellcheck) - excludes markdown
  mdlint          Run markdown linter separately (tox -e mdlint)
  lint-helpfunc   Check help functions are registered in HELP_DESCRIPTIONS
  lint-deadcode   Check for unused internal functions (_*) in shell-common/functions
  setup           Run setup script (symlinks only)
  install         Run full installation
  shell           Enter project shell

Examples:
  ./tools/dev.sh test
  ./tools/dev.sh test -v
  ./tools/dev.sh test -k test_bash
  ./tools/dev.sh format
  ./tools/dev.sh lint
  ./tools/dev.sh mdlint
  ./tools/dev.sh lint-helpfunc
  ./tools/dev.sh lint-deadcode
  ./tools/dev.sh setup
  ./tools/dev.sh install

Environment Variables:
  None required for basic usage.

See AGENTS.md for more details.
HELP
    ;;
esac

# Exit with the captured exit code
exit $EXIT_CODE
