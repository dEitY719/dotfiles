# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

**Setup:**
```bash
./setup.sh              # Link bash config to ~/.bashrc and ~/.bash_profile
./install.sh           # Optional: Setup Claude Code integration and agents
uv pip install -e .[dev]  # Install development dependencies
```

**Code Quality:**
```bash
tox                    # Run all checks (ruff, mypy, shellcheck, shfmt, mdlint)
tox -e ruff           # Format and check Python code
tox -e shellcheck     # Check shell scripts
tox -e shfmt          # Format shell scripts
tox -e mypy           # Type check Python
tox -e mdlint         # Lint markdown files
```

## Project Architecture

This repository contains opinionated Bash dotfiles for reproducible terminal environments. The architecture consists of:

### Core Structure
- **`bash/main.bash`**: Entry point sourced as `~/.bashrc`. Implements initialization guards (skip non-interactive shells, Codex CLI environments, etc.), loads UX library first, then auto-discovers and sources all `.bash` files from subdirectories in priority order (env first, then others).
- **`bash/profile.bash`**: Minimal bash profile configuration linked to `~/.bash_profile`.
- **`bash/ux_lib/`**: Central UX library (`ux_lib.bash`) providing consistent styling, colors, logging, and interactive functions across all bash scripts. Replaces older `beauty_log.bash` and `log_util.bash`.

### Directory Organization
- **`bash/env/`**: Environment variables (PATH, editor, locale, proxy, security). Must load first before other modules.
- **`bash/alias/`**: Organized aliases by category (core, directory, python, system).
- **`bash/app/`**: Application-specific configurations (git, npm, pyenv, postgres, mysql, docker, claude, etc.). Tool integrations for development workflows.
- **`bash/util/`**: Utility helper functions (e.g., `my_man.bash`).
- **`bash/claude/`**: Claude-specific assets for Claude Code integration (statusline command, agent markdown definitions).
- **`bash/config/`**: Non-sourced configuration files only.
- **`bash/coreutils/`**: Generic utilities and helpers.
- **`git/`**: Git configuration and setup script.
- **`mytool/`**: Executable scripts and CLI tools (moved from `bash/scripts/`).

### Auto-Loading Mechanism
`main.bash` prioritizes env directory first, then auto-discovers and loads all other `.bash` files. New subdirectories are automatically included without modifying the loader—just add `.bash` files to any subdirectory and they'll be sourced on shell startup.

### Initialization Guards
`main.bash` includes guards to skip loading in:
- Non-interactive shells (unless `DOTFILES_FORCE_INIT=1`)
- Codex CLI environments (detected via `CODEX_CLI`, `CODEX_MANAGED_BY_NPM`, `CODEX_SANDBOX_NETWORK_DISABLED`)
- When `DOTFILES_SKIP_INIT=1` is set

These guards prevent permission errors, timeouts, and sandbox write failures in sandboxed/non-interactive contexts.

## Key Files and Responsibilities

| File | Purpose |
|------|---------|
| `bash/main.bash` | Initialization, guard logic, module loading, `myhelp` function |
| `bash/env/*.bash` | Environment variables (must load first) |
| `bash/app/*.bash` | Tool integrations (git, npm, docker, etc.) |
| `bash/ux_lib/ux_lib.bash` | Central UX library for colors, logging, formatting |
| `bash/alias/*.bash` | Command aliases and shortcuts |
| `bash/setup.sh` | Symlinks bash config to home directory |
| `git/setup.sh` | Symlinks git config |
| `install.sh` | Optional: Sets up Claude Code assets and agents |
| `pyproject.toml` | Python project metadata and tool configurations |
| `tox.ini` | Automated testing and code quality checks |

## Development Workflow

### Bash Scripts
- Keep scripts POSIX/Bash 4.0+ compatible.
- Use functions over inline scripts. Prefer snake_case naming (e.g., `git_prune`, `mysql_dmc_dev`).
- Always source `ux_lib.bash` at the start of any script requiring UX features.
- Use `shfmt -i 4` formatting (tox -e shfmt will auto-format).
- Fix warnings from `shellcheck` (disable codes like `SC1090`, `SC1091` for shellcheck sourcing issues in tox.ini if needed).

### Python Code
- Follow `ruff` and `mypy` guidance for type hints.
- Use snake_case for files and functions.
- Target Python 3.10+ (per `pyproject.toml`).

### Adding New Help Functions
Automatically discovered in `main.bash`'s `myhelp` command. Just define a function ending with `help` (e.g., `dockerhelp()`, `uxhelp()`), and it will appear in the listing. Add a description in the `help_descriptions` map in `main.bash` for better UX.

### Adding New Modules
1. Create a `.bash` file in the appropriate `bash/` subdirectory (or new subdirectory).
2. If it needs environment variables, place it in `bash/env/`.
3. Otherwise, it will be auto-discovered and sourced by `main.bash`.
4. For interactive setup scripts, ensure they're executable and placed in `mytool/` (not auto-sourced).

## UX Library

All interactive output must use the central UX library (`bash/ux_lib/ux_lib.bash`) for consistency. Key functions:
- `ux_header()`: Section headers (blue)
- `ux_success()`, `ux_error()`, `ux_warning()`, `ux_info()`: Status messages with semantic colors
- `ux_section()`, `ux_bullet()`, `ux_divider()`: Structured formatting
- `ux_table_header()`, `ux_table_row()`: Table output
- Color variables: `UX_PRIMARY`, `UX_SUCCESS`, `UX_ERROR`, `UX_WARNING`, `UX_INFO`, `UX_MUTED`, `UX_RESET`

See `bash/ux_lib/UX_GUIDELINES.md` for detailed examples and best practices.

## Claude Code Integration

### Claude Code Assets
- **Statusline Command**: `bash/claude/statusline-command.sh` — Custom status line display for Claude Code UI.
- **Agent Definitions**: `bash/claude/*.md` — Claude agents for development workflows:
  - `tox-agent.md` — Automates lint and format checks
  - `req-orchestrator-agent.md`, `req-spec-agent.md`, `req-test-design-agent.md`, `req-implementation-agent.md`, `req-summary-agent.md` — REQ-based development workflow (Phase 1–4)
  - `feature-agent.md` — Converts free-form requirements to structured feature definitions

Setup via `./install.sh` creates symlinks in `~/.claude/agents/` and `~/.claude/statusline-command.sh`.

### Environment Guards
Code that writes to `$HOME` (e.g., database configs in `bash/app/`) must check for non-interactive/sandboxed sessions and remain opt-in to avoid sandbox errors.

## Testing

- No formal unit test suite yet; rely on `tox` jobs.
- Add new shell or Python checks to `tests/` and wire into `tox.ini`.
- Interactive helpers should include a non-interactive guard and dry-run path.

## Security & Environment Notes

### Initialization Flags
- `DOTFILES_SKIP_INIT=1` — Skip all sourcing
- `DOTFILES_FORCE_INIT=1` — Force load even in non-interactive shells
- Codex environments (`CODEX_CLI`, etc.) automatically skip to prevent sandbox conflicts

### Home Directory Access
Files that write to `$HOME` (database configs, symlinks, etc.) should gracefully handle non-interactive and sandboxed environments. Use guards like:
```bash
if [[ -z "$DOTFILES_SKIP_INIT" ]] && [[ $- == *i* ]]; then
    # Safe to write to $HOME
fi
```

## Platform Support

- **WSL2** (Windows Subsystem for Linux): Full support with Korean input (fcitx) integration
- **Linux**: Tested on Ubuntu, Debian
- **macOS**: Basic support; some features may need adjustment

## Commit Guidelines

- Messages follow `Type: Summary` format (e.g., `Fix: Prevent dotfiles init in non-interactive environments`, `Refactor: Move executable scripts to mytool`)
- Keep commits focused; explain behavioral changes in the body when non-trivial
- For PRs: describe scope, risks, and verification commands. Link related issues; include terminal output if UI changes.

## Useful References

- **README.md**: Installation, usage examples, troubleshooting
- **AGENTS.md**: Repository guidelines for agents and development
- **bash/ux_lib/UX_GUIDELINES.md**: Detailed UX library usage and best practices
- **bash/README.md**: Bash-specific documentation and function index
