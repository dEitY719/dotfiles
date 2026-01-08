# Project Context

- **Objective**: Opinionated Bash dotfiles for reproducible terminal environments (WSL, Linux, macOS).
- **Stack**: Bash 5.x+, Python 3.10+, Tox, Ruff, Mypy.
- **Structure**: Modular Bash (`bash/`), Python tools (`mytool/`), Tests (`tests/`), Docs (`docs/`).

# Operational Commands

- **Setup**: `./setup.sh` (Symlinks), `./install.sh` (Full install).
- **Linting (All)**: `tox` (Runs ruff, mypy, shellcheck, shfmt).
- **Linting (Python)**: `tox -e ruff` (fixes), `tox -e mypy`.
- **Linting (Bash)**: `tox -e shellcheck`, `tox -e shfmt` (formats).
- **Testing**: `pytest` (if tests exist), manual validation via `mytool/demo_ux.sh`.

# Golden Rules

## Immutable Constraints

- **500-Line Limit**: Every AGENTS.md file must be under 500 lines.
- **No Emojis**: Strictly prohibited to save tokens.
- **Interactive Guards**: Bash files must guard execution: `[[ $- == *i* ]]`.
- **Loading Order**: Respect `bash/main.bash` priority (Env -> UX -> Alias -> App).
- **No Direct Writes**: Do not write to `~/.bashrc` directly; use symlinks via `setup.sh`.

## Do's & Don'ts

- **DO**: Use snake_case for all Bash functions and filenames.
- **DO**: Use `ux_lib` functions (`ux_header`, `ux_success`) for ALL output.
- **DO**: Run `tox` before committing.
- **DO**: Use environment variables (e.g., `$SHELL_COMMON`) or absolute paths when sourcing files across shell contexts.
- **DO**: Test scripts in both bash and zsh for cross-shell compatibility.
- **DO**: Place shell functions in `shell-common/functions/` (auto-sourced by main.bash/main.zsh).
- **DO**: Place executable utility scripts in `shell-common/tools/custom/` (run explicitly, not sourced).
- **DON'T**: Use raw `echo` or `printf` (violates UX consistency).
- **DON'T**: Hardcode paths; use `$HOME` or relative paths.
- **DON'T**: Commit secrets or sensitive data.
- **DON'T**: Use bash-specific variables (e.g., `${BASH_SOURCE[0]}`) without fallback; this breaks zsh compatibility.
- **DON'T**: Place functions in `shell-common/tools/custom/` (won't be auto-sourced; breaks initialization).

## shell-common Directory Structure Guide

**CRITICAL**: Correct directory placement prevents "function not found" and "command not found" errors.

### shell-common/functions/ - AUTO-SOURCED FUNCTIONS
Loaded automatically by `main.bash` and `main.zsh` during shell initialization.

**Use this for:**
- Commands that users call from the terminal (e.g., `devx help`, `git-help`)
- Functions that need to be available in the shell immediately
- Wrapper functions around commands
- Helper functions needed by other functions or aliases

**Examples:**
- `devx.sh` - Provides `devx` command dispatcher
- `git_help.sh` - Provides `git_help()` function (callable as alias `git-help`)
- `docker_help.sh` - Provides `docker_help()` function
- `my_man.sh` - Provides custom man page function
- `my_help.sh` - Provides `my_help()` shell command

**Pattern**: `shell-common/functions/COMMAND_help.sh` or `shell-common/functions/COMMAND.sh`

### shell-common/tools/custom/ - EXECUTABLE UTILITY SCRIPTS
Run explicitly as scripts, NOT auto-sourced. Used for development tools, CLI utilities, analysis scripts.

**Use this for:**
- Command-line utilities meant to be executed directly
- Standalone scripts that should NOT be sourced
- Tools called by Makefile, tox, or other scripts
- Development/debugging utilities

**Examples:**
- `check_ux_consistency.sh` - Run: `./shell-common/tools/custom/check_ux_consistency.sh`
- `analyze_bash_scripts.sh` - Run: `./shell-common/tools/custom/analyze_bash_scripts.sh`
- `demo_ux.sh` - Run: `./shell-common/tools/custom/demo_ux.sh`
- `mount.sh` - Utility script for mounting operations

**Pattern**: `shell-common/tools/custom/TOOL_NAME.sh` (has shebang, executable, never sourced)

### shell-common/tools/external/ - THIRD-PARTY TOOL WRAPPERS
Auto-sourced. Thin wrappers around system tools or external packages.

**Use this for:**
- Wrapper functions for external CLIs (npm, pip, etc.)
- System tool integrations
- Package manager abstraction

**Examples:**
- `npm.sh` - npm wrapper
- `apt.sh` - apt package manager integration
- `ccusage.sh` - External tool wrapper

### Decision Tree

```
Creating a new .sh file? Ask yourself:

1. Will users call this as a command? (e.g., `devx help`, `my-tool`)
   YES -> shell-common/functions/
   NO  -> Next question

2. Is this a standalone utility script to be run explicitly?
   YES -> shell-common/tools/custom/
   NO  -> Next question

3. Is this a wrapper for an external tool?
   YES -> shell-common/tools/external/
   NO  -> Contact maintainers (may belong in bash/, zsh/, or projects/)
```

### Common Mistakes & Fixes

**ERROR**: Function placed in `tools/custom/` not available after shell restart
```
# WRONG
mv shell-common/functions/devx.sh shell-common/tools/custom/devx.sh
# Result: devx: command not found (not auto-sourced)

# RIGHT
# Keep it in shell-common/functions/devx.sh (auto-sourced at startup)
```

**ERROR**: Utility script accidentally sourced by main.bash
```
# WRONG: Sourcing a utility script
source shell-common/tools/custom/check_ux_consistency.sh
# Result: Global pollution, side effects, broken behavior

# RIGHT: Execute directly when needed
./shell-common/tools/custom/check_ux_consistency.sh
# Or call from Makefile/tox
```

## Bash/Zsh Compatibility Rules

This project supports both bash and zsh. Ensure cross-shell compatibility:

- **Forbidden**: `source "${BASH_SOURCE[0]%/*}/file.sh"` (bash-only, fails in zsh)
- **Required**: Use environment variables: `source "${SHELL_COMMON}/tools/custom/file.sh"`
- **Acceptable**: Use positional parameter: `source "$(dirname "$0")/file.sh"` (works in direct execution)
- **For sourced scripts**: Always prefer pre-defined variables like `$SHELL_COMMON`, `$DOTFILES_ROOT`
- **Test command**: Verify in both: `bash -i -c 'function_name'` and `zsh -c 'source main.zsh && function_name'`

# SOLID & Design Principles

- **SRP**: Each Bash file manages ONE domain (e.g., `docker.bash` only for Docker).
- **OCP**: Extend behavior via new files in `bash/app/`, don't clutter `main.bash`.
- **DRY**: Replicate logic? Move to `bash/util/` or `bash/ux_lib/`.
- **DIP**: Scripts should depend on `ux_lib` abstractions, not raw colors.

# TDD Protocol

1. **Analyze**: Understand the feature or bug.
2. **Test**: Write a test case (Python `pytest` or manual `demo_ux.sh` scenario).
3. **Implement**: Write minimal Bash/Python code.
4. **Refactor**: Optimize while keeping tests green.
5. **Verify**: Run `tox` to ensure style compliance.

# Standards & References

- **Coding Style**: See `bash/ux_lib/UX_GUIDELINES.md` and `tox.ini`.
- **Git Strategy**: Semantic commits (`Type: Summary`).
- **Maintenance**: Update AGENTS.md when adding new modules.

# Context Map

- **[Bash Module](./bash/AGENTS.md)** — Bash-specific configuration and utilities
- **[Zsh Module](./zsh/AGENTS.md)** — Zsh-specific configuration and applications
- **[Shell Common](./shell-common/AGENTS.md)** — POSIX-compatible shared utilities (env, aliases, functions, tools, projects)
- **[Claude Code](./claude/AGENTS.md)** — Claude Code configuration, settings, skills, and automation
- **[UX Library](./shell-common/tools/ux_lib/AGENTS.md)** — Styling, logging, interactive components
- **[Documentation](./docs/AGENTS.md)** — Project docs, AGENTS.md master prompt, SOLID reviews

# Naming Rules (Bash/Zsh)

- **File names**: snake_case with `.sh` (e.g., `git_help.sh`, `install_docker.sh`, `git_crypt.sh`).
- **Function names**: snake_case (e.g., `git_help`, `install_docker`, `git_crypt_install`).
- **Aliases**: dash-form for user commands, mapped from snake_case functions (e.g., `alias git-help='git_help'`, `alias install-docker='install_docker'`).

# Naming Rules (Docs)

- **Markdown files**: dash-form (e.g., `setup-guide.md`, `ux-library-notes.md`); avoid camelCase or snake_case in filenames.
