# Module Context
- **Purpose**: Core Bash configuration hub. Manages environment, aliases, and applications.
- **Entry Point**: `main.bash` (Sources all other modules).
- **Structure**:
    - `env/`: Environment variables (PATH, LOCALE). Loaded FIRST.
    - `ux_lib/`: User Experience library. Loaded SECOND.
    - `alias/`: Command shortcuts. Loaded THIRD.
    - `app/`: Application integrations. Loaded LAST.
    - `util/`: Helper functions.

# Operational Commands
- **Lint**: `tox -e shellcheck` (Validate syntax).
- **Format**: `tox -e shfmt` (Standardize style).
- **Reload**: `source ~/.bashrc` (Apply changes).

# Implementation Patterns

## File Loading
```bash
# In main.bash or submodule loaders
for file in "$DOTFILES_DIR/bash/app/"*.bash; do
    [ -r "$file" ] && source "$file"
done
```

## Interactive Guard
```bash
# Top of every file if it produces output or binds keys
[[ $- == *i* ]] || return 0
```

# Golden Rules
- **Naming**: Use `snake_case.bash`.
- **Output**: ONLY use `ux_lib` functions. No `echo`.
- **Idempotency**: Scripts must be safe to source multiple times.
- **Performance**: Lazy load heavy integrations (e.g., `nvm`, `pyenv`) if possible.
- **Guards**: Respect `DOTFILES_SKIP_INIT` and `DOTFILES_FORCE_INIT`.

# Testing Strategy
- **Syntax**: `shellcheck` via `tox`.
- **Format**: `shfmt` via `tox`.
- **Manual**: Use `source bash/main.bash` in a clean shell to verify loading.

# Context Map
- **[Apps & Integrations](./app/AGENTS.md)** — Git, Docker, Postgres, Python configs.
- **[UX Library](./ux_lib/AGENTS.md)** — UI components, logging, progress bars.
- **[Environment](./env/AGENTS.md)** — PATH, Editor, Proxy, Security settings.
- **[Aliases](./alias/AGENTS.md)** — Git shortcuts, directory navigation.
