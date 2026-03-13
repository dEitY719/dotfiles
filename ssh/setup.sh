#!/bin/bash
# ssh/setup.sh: SSH configuration setup
#
# PURPOSE: Create ~/.ssh/config symlink pointing to dotfiles/ssh/config
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_SCRIPT_DIR%/ssh}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

SSH_CONFIG_SRC="${_SCRIPT_DIR}/config"
SSH_CONFIG_LINK="${HOME}/.ssh/config"

ux_header "SSH Configuration Setup"

# Ensure ~/.ssh directory exists with correct permissions
if [ ! -d "${HOME}/.ssh" ]; then
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    ux_success "Created: ~/.ssh (700)"
fi

# Handle existing file or symlink
if [ -L "${SSH_CONFIG_LINK}" ]; then
    current_target=$(readlink "${SSH_CONFIG_LINK}")
    if [ "${current_target}" = "${SSH_CONFIG_SRC}" ]; then
        ux_success "Symlink already correct: ~/.ssh/config → ${SSH_CONFIG_SRC}"
        exit 0
    fi
    ux_info "Updating symlink (was: ${current_target})"
    rm "${SSH_CONFIG_LINK}"
elif [ -f "${SSH_CONFIG_LINK}" ]; then
    backup="${SSH_CONFIG_LINK}.backup.$(date +%Y%m%d%H%M%S)"
    ux_info "Backing up existing file: ${backup}"
    mv "${SSH_CONFIG_LINK}" "${backup}"
fi

ln -s "${SSH_CONFIG_SRC}" "${SSH_CONFIG_LINK}"
chmod 644 "${SSH_CONFIG_SRC}"
ux_success "Created: ~/.ssh/config → ${SSH_CONFIG_SRC}"
