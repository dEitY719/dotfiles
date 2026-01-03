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

# Naming Rules (Bash/Zsh)

- **File names**: snake_case with `.sh` (e.g., `git_help.sh`, `install_docker.sh`, `git_crypt.sh`).
- **Function names**: snake_case (e.g., `git_help`, `install_docker`, `git_crypt_install`).
- **Aliases**: dash-form for user commands, mapped from snake_case functions (e.g., `alias git-help='git_help'`, `alias install-docker='install_docker'`).

# Naming Rules (Docs)

- **Markdown files**: dash-form (e.g., `setup-guide.md`, `ux-library-notes.md`); avoid camelCase or snake_case in filenames.
