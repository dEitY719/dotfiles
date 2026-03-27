#!/bin/sh
# shell-common/functions/bun_help.sh

# ========================================
# Load UX Library (POSIX portable)
# ========================================
if ! type ux_header >/dev/null 2>&1; then
    _ux_lib_paths="
        ${SHELL_COMMON}/tools/ux_lib/ux_lib.sh
        ${HOME}/.local/dotfiles/shell-common/tools/ux_lib/ux_lib.sh
        $(dirname "$0")/../tools/ux_lib/ux_lib.sh
    "
    for _ux_lib_path in $_ux_lib_paths; do
        if [ -f "$_ux_lib_path" ]; then
            # shellcheck disable=SC1090
            . "$_ux_lib_path"
            break
        fi
    done
    unset _ux_lib_path _ux_lib_paths
fi

bun_help() {
    ux_header "Bun Quick Commands"

    ux_section "Installation"
    ux_table_row "install-bun" "curl .../bun.sh/install" "Install Bun"
    ux_table_row "uninstall-bun" "Remove ~/.bun" "Uninstall Bun"
    ux_table_row "bun-v" "bun --version" "Check version"

    ux_section "Package Management"
    ux_table_row "bun-i" "bun install" "Install deps"
    ux_table_row "bun-id" "install --dev" "Dev dependency"
    ux_table_row "bun-ig" "install --global" "Global install"
    ux_table_row "bun-un" "bun remove" "Remove package"
    ux_table_row "bun-update" "bun update" "Update deps"
    ux_table_row "bun-outdated" "bun outdated" "Check outdated"

    ux_section "Run"
    ux_table_row "bun-run" "bun run <script>" "Run package.json script"
    ux_table_row "bunx" "bun x <pkg>" "Run package without install"

    ux_section "Bunx Usage Examples"
    ux_bullet "${UX_INFO}bunx oh-my-opencode install${UX_RESET}  : OMO 설치"
    ux_bullet "${UX_INFO}bunx create-next-app${UX_RESET}         : Next.js 프로젝트 생성"

    ux_section "Configuration"
    ux_bullet "Config file  : ${UX_INFO}~/.bunfig.toml${UX_RESET} (dotfiles symlink)"
    ux_bullet "Environments : internal (Samsung registry), external (default)"

    ux_section "Troubleshooting"
    ux_bullet "bun not found?   : Run ${UX_PRIMARY}install-bun${UX_RESET}"
    ux_bullet "Registry error?  : Check ${UX_PRIMARY}~/.bunfig.toml${UX_RESET} registry setting"
    ux_bullet "SSL error?       : Verify ${UX_PRIMARY}cafile${UX_RESET} path in bunfig.toml"

    ux_info "Binary path: ~/.bun/bin"
}

alias bun-help='bun_help'
