#!/bin/bash
# obsidian/setup.sh: Obsidian CLI wrapper setup
#
# PURPOSE: Symlink the `obsidian` executable into ~/.local/bin so it resolves
#          on PATH in BOTH interactive shells and non-interactive `bash -c`
#          calls made by AI coding agents (issue #1023).
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: Symlink target declared in shell-common/config/symlinks.conf

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_ROOT="${_SCRIPT_DIR%/obsidian}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
# shellcheck source=../shell-common/lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

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

# Same link -> no-op; real file -> backed up to obsidian.original (#2138).
dotfiles_ensure_link "${OBSIDIAN_BIN_SRC}" "${OBSIDIAN_BIN_LINK}" || exit 1
ux_success "Linked: ~/.local/bin/obsidian → ${OBSIDIAN_BIN_SRC}"
