#!/bin/bash
# herdr/setup.sh: herdr config activation + plugin bootstrap
#
# PURPOSE: Make a fresh machine's herdr match this repo — symlink the tracked
#          config into ~/.config/herdr, then install the plugins whose actions
#          that config binds keys to.
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: Symlink target declared in shell-common/config/symlinks.conf
#       Plugin list declared in herdr/plugins.conf
#
# The two halves fail differently on purpose:
#   - config symlink  — hard-fail (exit 1). A missing source means a dangling
#                       link and herdr silently reverting to its defaults.
#   - plugin install  — soft-fail. Installs reach GitHub and build from source;
#                       on a proxied corporate network that can fail for reasons
#                       this script cannot fix. Never abort the parent setup.sh
#                       (which runs under `set -e`) over it — warn and move on.
#
# Opt out of the plugin half with HERDR_SKIP_PLUGINS=1.

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_SCRIPT_DIR%/herdr}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

HERDR_CONFIG_SRC="${_SCRIPT_DIR}/config.toml"
HERDR_CONFIG_DIR="${HOME}/.config/herdr"
HERDR_CONFIG_LINK="${HERDR_CONFIG_DIR}/config.toml"
HERDR_PLUGINS_CONF="${_SCRIPT_DIR}/plugins.conf"

ux_header "herdr Config Setup"

# ============================================================================
# Part 1: config symlink (hard-fail)
# ============================================================================

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

link_current_target=""
[ -L "${HERDR_CONFIG_LINK}" ] && link_current_target=$(readlink "${HERDR_CONFIG_LINK}")

if [ "${link_current_target}" = "${HERDR_CONFIG_SRC}" ]; then
	ux_success "Symlink already correct: ~/.config/herdr/config.toml → ${HERDR_CONFIG_SRC}"
else
	if [ -L "${HERDR_CONFIG_LINK}" ]; then
		ux_info "Updating symlink (was: ${link_current_target})"
		rm "${HERDR_CONFIG_LINK}"
	elif [ -e "${HERDR_CONFIG_LINK}" ]; then
		backup="${HERDR_CONFIG_LINK}.backup"
		rm -f "${backup}"
		ux_info "Backing up existing file: ${backup}"
		mv "${HERDR_CONFIG_LINK}" "${backup}"
	fi
	ln -s "${HERDR_CONFIG_SRC}" "${HERDR_CONFIG_LINK}"
	ux_success "Created: ~/.config/herdr/config.toml → ${HERDR_CONFIG_SRC}"
fi

# ============================================================================
# Part 2: plugin bootstrap (soft-fail)
# ============================================================================

# Returns 0 when PLUGIN_ID is already installed. `--plugin` is an exact-id
# filter (a partial id matches nothing), and it exits 0 either way, so the
# output — not the exit status — carries the answer.
#
# awk compares the id field literally. grep would treat the dots in ids like
# `persiyanov.reviewr` as any-char wildcards.
_herdr_plugin_installed() {
	herdr plugin list --plugin "$1" 2>/dev/null |
		awk -v id="$1" '$1 == "-" && $2 == id { found = 1 } END { exit !found }'
}

_herdr_install_plugins() {
	if [ "${HERDR_SKIP_PLUGINS:-0}" = "1" ]; then
		ux_info "Plugin bootstrap skipped (HERDR_SKIP_PLUGINS=1)"
		return 0
	fi

	if ! command -v herdr >/dev/null 2>&1; then
		ux_info "herdr not on PATH — plugin bootstrap skipped"
		ux_bullet "Install herdr first: herdr-help install"
		return 0
	fi

	if [ ! -r "${HERDR_PLUGINS_CONF}" ]; then
		ux_warning "Plugin list not readable: ${HERDR_PLUGINS_CONF} — skipping"
		return 0
	fi

	ux_section "herdr plugins"

	installed=0
	skipped=0
	failed=0
	failed_repos=""

	while IFS='|' read -r plugin_id repo description; do
		case "$plugin_id" in
			''|\#*) continue ;;
		esac
		[ -n "$repo" ] || continue

		if _herdr_plugin_installed "$plugin_id"; then
			ux_success "already installed: ${plugin_id}"
			skipped=$((skipped + 1))
			continue
		fi

		ux_info "installing ${plugin_id} from ${repo} (${description})"
		# -y skips the interactive confirmation; setup.sh is non-interactive here.
		if herdr plugin install "$repo" -y; then
			installed=$((installed + 1))
			ux_success "installed: ${plugin_id}"
		else
			failed=$((failed + 1))
			failed_repos="${failed_repos} ${repo}"
			ux_warning "failed: ${plugin_id} (${repo})"
		fi
	done < "${HERDR_PLUGINS_CONF}"

	ux_info "plugins — installed: ${installed}, already present: ${skipped}, failed: ${failed}"

	if [ "$failed" -gt 0 ]; then
		ux_warning "Some plugins did not install. herdr still runs; the keybindings for the missing plugins will do nothing."
		ux_bullet "Retry manually (needs GitHub reachability — behind a corporate proxy this is the usual cause):"
		for repo in ${failed_repos}; do
			ux_bullet_sub "herdr plugin install ${repo}"
		done
		ux_bullet "Verify afterwards: herdr plugin list"
	fi

	return 0
}

_herdr_install_plugins

# ============================================================================
# Part 3: apply to a running server (best-effort)
# ============================================================================

# A running server keeps the old config until told otherwise. Absent binary or
# no running server is the normal case on a fresh machine.
if command -v herdr >/dev/null 2>&1; then
	if herdr server reload-config >/dev/null 2>&1; then
		ux_success "Reloaded config in the running herdr server"
	else
		ux_info "herdr server not running — config applies on next start"
	fi
fi

# Plugin failures are reported, never fatal — see the header comment.
exit 0
