# Project Context
- **Objective**: Opinionated Bash dotfiles for reproducible terminal environments (WSL, Linux, macOS).
- **Stack**: Bash 5.x+, Python 3.10+, Tox, Ruff, Mypy.
- **Structure**: Modular Bash (`bash/`), Python tools (`mytool/`), Tests (`tests/`), Docs (`docs/`).

# Operational Commands
- **Setup**: `./setup.sh` (Symlinks), `./install.sh` (Full install).
- **Linting (All)**: `tox` (Runs ruff, mypy, mdlint, shellcheck, shfmt).
- **Linting (Python)**: `tox -e ruff` (fixes), `tox -e mypy`.
- **Linting (Bash)**: `tox -e shellcheck`, `tox -e shfmt` (formats).
- **Testing**: `pytest` (if tests exist), manual validation via `mytool/demo_ux.sh`.
- **Docs**: `tox -e mdlint`.

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
- **DON'T**: Use raw `echo` or `printf` (violates UX consistency).
- **DON'T**: Hardcode paths; use `$HOME` or relative paths.
- **DON'T**: Commit secrets or sensitive data.

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
- **[UX Library](./shell-common/tools/ux_lib/AGENTS.md)** — Styling, logging, interactive components
- **[Documentation](./docs/AGENTS.md)** — Project docs, AGENTS.md master prompt, SOLID reviews

# Postmortem: Auto-Sourcing Utility Scripts (2025-12-29)

## Issue

After refactoring docker.bash to shell-common/tools/external/, shell initialization began auto-sourcing all files from shell-common/tools/custom/. This caused:

- **zsh to hang** with no prompt displayed
- **Endless interactive menu loops** (demo_ux.sh, check_ux_consistency.sh running on startup)
- **Shell initialization blocking** waiting for user input

## Root Cause

shell-common/tools/custom/ contains **executable utility scripts** (not sourced libraries):

- demo_ux.sh: Interactive UX library demo
- check_ux_consistency.sh: Consistency checker
- All install-*.sh: Installation scripts
- All setup-*.sh: Configuration scripts

These scripts have:

```bash
main() { ... }  # Interactive function
main            # Called at END OF FILE
```

When sourced at shell init, the `main()` call executes immediately, blocking the shell.

## Solution (Commit 9ce6b82)

Removed auto-sourcing of shell-common/tools/custom/ from:

- bash/main.bash (line 160-163): Changed to comment explaining purpose
- ~/.zshrc (line 117-121): Changed to comment explaining purpose

These scripts are **meant to be executed explicitly** as commands:

```bash
./install_docker.sh    # Direct execution
dinstall               # Via function wrapper in docker.sh
```

NOT sourced during shell init.

## Lesson Learned: Separate Concerns

- **Library Code** (ux_lib, functions): Source at init
- **Executable Scripts** (installs, demos): Don't source at init
- **Directory Purpose**: Naming matters
  - shell-common/tools/external/ → Sourced at init (apt.sh, docker.sh)
  - shell-common/tools/custom/ → Executable utilities only
  - shell-common/functions/ → Sourced at init (functions)

## Prevention

When adding scripts to shell-common/tools/custom/:

1. Ensure main() is NOT called automatically
2. Define functions only, don't execute at end of file
3. If execution is needed, create a wrapper function in tools/external/
4. Never auto-source from custom/ in shell init files
