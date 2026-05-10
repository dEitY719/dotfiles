# Reference templates by stack. Selection: uv.lock → T1, Django → T2, alembic.ini → T3

> Note: Template T1 hardcodes `DEFAULT_DATASET=./data` and
> `CLI_ENTRY=src/backend/cli/app.py` — see "Known risks" in `SKILL.md`. The
> generator must override these from `tools/AGENTS.md` when present.

## Selection rubric

| Detect | Pick |
| --- | --- |
| `uv.lock` present + FastAPI + no alembic | T1 |
| Django (`manage.py` or `IS_DJANGO=true` in AGENTS.md) | T2 |
| `alembic.ini` present (with or without `uv.lock`) | T3 |

If multiple match, AGENTS.md wins. If nothing matches, fall back to T1 with
empty `UVICORN_ENTRY` and let the `up` command emit an actionable error
(see `references/error-handling.md`).

## Template 1: FastAPI with uv

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

## Template 2: Django with Poetry

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

## Template 3: FastAPI with Alembic

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
