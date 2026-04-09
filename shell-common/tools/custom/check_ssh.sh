#!/bin/bash
# shell-common/tools/custom/check_ssh.sh
# SSH key setup and diagnostics for SSAI project (WSL environment)
# Usage: check_ssh [key|copy|link|all]

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
source "$(dirname "$0")/init.sh" || exit 1

# ============================================================
# Configuration
# ============================================================

KEY_NAME="id_rsa_ssai_bwyoon"
WSL_SSH_DIR="$HOME/.ssh"

# Detect Windows username from WSL
_detect_win_user() {
    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    if [ -z "$win_user" ]; then
        win_user=$(powershell.exe -Command '[System.Environment]::UserName' 2>/dev/null | tr -d '\r\n')
    fi
    echo "$win_user"
}

WIN_USER="$(_detect_win_user)"
WIN_SSH_DIR="/mnt/c/Users/${WIN_USER}/.ssh"

# ============================================================
# Diagnostic functions
# ============================================================

check_ssh_key() {
    ux_header "1. SSH Key (WSL)"

    ux_section "Key Location"
    ux_info "Path: ${WSL_SSH_DIR}/${KEY_NAME}"

    if [ -f "${WSL_SSH_DIR}/${KEY_NAME}" ]; then
        ux_success "Private key exists"
        if [ -f "${WSL_SSH_DIR}/${KEY_NAME}.pub" ]; then
            ux_success "Public key exists"
        else
            ux_warning "Public key missing (${KEY_NAME}.pub)"
        fi
        echo ""
        return 0
    fi

    ux_warning "SSH key not found"
    echo ""

    if ! ux_confirm "Generate SSH key now?" "n"; then
        ux_info "Key generation skipped"
        echo ""
        return 1
    fi

    mkdir -p "$WSL_SSH_DIR"
    chmod 700 "$WSL_SSH_DIR"

    ssh-keygen -t rsa -b 4096 -f "${WSL_SSH_DIR}/${KEY_NAME}" -N ""
    chmod 600 "${WSL_SSH_DIR}/${KEY_NAME}"
    chmod 644 "${WSL_SSH_DIR}/${KEY_NAME}.pub"
    ux_success "SSH key generated: ${WSL_SSH_DIR}/${KEY_NAME}"
    echo ""
}

check_ssh_copy() {
    ux_header "2. Windows Copy"

    if [ -z "$WIN_USER" ]; then
        ux_error "Cannot detect Windows username"
        ux_info "WSL cmd.exe/powershell.exe access may be restricted"
        echo ""
        return 1
    fi

    ux_section "Environment"
    ux_info "WSL User: $USER"
    ux_info "Windows User: $WIN_USER"
    ux_info "Target: ${WIN_SSH_DIR}/${KEY_NAME}"
    echo ""

    if [ ! -f "${WSL_SSH_DIR}/${KEY_NAME}" ]; then
        ux_error "WSL key does not exist. Run 'check_ssh key' first"
        echo ""
        return 1
    fi

    # Check if already copied and up-to-date
    if [ -f "${WIN_SSH_DIR}/${KEY_NAME}" ]; then
        if diff -q "${WSL_SSH_DIR}/${KEY_NAME}" "${WIN_SSH_DIR}/${KEY_NAME}" >/dev/null 2>&1; then
            ux_success "Windows copy already up-to-date"
            echo ""
            return 0
        fi
        ux_warning "Windows copy exists but differs from WSL key"
    fi

    if ! ux_confirm "Copy key to Windows .ssh directory?" "n"; then
        ux_info "Copy skipped"
        echo ""
        return 0
    fi

    if [ ! -d "$WIN_SSH_DIR" ]; then
        mkdir -p "$WIN_SSH_DIR"
        ux_success "Created: $WIN_SSH_DIR"
    fi

    cp "${WSL_SSH_DIR}/${KEY_NAME}" "${WIN_SSH_DIR}/${KEY_NAME}"
    cp "${WSL_SSH_DIR}/${KEY_NAME}.pub" "${WIN_SSH_DIR}/${KEY_NAME}.pub" 2>/dev/null
    ux_success "Copied to: ${WIN_SSH_DIR}/${KEY_NAME}"
    ux_info "SSH config IdentityFile uses: ~/.ssh/${KEY_NAME}"
    echo ""
}

check_ssh_link() {
    ux_header "3. SSH Config Symlink"

    local dotfiles_config="${DOTFILES_ROOT}/ssh/config"
    local ssh_config_link="${WSL_SSH_DIR}/config"

    ux_section "Status"
    if [ ! -f "$dotfiles_config" ]; then
        ux_error "dotfiles ssh/config not found: $dotfiles_config"
        echo ""
        return 1
    fi

    if [ -L "$ssh_config_link" ]; then
        local current_target
        current_target=$(readlink "$ssh_config_link")
        if [ "$current_target" = "$dotfiles_config" ]; then
            ux_success "Symlink correct: ~/.ssh/config -> $dotfiles_config"
            echo ""
            return 0
        fi
        ux_warning "Symlink points to: $current_target"
        ux_info "Expected: $dotfiles_config"
    elif [ -f "$ssh_config_link" ]; then
        ux_warning "~/.ssh/config is a regular file (not a symlink)"
    else
        ux_info "~/.ssh/config does not exist"
    fi
    echo ""

    ux_info "Run 'bash ${DOTFILES_ROOT}/ssh/setup.sh' to fix"
    echo ""
}

# ============================================================
# Main function with sub-command handling
# ============================================================

main() {
    local cmd="${1:-all}"

    case "$cmd" in
        key)
            check_ssh_key
            ;;
        copy)
            check_ssh_copy
            ;;
        link)
            check_ssh_link
            ;;
        all)
            check_ssh_key
            check_ssh_copy
            check_ssh_link
            ;;
        *)
            echo "Usage: check_ssh [key|copy|link|all]"
            echo ""
            echo "  key     - Check/generate WSL SSH key"
            echo "  copy    - Copy key to Windows .ssh directory"
            echo "  link    - Check ~/.ssh/config symlink"
            echo "  all     - Run all checks (default)"
            echo ""
            exit 1
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
