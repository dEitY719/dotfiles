#!/bin/bash
# obsidian/setup.sh: Obsidian CLI wrapper setup
#
# PURPOSE: Symlink the `obsidian` executable into ~/.local/bin so it resolves
#          on PATH in BOTH interactive shells and non-interactive `bash -c`
#          calls made by AI coding agents (issue #1023).
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: Symlink target declared in shell-common/config/symlinks.conf

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_SCRIPT_DIR%/obsidian}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

OBSIDIAN_BIN_SRC="${_SCRIPT_DIR}/bin/obsidian"
BIN_DIR="${HOME}/.local/bin"
OBSIDIAN_BIN_LINK="${BIN_DIR}/obsidian"

ux_header "Obsidian CLI Wrapper Setup"

# Ensure ~/.local/bin exists (it is prepended to PATH in shell-common/env/path.sh).
if [ ! -d "${BIN_DIR}" ]; then
	mkdir -p "${BIN_DIR}"
	ux_success "Created: ~/.local/bin"
fi

# Source must be executable for the symlink to be runnable.
chmod +x "${OBSIDIAN_BIN_SRC}"

# Handle existing symlink or file.
if [ -L "${OBSIDIAN_BIN_LINK}" ]; then
	current_target=$(readlink "${OBSIDIAN_BIN_LINK}")
	if [ "${current_target}" = "${OBSIDIAN_BIN_SRC}" ]; then
		ux_success "Symlink already correct: ~/.local/bin/obsidian → ${OBSIDIAN_BIN_SRC}"
		exit 0
	fi
	ux_info "Updating symlink (was: ${current_target})"
	rm "${OBSIDIAN_BIN_LINK}"
elif [ -e "${OBSIDIAN_BIN_LINK}" ]; then
	backup="${OBSIDIAN_BIN_LINK}.backup"
	rm -f "${backup}"
	ux_info "Backing up existing file: ${backup}"
	mv "${OBSIDIAN_BIN_LINK}" "${backup}"
fi

ln -s "${OBSIDIAN_BIN_SRC}" "${OBSIDIAN_BIN_LINK}"
ux_success "Created: ~/.local/bin/obsidian → ${OBSIDIAN_BIN_SRC}"
