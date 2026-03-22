#!/bin/sh
# shell-common/functions/uv_help.sh

uv_help() {
    ux_header "UV Quick Commands"

    ux_section "Sync & Install"
    ux_table_row "uvs" "uv sync" "Sync env & prune (Prod)"
    ux_table_row "uvu" "uv sync --upgrade" "Upgrade deps"
    ux_table_row "uvd" "uv sync --dev" "Dev install"
    ux_table_row "uv-install" "install script" "Install UV tool"

    ux_section "Lock & Export"
    ux_table_row "uvk" "uv lock" "Refresh lockfile"
    ux_table_row "uvl" "uv pip list" "List packages"
    ux_table_row "uvc" "uv pip compile" "Export requirements"
    ux_table_row "uvr" "uv pip sync" "Sync from reqs"

    ux_section "Maintenance"
    ux_table_row "uvcheck" "uv pip check" "Verify env"

    ux_section "Recipes"
    ux_bullet "Install all extras: ${UX_SUCCESS}uv pip sync --all-extras${UX_RESET}"
    ux_bullet "Backend dev:      ${UX_SUCCESS}uv pip sync --extra backend --extra dev${UX_RESET}"
    ux_bullet "Frontend dev:     ${UX_SUCCESS}uv pip sync --extra frontend --extra dev${UX_RESET}"
}

# UV Check Wrapper - calls the diagnostic script
uv_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_uv.sh" "$@"
}

alias uv-help='uv_help'
alias check-uv='uv_check'
