# Module Context

- **Purpose**: Centralized UX system for consistent terminal output and interaction (POSIX-compliant with bash/zsh support).
- **Components**: Shell library (`ux_lib.sh`), summary-mode step runner (`step_runner.sh`, bash only), Python helpers (`ux_menu.py`, `ux_progress.py`).
- **Reference**: `UX_GUIDELINES.md` is the Single Source of Truth.

# Operational Commands

- **Demo**: `shell-common/tools/custom/demo_ux.sh` (Visual verification).
- **Consistency Check**: `shell-common/tools/custom/check_ux_consistency.sh`.
- **Lint**: `mise run lint-sh` (validates shell code quality).

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

## Step Runner (`step_runner.sh`, #2126)

Shared by `./setup.sh` and `scripts/update-skills.sh` (skills-sync): one line per step,
warnings/failures with detail, full output in a log file. Explicit `source` only —
never auto-sourced, so it has no interactive guard. API and knobs: its header.

```bash
source "${DOTFILES_DIR}/shell-common/tools/ux_lib/step_runner.sh"
STEP_NAME=mytool STEP_RERUN=./mytool.sh STEP_HINT_FN=_my_hint
step_init mytool "$verbose"          # log: ${TMPDIR:-/tmp}/mytool-<ts>.log
step_run "fetch" critical ./fetch.sh  # critical failure -> exit 1
step_run "extras" optional ./extras.sh  # rc kept in STEP_LAST_RC
step_summary mytool
```

Change the runner's output only with `tests/bats/setup/setup_runner.bats` green —
`setup.sh`'s summary output is a byte-level contract (#2126 NF-2).

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
