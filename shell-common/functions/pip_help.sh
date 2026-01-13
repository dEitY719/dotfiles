#!/bin/sh
# shell-common/functions/pip_help.sh
# Pip help function (POSIX-compatible, shared between bash and zsh)

pip_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "Pip Configuration & Diagnostics"
    else
        echo ""
        echo "Pip Configuration & Diagnostics"
        echo ""
    fi

    if type ux_section >/dev/null 2>&1; then
        ux_section "Diagnostic Commands"
        ux_bullet "check-pip            Run full pip diagnostic"
        ux_bullet "check-pip config     Show pip configuration"
        ux_bullet "check-pip file       pip.conf file check"
        ux_bullet "check-pip repo       Repository connectivity test"
        ux_bullet "check-pip env        Environment variables"
        echo ""

        ux_section "Quick Commands"
        ux_bullet "pip config list                 Show all pip settings"
        ux_bullet "pip config list --verbose       Show pip config files loading"
        ux_bullet "cat \$HOME/.config/pip/pip.conf  View user pip config"
        ux_bullet "pip --version                   Check pip version"
        echo ""

        ux_section "Environment Setup"
        ux_bullet "./setup.sh                      Run setup (choose environment)"
        ux_bullet "               1) Public PC"
        ux_bullet "               2) Internal company PC (proxy + internal repo)"
        ux_bullet "               3) External company PC (VPN)"
        echo ""

        ux_section "Proxy & Repository Info"
        ux_bullet "Proxy:            http://12.26.204.100:8080"
        ux_bullet "Internal Repo:    http://repo.samsungds.net:8081/artifactory/api/pypi/pypi/simple"
        ux_bullet "DataService Repo: http://nexus.adpaas.cloud.samsungds.net/repository/dataservice-pypi/simple"
        echo ""

        ux_section "Troubleshooting"
        ux_bullet "pip install tox              Install package from configured repo"
        ux_bullet "pip install -v tox           Verbose output for debugging"
        ux_bullet "pip cache purge              Clear pip cache"
        ux_bullet "pip config list --verbose    See which config file is loaded"
        echo ""

        ux_section "Important Notes"
        ux_warning "CA certificate: Configured via security.local.sh (REQUESTS_CA_BUNDLE)"
        ux_info "Config files are managed by setup.sh - do not edit manually"
        ux_info "Symlink: ~/.config/pip/pip.conf -> shell-common/config/pip/pip.conf.*"
        echo ""
    else
        # Fallback for minimal shells without UX library
        echo "Diagnostic Commands:"
        echo "  check-pip            Run full pip diagnostic"
        echo "  check-pip config     Show pip configuration"
        echo "  check-pip repo       Repository connectivity test"
        echo ""
        echo "Quick Commands:"
        echo "  pip config list      Show all pip settings"
        echo "  pip --version        Check pip version"
        echo ""
    fi
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

# Aliases for pip-help and check-pip
alias pip-help='pip_help'
alias check-pip='pip_check'
