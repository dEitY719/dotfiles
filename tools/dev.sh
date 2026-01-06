#!/usr/bin/env bash
set -euo pipefail

# Configuration (dotfiles project - bash configuration management)
PY_RUN="uv run"
PY_TEST="uv run pytest"

cmd="${1:-help}"

case "$cmd" in
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

  lint)
    echo "Running linters excluding markdown (ruff, mypy, shellcheck, shfmt)..."
    if command -v tox >/dev/null 2>&1; then
      tox -e ruff,mypy,shellcheck,shfmt
    else
      echo "ERROR: tox not found. Install: uv pip install tox"
      exit 1
    fi
    ;;

  mdlint)
    echo "Running markdown linter (tox -e mdlint)..."
    if command -v tox >/dev/null 2>&1; then
      tox -e mdlint "${@:2}"
    else
      echo "ERROR: tox not found. Install: uv pip install tox"
      exit 1
    fi
    ;;

  setup)
    echo "Running setup (symlinks)..."
    if [ -f ./setup.sh ]; then
      ./setup.sh "${@:2}"
    else
      echo "ERROR: setup.sh not found."
      exit 1
    fi
    ;;

  install)
    echo "Running full installation..."
    if [ -f ./install.sh ]; then
      ./install.sh "${@:2}"
    else
      echo "ERROR: install.sh not found."
      exit 1
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
  test         Run test suite (pytest)
  format       Format and lint Python code (tox -e ruff)
  lint         Run linters (ruff, mypy, shellcheck) - excludes markdown
  mdlint       Run markdown linter separately (tox -e mdlint)
  setup        Run setup script (symlinks only)
  install      Run full installation
  shell        Enter project shell

Examples:
  ./tools/dev.sh test
  ./tools/dev.sh test -v
  ./tools/dev.sh test -k test_bash
  ./tools/dev.sh format
  ./tools/dev.sh lint
  ./tools/dev.sh mdlint
  ./tools/dev.sh setup
  ./tools/dev.sh install

Environment Variables:
  None required for basic usage.

See AGENTS.md for more details.
HELP
    ;;
esac
