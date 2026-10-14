#!/bin/bash
# ssh/setup.sh: SSH configuration setup
#
# PURPOSE: Create ~/.ssh/config symlink pointing to dotfiles/ssh/config
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: Symlink target declared in shell-common/config/symlinks.conf
#       This script adds permissions/backup logic on top of the declarative config.

# pwd -P: link to the physical checkout path, the same one symlink-manager.sh
# expands ${DOTFILES_ROOT} to, so the two never rewrite each other's link.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_ROOT="${_SCRIPT_DIR%/ssh}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
# shellcheck source=../shell-common/lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

SSH_CONFIG_SRC="${_SCRIPT_DIR}/config"
SSH_CONFIG_LINK="${HOME}/.ssh/config"

ux_header "SSH Configuration Setup"

# Ensure ~/.ssh directory exists with correct permissions
if [ ! -d "${HOME}/.ssh" ]; then
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    ux_success "Created: ~/.ssh (700)"
fi

# Same link -> no-op; real file -> backed up to config.original (#806, #2138).
dotfiles_ensure_link "${SSH_CONFIG_SRC}" "${SSH_CONFIG_LINK}" || exit 1
chmod 600 "${SSH_CONFIG_SRC}"
ux_success "Linked: ~/.ssh/config → ${SSH_CONFIG_SRC}"
