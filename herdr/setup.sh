#!/bin/bash
# herdr/setup.sh: herdr config activation
#
# PURPOSE: Symlink the tracked herdr config into ~/.config/herdr so the
#          keybindings, theme, and plugin action bindings are identical on
#          every machine instead of living untracked in ~/.config.
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: Symlink target declared in shell-common/config/symlinks.conf
#
# NOTE: herdr plugins themselves are NOT installed here — they are per-machine
#       GitHub checkouts pinned by commit (see `herdr plugin list`). This script
#       only activates the config that binds keys to their actions.

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_SCRIPT_DIR%/herdr}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

HERDR_CONFIG_SRC="${_SCRIPT_DIR}/config.toml"
HERDR_CONFIG_DIR="${HOME}/.config/herdr"
HERDR_CONFIG_LINK="${HERDR_CONFIG_DIR}/config.toml"

ux_header "herdr Config Setup"

# The source must exist; without it the symlink would dangle and herdr would
# silently fall back to its built-in defaults (no custom keybindings).
if [ ! -f "${HERDR_CONFIG_SRC}" ]; then
	ux_error "Source config not found: ${HERDR_CONFIG_SRC}"
	exit 1
fi

# herdr creates this directory itself on first run, but setup.sh may run first.
if [ ! -d "${HERDR_CONFIG_DIR}" ]; then
	mkdir -p "${HERDR_CONFIG_DIR}"
	ux_success "Created: ~/.config/herdr"
fi

# Handle existing symlink or file.
if [ -L "${HERDR_CONFIG_LINK}" ]; then
	current_target=$(readlink "${HERDR_CONFIG_LINK}")
	if [ "${current_target}" = "${HERDR_CONFIG_SRC}" ]; then
		ux_success "Symlink already correct: ~/.config/herdr/config.toml → ${HERDR_CONFIG_SRC}"
		exit 0
	fi
	ux_info "Updating symlink (was: ${current_target})"
	rm "${HERDR_CONFIG_LINK}"
elif [ -e "${HERDR_CONFIG_LINK}" ]; then
	backup="${HERDR_CONFIG_LINK}.backup"
	rm -f "${backup}"
	ux_info "Backing up existing file: ${backup}"
	mv "${HERDR_CONFIG_LINK}" "${backup}"
fi

ln -s "${HERDR_CONFIG_SRC}" "${HERDR_CONFIG_LINK}"
ux_success "Created: ~/.config/herdr/config.toml → ${HERDR_CONFIG_SRC}"

# A running server keeps the old config until told otherwise. Best-effort:
# absent binary or no running server is the normal case on a fresh machine.
if command -v herdr >/dev/null 2>&1; then
	if herdr server reload-config >/dev/null 2>&1; then
		ux_success "Reloaded config in the running herdr server"
	else
		ux_info "herdr server not running — config applies on next start"
	fi
fi
