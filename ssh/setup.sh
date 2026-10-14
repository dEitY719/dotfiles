#!/bin/bash
# ssh/setup.sh: SSH configuration setup
#
# PURPOSE: ~/.ssh directory and permissions for the dotfiles ssh config
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: The ~/.ssh/config link is a row in shell-common/config/symlinks.conf,
#       made by ./setup.sh's `symlinks` step (#2139). This script only sets the
#       permissions ssh insists on.

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_ROOT="${_SCRIPT_DIR%/ssh}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

SSH_CONFIG_SRC="${_SCRIPT_DIR}/config"

ux_header "SSH Configuration Setup"

# The symlinks step may have created ~/.ssh with the default umask, so set
# 700 every run rather than only on creation.
if ! { mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh" && chmod 600 "${SSH_CONFIG_SRC}"; }; then
    ux_error "Could not set ssh permissions (~/.ssh 700, ${SSH_CONFIG_SRC} 600)"
    exit 1
fi
ux_success "Permissions: ~/.ssh (700), ssh/config (600)"
