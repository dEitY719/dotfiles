#!/bin/bash
# obsidian/setup.sh: Obsidian CLI wrapper setup
#
# PURPOSE: Keep the `obsidian` wrapper executable. ~/.local/bin/obsidian links
#          to it so it resolves on PATH in BOTH interactive shells and
#          non-interactive `bash -c` calls made by AI coding agents (#1023).
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: The link is a row in shell-common/config/symlinks.conf, made by
#       ./setup.sh's `symlinks` step (#2139) — not by this script.

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_ROOT="${_SCRIPT_DIR%/obsidian}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

OBSIDIAN_BIN_SRC="${_SCRIPT_DIR}/bin/obsidian"

ux_header "Obsidian CLI Wrapper Setup"

# Source must be executable for the symlink to be runnable.
chmod +x "${OBSIDIAN_BIN_SRC}" || { ux_error "chmod +x failed: ${OBSIDIAN_BIN_SRC}"; exit 1; }
ux_success "Executable: ${OBSIDIAN_BIN_SRC}"
