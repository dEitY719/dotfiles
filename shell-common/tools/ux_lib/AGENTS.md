# Module Context

- **Purpose**: Centralized UX system for consistent terminal output and interaction (POSIX-compliant with bash/zsh support).
- **Components**: Shell library (`ux_lib.sh`), Python helpers (`ux_menu.py`, `ux_progress.py`).
- **Reference**: `UX_GUIDELINES.md` is the Single Source of Truth.

# Operational Commands

- **Demo**: `shell-common/tools/custom/demo_ux.sh` (Visual verification).
- **Consistency Check**: `shell-common/tools/custom/check_ux_consistency.sh`.
- **Lint**: `tox -e shellcheck` (validates shell code quality).

# Implementation Patterns

## Standard Output

```bash
ux_header "Operation Title"
ux_info "Starting process..."
if some_command; then
    ux_success "Done!"
else
    ux_error "Failed!"
fi
```

## User Prompt

```bash
if ux_confirm "Delete database?"; then
    drop_db
fi
```

# Golden Rules

- **No Raw Output**: NEVER use `echo`, `printf`, or `tput` directly in app scripts.
- **No Hardcoded Colors**: Use variables (`${UX_SUCCESS}`, etc.) defined in `ux_lib.sh`.
- **Consistency**: All scripts must look part of the same suite.
- **Accessibility**: Support `NO_COLOR` standard if possible (future proofing).

# Dependencies

- **Python**: `ux_menu.py` and `ux_progress.py` require Python 3.
- **Paths**: Python scripts are resolved relative to `ux_lib.sh` via the `UX_LIB_DIR` variable.
- **Shells**: Supports both bash and zsh (detected via `$BASH_VERSION` and `$ZSH_VERSION`).

# Context Map

- **[UX Guidelines](./UX_GUIDELINES.md)** — detailed design specs.
- **[Parent Context](../AGENTS.md)** — Back to Bash Core.
