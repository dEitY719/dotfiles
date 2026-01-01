# Module Context
- **Purpose**: Core Bash configuration hub. Manages environment, aliases, and shared utilities.
- **Entry Point**: `main.bash` (Sources all modules including shell-common/).
- **Structure**:
    - `bash/env/`: Bash-specific environment variables
    - `bash/util/`: Bash-specific utilities
    - `shell-common/env/`: Shared environment (PATH, LOCALE, etc.)
    - `shell-common/aliases/`: Shared command shortcuts
    - `shell-common/functions/`: Shared functions and help systems
    - `shell-common/tools/`: UX library and external integrations
    - `shell-common/projects/`: Project-specific utilities (finrx, dmc, smithery)

# Operational Commands
- **Lint**: `tox -e shellcheck` (Validate syntax).
- **Format**: `tox -e shfmt` (Standardize style).
- **Reload**: `source ~/.bashrc` (Apply changes).

# Implementation Patterns

## File Loading
```bash
# In main.bash: Loading shared modules
for file in "${SHELL_COMMON}/aliases/"*.sh; do
    [ -r "$file" ] && safe_source "$file" "Failed to load alias"
done

# Loading bash-specific modules
for file in "${DOTFILES_BASH_DIR}/env/"*.sh; do
    [ -r "$file" ] && safe_source "$file" "Failed to load bash env"
done
```

## Interactive Guard
```bash
# Top of every file if it produces output or binds keys
[[ $- == *i* ]] || return 0
```

# Golden Rules
- **Naming**:
  - Shared files: `snake_case.sh` (in `shell-common/`)
  - Bash-only files: `snake_case.sh` or `.bash` (in `bash/`)
- **Location**:
  - POSIX-compatible code → `shell-common/`
  - Bash-specific code → `bash/`
- **Output**: ONLY use `ux_lib` functions. No direct `echo`.
- **Idempotency**: Scripts must be safe to source multiple times.
- **Performance**: Lazy load heavy integrations (e.g., `nvm`, `pyenv`) if possible.
- **Guards**: Respect `DOTFILES_SKIP_INIT` and `DOTFILES_FORCE_INIT`.
- **POSIX Compatibility**: Shared files must use POSIX syntax (`>/dev/null 2>&1`, not `&>/dev/null`).

# Testing Strategy
- **Syntax**: `shellcheck` via `tox`.
- **Format**: `shfmt` via `tox`.
- **Manual**: Use `source bash/main.bash` in a clean shell to verify loading.

# Context Map
- **[Shared Configuration](../shell-common/README.md)** — Shared aliases, functions, tools, projects.
- **[UX Library](../shell-common/tools/ux_lib/)** — UI components, logging, progress bars.
- **[Bash Configuration](./README.md)** — Detailed bash module documentation.
- **[Main Entry Point](./main.bash)** — Module loading orchestration.
