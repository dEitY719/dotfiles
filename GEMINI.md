# GEMINI.md - Context & Guide

## Project Overview
**Name:** Dotfiles
**Purpose:** Opinionated Bash dotfiles for reproducible terminal environments (WSL, Linux, macOS).
**Goal:** Provide a modular, high-quality shell environment with consistent UX, integrated developer tools, and automated testing.

## Architecture & Directory Structure
The project uses a modular approach where `bash/main.bash` dynamically loads configurations.

- **`bash/`**: Core Bash configurations.
    - **`main.bash`**: Entry point. Logic for loading modules and handling environment guards.
    - **`env/`**: Environment variables (`PATH`, `EDITOR`, `LOCALE`, etc.). Loaded first.
    - **`ux_lib/`**: Shared UX library for logging (`ux_info`, `ux_error`), progress bars (`ux_spinner`), and interactivity (`ux_menu`).
    - **`alias/`**: Command aliases (`core_aliases.bash`, `git.bash`, etc.).
    - **`app/`**: Tool integrations (Git, Python/Pyenv, Node/NPM, Docker, databases).
    - **`util/`**: General utility functions.
    - **`claude/`**: Claude-specific agents and configurations.
- **`mytool/`**: Custom CLI tools (Python-based).
    - **`srcpack.py`**: Tool to pack source code into a single file for LLM context.
- **`git/`**: Git configuration files.
- **`tests/`**: Test suite (Python and Shell).
- **`config/`**: Miscellaneous configs (e.g., `pg_services.list`).

## Installation & Setup
- **Basic Setup:** `./setup.sh`
    - Symlinks `bash/main.bash` -> `~/.bashrc`
    - Symlinks `bash/profile.bash` -> `~/.bash_profile`
    - Symlinks `git/.gitconfig` -> `~/.gitconfig`
- **Extended Setup:** `./install.sh`
    - Installs Claude/Codex agents and status line scripts to `~/.claude/`.
    - Configures PostgreSQL services.
- **Python Dependencies:**
    - Install dev dependencies: `uv pip install -e .[dev]` (or `pip`)

## Development Workflow

### Testing & Quality Assurance
This project uses `tox` to orchestrate all checks.
- **Run All Checks:** `tox`
- **Python Linting (Ruff):** `tox -e ruff` (autofixes with `--fix` in `tox.ini` logic usually, or run `ruff check . --fix` manually).
- **Python Type Checking:** `tox -e mypy`
- **Shell Script Linting:** `tox -e shellcheck`
- **Shell Script Formatting:** `tox -e shfmt`
- **Markdown Linting:** `tox -e mdlint`

### Key Tools
- **`myhelp`**: Run this in the shell to see a dynamic list of available help commands (e.g., `githelp`, `dockerhelp`).
- **`srcpack`**: Located in `mytool/srcpack.py`. Use it to consolidate code for analysis.
    - Example: `python3 mytool/srcpack.py . --output context.txt`
- **Environment Guards:**
    - `DOTFILES_SKIP_INIT=1`: Skip loading dotfiles.
    - `DOTFILES_FORCE_INIT=1`: Force loading even in non-interactive shells.

## Coding Conventions
- **Bash:**
    - Modularize code into `bash/app/` or `bash/alias/` instead of monolithic files.
    - Use `ux_lib` functions (`ux_header`, `ux_success`) for output.
    - Prefer functions over aliases for complex logic.
    - Use snake_case for function names.
- **Python:**
    - Follow `ruff` and `mypy` strict standards.
    - Use type hints.
- **Commits:**
    - Semantic style: `Type: Summary` (e.g., `Feat: Add new docker alias`, `Fix: Resolve path issue in WSL`).
