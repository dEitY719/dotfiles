#!/bin/bash
# herdr/setup.sh: herdr config activation + plugin bootstrap
#
# PURPOSE: Make a fresh machine's herdr match this repo — symlink the tracked
#          config, install the plugins whose actions that config binds keys to,
#          and install the external binaries those bindings shell out to.
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
# SSOT: Symlink target declared in shell-common/config/symlinks.conf
#       Plugin list declared in herdr/plugins.conf
#       External tool list declared in herdr/tools.conf
#
# Failure policy: Part 1 (config symlink) hard-fails — a missing source means a
# dangling link and herdr silently reverting to its defaults. Parts 2-4 soft-fail:
# they reach GitHub over a proxied corporate network and can fail for reasons this
# script cannot fix, and everything they provide degrades gracefully (a missing
# plugin makes its keybinding inert, a missing renderer drops the viewer to plain
# text). Never abort the parent setup.sh — which runs under `set -e` — over any of
# it: warn and move on.
#
# Opt out of the install halves with HERDR_SKIP_PLUGINS=1 / HERDR_SKIP_TOOLS=1.

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_SCRIPT_DIR%/herdr}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

HERDR_CONFIG_SRC="${_SCRIPT_DIR}/config.toml"
HERDR_CONFIG_DIR="${HOME}/.config/herdr"
HERDR_CONFIG_LINK="${HERDR_CONFIG_DIR}/config.toml"
HERDR_PLUGINS_CONF="${_SCRIPT_DIR}/plugins.conf"
HERDR_TOOLS_CONF="${_SCRIPT_DIR}/tools.conf"

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

# A function so the "already correct" case returns early instead of nesting the
# rewrite branch. Body matches obsidian/setup.sh except `exit 0` → `return 0`:
# Parts 2-4 must still run.
_herdr_link_config() {
	if [ -L "${HERDR_CONFIG_LINK}" ]; then
		local current_target
		current_target=$(readlink "${HERDR_CONFIG_LINK}")
		if [ "${current_target}" = "${HERDR_CONFIG_SRC}" ]; then
			ux_success "Symlink already correct: ~/.config/herdr/config.toml → ${HERDR_CONFIG_SRC}"
			return 0
		fi
		ux_info "Updating symlink (was: ${current_target})"
		rm "${HERDR_CONFIG_LINK}"
	elif [ -e "${HERDR_CONFIG_LINK}" ]; then
		local backup="${HERDR_CONFIG_LINK}.backup"
		rm -f "${backup}"
		ux_info "Backing up existing file: ${backup}"
		mv "${HERDR_CONFIG_LINK}" "${backup}"
	fi

	ln -s "${HERDR_CONFIG_SRC}" "${HERDR_CONFIG_LINK}"
	ux_success "Created: ~/.config/herdr/config.toml → ${HERDR_CONFIG_SRC}"
}

_herdr_link_config

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

	local installed=0 skipped=0 failed=0 failed_repos=""
	local plugin_id repo description

	while IFS='|' read -r plugin_id repo description; do
		case "$plugin_id" in ''|\#*) continue ;; esac
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
# Part 3: external tool bootstrap (soft-fail)
# ============================================================================

# Debian/Ubuntu ship bat's binary as `batcat`. Bridge it instead of downloading
# a second copy — the viewer looks for `bat`.
_herdr_bridge_batcat() {
	command -v batcat >/dev/null 2>&1 || return 1
	mkdir -p "${HOME}/.local/bin"
	ln -sf "$(command -v batcat)" "${HOME}/.local/bin/bat"
	ux_success "bridged: batcat → ~/.local/bin/bat (no download needed)"
	return 0
}

# Downloads one GitHub release asset, extracts it, and installs the binary into
# ~/.local/bin (the PATH SSOT dir — shell-common/env/path.sh already exports it,
# so nothing here touches PATH or any shell profile).
_herdr_install_one_tool() {
	local _name="$1" _repo="$2" _glob="$3" _bin="$4"
	local _tmp _archive _found

	_tmp=$(mktemp -d) || return 1

	if ! gh release download --repo "$_repo" --pattern "$_glob" --dir "$_tmp" >/dev/null 2>&1; then
		rm -rf "$_tmp"
		return 1
	fi

	# One asset per glob; guard against a release that changed its naming.
	_archive=$(find "$_tmp" -maxdepth 1 -name '*.tar.gz' -print -quit)
	if [ -z "$_archive" ]; then
		rm -rf "$_tmp"
		return 1
	fi

	if ! tar xzf "$_archive" -C "$_tmp" 2>/dev/null; then
		rm -rf "$_tmp"
		return 1
	fi

	# `find` rather than a fixed path: lazygit/glow put the binary at the archive
	# root, delta/bat nest it one level down.
	_found=$(find "$_tmp" -type f -name "$_bin" -perm -u+x -print -quit)
	if [ -z "$_found" ]; then
		rm -rf "$_tmp"
		return 1
	fi

	mkdir -p "${HOME}/.local/bin"
	install -m 0755 "$_found" "${HOME}/.local/bin/${_name}"
	rm -rf "$_tmp"
	return 0
}

_herdr_install_tools() {
	if [ "${HERDR_SKIP_TOOLS:-0}" = "1" ]; then
		ux_info "External tool bootstrap skipped (HERDR_SKIP_TOOLS=1)"
		return 0
	fi

	if [ ! -r "${HERDR_TOOLS_CONF}" ]; then
		ux_warning "Tool list not readable: ${HERDR_TOOLS_CONF} — skipping"
		return 0
	fi

	# The globs in tools.conf pin Linux x86_64. Rather than guess an asset name
	# for another platform, say so and let the user install by hand.
	if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
		ux_info "External tools skipped — release assets are pinned to Linux x86_64 (this host: $(uname -s)/$(uname -m))"
		ux_bullet "Install by hand, or use your package manager: lazygit glow git-delta bat"
		return 0
	fi

	# `gh release download` is the only network path here; the repo already
	# depends on gh (gh/setup.sh) and it inherits gh's auth and proxy config.
	if ! command -v gh >/dev/null 2>&1; then
		ux_warning "gh not on PATH — external tool bootstrap skipped"
		return 0
	fi

	# gh must be authenticated. Unauthenticated is not a usable fallback: the
	# anonymous GitHub API allows 60 requests/hour *per IP*, and a shared
	# corporate egress IP exhausts that long before you get here (measured:
	# HTTP 403 "rate limit exceeded", X-RateLimit-Remaining: 0). Nothing in
	# setup.sh runs `gh auth login`, so on a fresh machine this is the normal
	# first-run state — say what to do and move on.
	if ! gh auth status >/dev/null 2>&1; then
		ux_warning "gh is not authenticated — external tool bootstrap skipped"
		ux_bullet "Run: gh auth login"
		ux_bullet "Then re-run: ./herdr/setup.sh"
		return 0
	fi

	ux_section "herdr external tools"

	local installed=0 skipped=0 failed=0 failed_names=""
	local name repo glob bin description

	while IFS='|' read -r name repo glob bin description; do
		case "$name" in ''|\#*) continue ;; esac
		[ -n "$bin" ] || continue

		if command -v "$name" >/dev/null 2>&1; then
			ux_success "already on PATH: ${name} ($(command -v "$name"))"
			skipped=$((skipped + 1))
			continue
		fi

		if [ "$name" = "bat" ] && _herdr_bridge_batcat; then
			installed=$((installed + 1))
			continue
		fi

		ux_info "installing ${name} from ${repo} (${description})"
		if _herdr_install_one_tool "$name" "$repo" "$glob" "$bin"; then
			installed=$((installed + 1))
			ux_success "installed: ~/.local/bin/${name}"
		else
			failed=$((failed + 1))
			failed_names="${failed_names} ${name}"
			ux_warning "failed: ${name} (${repo})"
		fi
	done < "${HERDR_TOOLS_CONF}"

	ux_info "tools — installed: ${installed}, already present: ${skipped}, failed: ${failed}"

	if [ "$failed" -gt 0 ]; then
		ux_warning "Some tools did not install. herdr still runs — lazygit's keybinding does nothing, and the file viewer falls back to plain text without its renderers."
		ux_bullet "Missing:${failed_names}"
		ux_bullet "Retry needs GitHub release reachability (corporate proxy is the usual cause)"
	fi

	return 0
}

_herdr_install_tools

# ============================================================================
# Part 4: apply to a running server (best-effort)
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

# Install failures are warnings, never fatal — pin the status so the parent's
# `set -e` cannot trip over Parts 2-4. See the header comment.
exit 0
