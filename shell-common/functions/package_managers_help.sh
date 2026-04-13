#!/bin/sh
# shell-common/functions/package_managers_help.sh
# Bundle: package manager check wrappers and help functions

# --- apt_check (from apt_help.sh) ---

# APT Check Wrapper - calls the diagnostic script
apt_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_apt.sh" "$@"
}

alias check-apt='apt_check'

# --- cargo_check (from cargo_help.sh) ---

# Cargo Check Wrapper - calls the diagnostic script
cargo_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_cargo.sh" "$@"
}

alias check-cargo='cargo_check'

# --- nuget_check (from nuget_help.sh) ---

# NuGet Check Wrapper - calls the diagnostic script
nuget_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_nuget.sh" "$@"
}

alias check-nuget='nuget_check'

# --- rpm_check (from rpm_help.sh) ---

# RPM Check Wrapper - calls the diagnostic script
rpm_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_rpm.sh" "$@"
}

alias check-rpm='rpm_check'

# --- pip_help (from pip_help.sh) ---

_pip_help_summary() {
    ux_info "Usage: pip-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "diagnostics: check-pip | config | file | repo | env"
    ux_bullet_sub "commands: pip config list | --verbose | view conf | --version"
    ux_bullet_sub "setup: ./setup.sh (Public | Internal | External)"
    ux_bullet_sub "repos: Proxy | Internal Repo | DataService Repo"
    ux_bullet_sub "notes: CA cert | setup.sh managed | symlink"
    ux_bullet_sub "details: pip-help <section>  (example: pip-help repos)"
}

_pip_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "diagnostics"
    ux_bullet_sub "commands"
    ux_bullet_sub "setup"
    ux_bullet_sub "repos"
    ux_bullet_sub "notes"
}

_pip_help_rows_diagnostics() {
    ux_bullet "check-pip            Run full pip diagnostic"
    ux_bullet "check-pip config     Show pip configuration"
    ux_bullet "check-pip file       pip.conf file check"
    ux_bullet "check-pip repo       Repository connectivity test"
    ux_bullet "check-pip env        Environment variables"
}

_pip_help_rows_commands() {
    ux_bullet "pip config list                 Show all pip settings"
    ux_bullet "pip config list --verbose       Show pip config files loading"
    ux_bullet "cat \$HOME/.config/pip/pip.conf  View user pip config"
    ux_bullet "pip --version                   Check pip version"
}

_pip_help_rows_setup() {
    ux_bullet "./setup.sh                      Run setup (choose environment)"
    ux_bullet "               1) Public PC"
    ux_bullet "               2) Internal company PC (proxy + internal repo)"
    ux_bullet "               3) External company PC (VPN)"
}

_pip_help_rows_repos() {
    ux_bullet "Proxy:            http://12.26.204.100:8080"
    ux_bullet "Internal Repo:    http://repository.samsungds.net/repository/proxy-pypi-files.pythonhosted.org/simple"
    ux_bullet "DataService Repo: http://nexus.adpaas.cloud.samsungds.net/repository/dataservice-pypi/simple"
}

_pip_help_rows_notes() {
    ux_warning "CA certificate: Configured via security.local.sh (REQUESTS_CA_BUNDLE)"
    ux_info "Config files are managed by setup.sh - do not edit manually"
    ux_info "Symlink: ~/.config/pip/pip.conf -> pip/pip.conf.{environment}"
}

_pip_help_render_section() {
    ux_section "$1"
    "$2"
}

_pip_help_section_rows() {
    case "$1" in
        diagnostics|diag)
            _pip_help_rows_diagnostics
            ;;
        commands|quick)
            _pip_help_rows_commands
            ;;
        setup|env|environment)
            _pip_help_rows_setup
            ;;
        repos|proxy|repo)
            _pip_help_rows_repos
            ;;
        notes|important)
            _pip_help_rows_notes
            ;;
        *)
            ux_error "Unknown pip-help section: $1"
            ux_info "Try: pip-help --list"
            return 1
            ;;
    esac
}

_pip_help_full() {
    ux_header "Pip Configuration & Diagnostics"

    _pip_help_render_section "Diagnostic Commands" _pip_help_rows_diagnostics
    _pip_help_render_section "Quick Commands" _pip_help_rows_commands
    _pip_help_render_section "Environment Setup" _pip_help_rows_setup
    _pip_help_render_section "Proxy & Repository Info" _pip_help_rows_repos
    _pip_help_render_section "Important Notes" _pip_help_rows_notes
}

pip_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _pip_help_summary
            ;;
        --list|list)
            _pip_help_list_sections
            ;;
        --all|all)
            _pip_help_full
            ;;
        *)
            _pip_help_section_rows "$1"
            ;;
    esac
}

# Wrapper function for check_pip.sh diagnostic
pip_check() {
    local check_pip_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_pip.sh"
    if [ -f "$check_pip_script" ]; then
        bash "$check_pip_script" "$@"
    else
        if type ux_error >/dev/null 2>&1; then
            ux_error "check_pip.sh not found at $check_pip_script"
        else
            echo "ERROR: check_pip.sh not found at $check_pip_script" >&2
        fi
        return 1
    fi
}

alias pip-help='pip_help'
alias check-pip='pip_check'

# --- npm_help (from npm_help.sh) ---

# NOTE: UX library is loaded by the loader before functions/ — no need to reload here

_npm_help_summary() {
    ux_info "Usage: npm-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "info: npm-v | npm-list | npm-info | npm-search | npm-outdated"
    ux_bullet_sub "install: npm-i | npm-is | npm-isd | npm-ig"
    ux_bullet_sub "uninstall: npm-un | npm-ung"
    ux_bullet_sub "maintenance: npm-update | npm-cache-clean"
    ux_bullet_sub "config: npm-config"
    ux_bullet_sub "setup: npminstall | npmuninstall"
    ux_bullet_sub "cert: crt-help | crtsetup"
    ux_bullet_sub "troubleshoot: EACCES | nvm conflict | certificate | config mismatch"
    ux_bullet_sub "details: npm-help <section>  (example: npm-help install)"
}

_npm_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "info"
    ux_bullet_sub "install"
    ux_bullet_sub "uninstall"
    ux_bullet_sub "maintenance"
    ux_bullet_sub "config"
    ux_bullet_sub "setup"
    ux_bullet_sub "cert"
    ux_bullet_sub "troubleshoot"
}

_npm_help_rows_info() {
    ux_table_row "npm-v" "npm --version" "Check version"
    ux_table_row "npm-list" "list -g --depth=0" "Global packages"
    ux_table_row "npm-info" "info <pkg>" "Package details"
    ux_table_row "npm-search" "search <keyword>" "Search packages"
    ux_table_row "npm-outdated" "outdated -g" "Check updates"
}

_npm_help_rows_install() {
    ux_table_row "npm-i" "npm install" "Install deps"
    ux_table_row "npm-is" "install --save" "Save prod dep"
    ux_table_row "npm-isd" "install --save-dev" "Save dev dep"
    ux_table_row "npm-ig" "install -g" "Global install"
}

_npm_help_rows_uninstall() {
    ux_table_row "npm-un" "npm uninstall" "Remove dep"
    ux_table_row "npm-ung" "uninstall -g" "Remove global"
}

_npm_help_rows_maintenance() {
    ux_table_row "npm-update" "update -g" "Update global"
    ux_table_row "npm-cache-clean" "cache clean --force" "Clear cache"
}

_npm_help_rows_config() {
    ux_table_row "npm-config" "Show current config" "Registry, CA, SSL"
}

_npm_help_rows_setup() {
    ux_table_row "npminstall" "Install Script" "Install Node/NPM"
    ux_table_row "npmuninstall" "Uninstall Script" "Remove Node/NPM"
}

_npm_help_rows_cert() {
    ux_info "For CA certificate setup (company proxy/internal network):"
    ux_bullet "Run: ${UX_SUCCESS}crt-help${UX_RESET} for detailed guide"
    ux_bullet "Setup: ${UX_SUCCESS}crtsetup${UX_RESET} to install certificate"
}

_npm_help_rows_troubleshoot() {
    ux_bullet "EACCES permission error (npm WARN): npm config set prefix ~/.npm-global"
    ux_bullet "nvm과 npm prefix 충돌: .npmrc 파일의 prefix 라인 제거"
    ux_bullet "Certificate error: Run ${UX_SUCCESS}crt-help${UX_RESET} for CA setup guide"
    ux_bullet "Config mismatch: Run ${UX_SUCCESS}./shell-common/setup.sh${UX_RESET} to reconfigure symlink"
    ux_info "Global Path: ~/.npm-global"
}

_npm_help_render_section() {
    ux_section "$1"
    "$2"
}

_npm_help_section_rows() {
    case "$1" in
        info|version)
            _npm_help_rows_info
            ;;
        install|i)
            _npm_help_rows_install
            ;;
        uninstall|un)
            _npm_help_rows_uninstall
            ;;
        maintenance|update)
            _npm_help_rows_maintenance
            ;;
        config|configuration)
            _npm_help_rows_config
            ;;
        setup|tools)
            _npm_help_rows_setup
            ;;
        cert|certificate|ca)
            _npm_help_rows_cert
            ;;
        troubleshoot|troubleshooting)
            _npm_help_rows_troubleshoot
            ;;
        *)
            ux_error "Unknown npm-help section: $1"
            ux_info "Try: npm-help --list"
            return 1
            ;;
    esac
}

_npm_help_full() {
    ux_header "NPM Quick Commands"

    _npm_help_render_section "Info & Version" _npm_help_rows_info
    _npm_help_render_section "Install" _npm_help_rows_install
    _npm_help_render_section "Uninstall" _npm_help_rows_uninstall
    _npm_help_render_section "Maintenance" _npm_help_rows_maintenance
    _npm_help_render_section "Configuration" _npm_help_rows_config
    _npm_help_render_section "Setup Tools" _npm_help_rows_setup
    _npm_help_render_section "Certificate Management" _npm_help_rows_cert
    _npm_help_render_section "Troubleshooting" _npm_help_rows_troubleshoot
}

npm_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _npm_help_summary
            ;;
        --list|list)
            _npm_help_list_sections
            ;;
        --all|all)
            _npm_help_full
            ;;
        *)
            _npm_help_section_rows "$1"
            ;;
    esac
}

# Helper function to normalize npm config output
_npm_config_get() {
    local value
    value="$(npm config get "$1" 2>/dev/null)"
    # Normalize null or empty values to "(not set)"
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "(not set)"
    else
        echo "$value"
    fi
}

# NPM Config Function - show all important npm settings in one command
npm_config() {
    ux_header "NPM Configuration"

    ux_section "Registry & Security"
    ux_table_row "Registry" $(_npm_config_get registry)
    ux_table_row "CA File" $(_npm_config_get cafile)
    ux_table_row "Strict SSL" $(_npm_config_get strict-ssl)

    ux_section "Proxy Settings"
    ux_table_row "Proxy" $(_npm_config_get proxy)
    ux_table_row "HTTPS Proxy" $(_npm_config_get https-proxy)
    ux_table_row "No Proxy" $(_npm_config_get noproxy)

    ux_section "Quick Commands"
    ux_bullet "npm-config              Show this configuration"
    ux_bullet "npm config list         Show all npm settings"
    ux_bullet "npm config set <key>    Update a setting"
}

# NPM Check Wrapper - calls the diagnostic script
npm_check() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_npm.sh" "$@"
}
alias npm-config='npm_config'
alias check-npm='npm_check'
alias npm-help='npm_help'

# --- uv_help (from uv_help.sh) ---

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

# --- bun_help (from bun_help.sh) ---

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
