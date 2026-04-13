#!/bin/sh
# shell-common/functions/security_ssh_help.sh
# Bundle: security, SSL, and SSH help functions

# --- crt_help (from security_help.sh) ---

# NOTE: UX library is loaded by the loader before functions/ — no need to reload here

_crt_help_summary() {
    ux_info "Usage: crt-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "overview: npm/Node/Python CA | custom & system | security.local.sh"
    ux_bullet_sub "options: External (custom crt) | Internal (system CA)"
    ux_bullet_sub "setup: crtsetup"
    ux_bullet_sub "env: NODE_EXTRA_CA_CERTS | REQUESTS_CA_BUNDLE"
    ux_bullet_sub "config: shell-common/env/security.local.sh"
    ux_bullet_sub "related: npm-help | security.sh | setup.sh"
    ux_bullet_sub "details: crt-help <section>  (example: crt-help options)"
}

_crt_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "overview"
    ux_bullet_sub "options"
    ux_bullet_sub "setup"
    ux_bullet_sub "env"
    ux_bullet_sub "config"
    ux_bullet_sub "related"
}

_crt_help_rows_overview() {
    ux_bullet "Manages CA certificates for npm, Node.js, and Python"
    ux_bullet "Supports custom certificates (company proxy) and system CA bundles"
    ux_bullet "Configuration stored in: shell-common/env/security.local.sh"
}

_crt_help_rows_options() {
    ux_bullet "Option 1: Custom Certificate (External Company PC - VPN)"
    ux_bullet " • Certificate path: ${UX_MUTED}/usr/local/share/ca-certificates/samsungsemi-prx.com.crt${UX_RESET}"
    ux_bullet " • Install with: ${UX_SUCCESS}crtsetup${UX_RESET}"
    ux_bullet "Option 2: System CA Bundle (Internal Company PC)"
    ux_bullet " • Certificate path: ${UX_MUTED}/etc/ssl/certs/ca-certificates.crt${UX_RESET}"
    ux_bullet " • Already system default, no setup needed"
}

_crt_help_rows_setup() {
    ux_table_row "crtsetup" "Interactive CA certificate setup script"
}

_crt_help_rows_env() {
    ux_table_row "NODE_EXTRA_CA_CERTS" "Used by Node.js/npm for certificate validation"
    ux_table_row "REQUESTS_CA_BUNDLE" "Used by Python for certificate validation"
}

_crt_help_rows_config() {
    ux_info "Location: ${UX_BOLD}shell-common/env/security.local.sh${UX_RESET}"
}

_crt_help_rows_related() {
    ux_table_row "npm-help" "NPM package manager commands and setup"
    ux_table_row "security.sh" "Security environment variable configuration"
    ux_table_row "setup.sh" "Initial environment-specific setup"
}

_crt_help_render_section() {
    ux_section "$1"
    "$2"
}

_crt_help_section_rows() {
    case "$1" in
        overview)
            _crt_help_rows_overview
            ;;
        options|option)
            _crt_help_rows_options
            ;;
        setup|install)
            _crt_help_rows_setup
            ;;
        env|environment)
            _crt_help_rows_env
            ;;
        config|configuration)
            _crt_help_rows_config
            ;;
        related)
            _crt_help_rows_related
            ;;
        *)
            ux_error "Unknown crt-help section: $1"
            ux_info "Try: crt-help --list"
            return 1
            ;;
    esac
}

_crt_help_full() {
    ux_header "CA Certificate Setup Guide"

    _crt_help_render_section "Overview" _crt_help_rows_overview
    _crt_help_render_section "Two Options" _crt_help_rows_options
    _crt_help_render_section "Setup Command" _crt_help_rows_setup
    _crt_help_render_section "Environment Variables" _crt_help_rows_env
    _crt_help_render_section "Configuration File" _crt_help_rows_config
    _crt_help_render_section "Related Commands" _crt_help_rows_related
}

crt_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _crt_help_summary
            ;;
        --list|list)
            _crt_help_list_sections
            ;;
        --all|all)
            _crt_help_full
            ;;
        *)
            _crt_help_section_rows "$1"
            ;;
    esac
}

alias crt-help='crt_help'

# --- ssh_help (from ssh_help.sh) ---

_ssh_help_summary() {
    ux_info "Usage: ssh-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "ssh: ssh <host> | ssh <host> <cmd>"
    ux_bullet_sub "scp: pull | push"
    ux_bullet_sub "hosts: registered hosts in ~/.ssh/config"
    ux_bullet_sub "config: ~/.ssh/config -> dotfiles/ssh/config"
    ux_bullet_sub "details: ssh-help <section>  (example: ssh-help hosts)"
}

_ssh_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "ssh"
    ux_bullet_sub "scp"
    ux_bullet_sub "hosts"
    ux_bullet_sub "config"
}

_ssh_help_rows_ssh() {
    ux_table_row "ssh <host>" "ssh ssai-dev" "Connect to server"
    ux_table_row "ssh <host> <cmd>" "ssh ssai-dev 'ls /home'" "Run remote command"
}

_ssh_help_rows_scp() {
    ux_table_row "pull" "scp <host>:<src> <dst>" "Download from server"
    ux_table_row "push" "scp <src> <host>:<dst>" "Upload to server"
}

_ssh_help_rows_hosts() {
    if [ -f "${HOME}/.ssh/config" ]; then
        set -f  # Disable glob expansion to prevent Host * from expanding
        while IFS= read -r line; do
            # Trim leading whitespace
            line_trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
            case "$line_trimmed" in
                \#* | "")  continue ;;  # Skip comments and empty lines
                Host\ \*)  continue ;;  # Skip wildcard Host *
                Host\ *)
                    hosts="${line_trimmed#Host }"
                    for host in $hosts; do
                        ux_bullet "$host"
                    done
                    ;;
            esac
        done < "${HOME}/.ssh/config"
        set +f  # Re-enable glob expansion
    else
        ux_info "~/.ssh/config not found. Run ./setup.sh to create symlink."
    fi
}

_ssh_help_rows_config() {
    ux_table_row "config file" "~/.ssh/config → dotfiles/ssh/config" "Managed by dotfiles"
}

_ssh_help_render_section() {
    ux_section "$1"
    "$2"
}

_ssh_help_section_rows() {
    case "$1" in
        ssh|connect)
            _ssh_help_rows_ssh
            ;;
        scp|transfer)
            _ssh_help_rows_scp
            ;;
        hosts|registered)
            _ssh_help_rows_hosts
            ;;
        config|configuration)
            _ssh_help_rows_config
            ;;
        *)
            ux_error "Unknown ssh-help section: $1"
            ux_info "Try: ssh-help --list"
            return 1
            ;;
    esac
}

_ssh_help_full() {
    ux_header "SSH / SCP Commands"

    _ssh_help_render_section "SSH - Connect & Run" _ssh_help_rows_ssh
    _ssh_help_render_section "SCP - File Transfer" _ssh_help_rows_scp
    _ssh_help_render_section "Registered Hosts (~/.ssh/config)" _ssh_help_rows_hosts
    _ssh_help_render_section "Config" _ssh_help_rows_config
}

ssh_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _ssh_help_summary
            ;;
        --list|list)
            _ssh_help_list_sections
            ;;
        --all|all)
            _ssh_help_full
            ;;
        *)
            _ssh_help_section_rows "$1"
            ;;
    esac
}

alias ssh-help='ssh_help'

# --- ssl_help (from ssl_help.sh) ---

_ssl_help_summary() {
    ux_info "Usage: ssl-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "status: SSL_CERT_FILE | REQUESTS_CA_BUNDLE | NODE_EXTRA_CA_CERTS"
    ux_bullet_sub "commands: echo \$SSL_CERT_FILE | env grep cert"
    ux_bullet_sub "files: security.local.sh status"
    ux_bullet_sub "paths: Internal | External | System CA"
    ux_bullet_sub "tools: curl | wget | git | python | npm"
    ux_bullet_sub "notes: SSL_CERT_FILE | REQUESTS_CA_BUNDLE | NODE_EXTRA_CA_CERTS"
    ux_bullet_sub "details: ssl-help <section>  (example: ssl-help status)"
}

_ssl_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "status"
    ux_bullet_sub "commands"
    ux_bullet_sub "files"
    ux_bullet_sub "paths"
    ux_bullet_sub "tools"
    ux_bullet_sub "notes"
}

_ssl_help_rows_status() {
    if [ -n "$SSL_CERT_FILE" ]; then
        ux_success "SSL_CERT_FILE: $SSL_CERT_FILE"
        if [ -f "$SSL_CERT_FILE" ]; then
            ux_success "  ✓ File exists and is readable"
        else
            ux_warning "  ✗ File NOT found (may need to be installed)"
        fi
    else
        ux_warning "SSL_CERT_FILE: [NOT SET]"
        ux_info "  This is normal for public/home environments"
    fi

    if [ -n "$REQUESTS_CA_BUNDLE" ]; then
        ux_success "REQUESTS_CA_BUNDLE: $REQUESTS_CA_BUNDLE (Python requests)"
    else
        ux_info "REQUESTS_CA_BUNDLE: [NOT SET]"
    fi

    if [ -n "$NODE_EXTRA_CA_CERTS" ]; then
        ux_success "NODE_EXTRA_CA_CERTS: $NODE_EXTRA_CA_CERTS (Node.js)"
    else
        ux_info "NODE_EXTRA_CA_CERTS: [NOT SET]"
    fi
}

_ssl_help_rows_commands() {
    ux_bullet "echo \$SSL_CERT_FILE                  Show SSL certificate file"
    ux_bullet "echo \$REQUESTS_CA_BUNDLE             Show Python requests CA bundle"
    ux_bullet "env | grep -i cert                   Show all certificate vars"
}

_ssl_help_rows_files() {
    local security_local="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/env/security.local.sh"
    if [ -f "$security_local" ]; then
        ux_success "security.local.sh: exists"
        ux_bullet "Location: $security_local"
    else
        ux_info "security.local.sh: not configured (public environment)"
    fi
}

_ssl_help_rows_paths() {
    ux_bullet "Internal PC:  /usr/share/ca-certificates/extra/McAfee_Certificate.crt"
    ux_bullet "External PC:  /usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
    ux_bullet "System CA:    /etc/ssl/certs/ca-certificates.crt"
}

_ssl_help_rows_tools() {
    ux_bullet "curl                 - Web requests and downloads"
    ux_bullet "wget                 - File downloads"
    ux_bullet "git                  - Git operations (HTTPS)"
    ux_bullet "python (requests)    - HTTP library"
    ux_bullet "npm                  - Node.js package manager"
}

_ssl_help_rows_notes() {
    ux_warning "Different variables for different tools:"
    ux_info "  - SSL_CERT_FILE:        curl, wget, git"
    ux_info "  - REQUESTS_CA_BUNDLE:   Python requests"
    ux_info "  - NODE_EXTRA_CA_CERTS:  Node.js"
}

_ssl_help_render_section() {
    ux_section "$1"
    "$2"
}

_ssl_help_section_rows() {
    case "$1" in
        status|current)
            _ssl_help_rows_status
            ;;
        commands|quick)
            _ssl_help_rows_commands
            ;;
        files|config)
            _ssl_help_rows_files
            ;;
        paths|environment)
            _ssl_help_rows_paths
            ;;
        tools)
            _ssl_help_rows_tools
            ;;
        notes|important)
            _ssl_help_rows_notes
            ;;
        *)
            ux_error "Unknown ssl-help section: $1"
            ux_info "Try: ssl-help --list"
            return 1
            ;;
    esac
}

_ssl_help_full() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "SSL Certificate Configuration & Diagnostics"
    else
        echo "=== SSL Certificate Configuration & Diagnostics ==="
    fi

    if type ux_section >/dev/null 2>&1; then
        _ssl_help_render_section "Current SSL Certificate Status" _ssl_help_rows_status
        _ssl_help_render_section "Quick Commands" _ssl_help_rows_commands
        _ssl_help_render_section "Security Configuration Files" _ssl_help_rows_files
        _ssl_help_render_section "Certificate Paths by Environment" _ssl_help_rows_paths
        _ssl_help_render_section "Tools That Use SSL_CERT_FILE" _ssl_help_rows_tools
        _ssl_help_render_section "Important Notes" _ssl_help_rows_notes
    else
        # Fallback for minimal shells without UX library
        echo ""
        echo "Current SSL_CERT_FILE: ${SSL_CERT_FILE:-[NOT SET]}"
        echo "Current REQUESTS_CA_BUNDLE: ${REQUESTS_CA_BUNDLE:-[NOT SET]}"
        echo ""
        echo "Quick commands:"
        echo "  echo \$SSL_CERT_FILE       # Show SSL certificate"
        echo "  env | grep -i cert        # Show all certificate variables"
        echo ""
    fi
}

ssl_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _ssl_help_summary
            ;;
        --list|list)
            _ssl_help_list_sections
            ;;
        --all|all)
            _ssl_help_full
            ;;
        *)
            _ssl_help_section_rows "$1"
            ;;
    esac
}

# Wrapper function for future check_ssl.sh diagnostic (placeholder)
ssl_check() {
    local check_ssl_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_ssl.sh"
    if [ -f "$check_ssl_script" ]; then
        bash "$check_ssl_script" "$@"
    else
        if type ux_info >/dev/null 2>&1; then
            ux_info "check-ssl script coming soon. Running ssl-help for now..."
        fi
        ssl_help "$@"
    fi
}

alias ssl-help='ssl_help'
alias check-ssl='ssl_check'

# --- ssh_check (WSL SSH key setup) ---

ssh_check() {
    local check_ssh_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/check_ssh.sh"
    if [ -f "$check_ssh_script" ]; then
        bash "$check_ssh_script" "$@"
    else
        if type ux_error >/dev/null 2>&1; then
            ux_error "check_ssh.sh not found: $check_ssh_script"
        fi
    fi
}

alias ssh-check='ssh_check'
