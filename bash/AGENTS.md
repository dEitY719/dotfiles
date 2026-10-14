# Module Context
- **Purpose**: Core Bash configuration hub. Manages environment, aliases, and shared utilities.
- **Entry Point**: `main.bash` — 얇은 진입점. 로딩 코어는 `shell-common/util/bootstrap.sh` + `loader.sh` 의 `dotfiles_load_all` (#2134, zsh 와 공유).
- **Loading order**: zsh 가드 → ROOT 후보(realpath) → MERGE_HEAD 진단 → `bootstrap.sh`(skip 가드·정규화·ux_lib) → `dotfiles_load_all`(env → aliases → functions → integrations → adapter → projects) → `bash/env/*.bash`(공통값 override 용으로 공통 로드 **뒤**) → summary → fzf/fasd → setup_mode → `~/.bashrc.local`.
- **Startup merge guard (#2078)**: `main.bash` 상단에 인라인 `.git/MERGE_HEAD` 진단(대화형 한정)이 있다. 미완 `git sync` 머지를 알리는 용도라 파일 소싱 없이 `printf` 만 쓴다 — bootstrap 으로 옮기지 않는다.
- **Structure**:
    - `bash/env/`: Bash-specific environment (`*.bash` only — `main.bash` globs `env/*.bash`)
    - `shell-common/env/`: Shared environment (PATH, LOCALE, etc.)
    - `shell-common/aliases/`: Shared command shortcuts
    - `shell-common/functions/`: Shared functions and help systems
    - `shell-common/tools/`: UX library and external integrations
    - `shell-common/projects/`: Project-specific utilities (finrx, dmc, smithery)

# Operational Commands
- **Lint**: `mise run lint-sh` (shellcheck + shfmt diff for `bash/`).
- **Format**: `mise run fix-sh` (Standardize style, `shfmt -w`).
- **Reload**: `source ~/.bashrc` (Apply changes).

# Implementation Patterns

## File Loading
```bash
# In main.bash: shared modules — one call, every file goes through safe_source
dotfiles_load_all

# Loading bash-specific modules
for f in "${DOTFILES_BASH_DIR}/env/"*.bash; do
    safe_source "$f" "Environment variable file not found"
done
```

## Interactive Guard
```bash
# Top of every file if it produces output or binds keys (same form as root AGENTS.md)
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
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
- **Syntax**: `shellcheck` via `mise run lint-sh`.
- **Format**: `shfmt` via `mise run fix-sh`.
- **Manual**: Use `source bash/main.bash` in a clean shell to verify loading.

# Context Map
- **[Shared Configuration](../shell-common/README.md)** — Shared aliases, functions, tools, projects.
- **[UX Library](../shell-common/tools/ux_lib/)** — UI components, logging, progress bars.
- **[Bash Configuration](./README.md)** — Detailed bash module documentation.
- **[Main Entry Point](./main.bash)** — Module loading orchestration.
