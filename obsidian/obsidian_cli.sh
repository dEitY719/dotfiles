#!/bin/sh
# shellcheck shell=bash
# obsidian/obsidian_cli.sh
# Unified `obsidian` command (POSIX-compatible, bash + zsh).
#
# One `obsidian ...` entry point, routed to the right backend per environment:
#   - WSL:          Windows desktop CLI redirector (Obsidian.com)
#                   forwards subcommands: search / read / create / property:set / ...
#   - native Linux: latest Obsidian-*.AppImage (GUI launcher)
#
# Path overrides (resolved at call-time, never at source-time):
#   OBSIDIAN_CLI_BIN  WSL redirector  (default: /mnt/c/Program Files/Obsidian/Obsidian.com)
#   OBSIDIAN_BIN      explicit AppImage path (native Linux)
#   OBSIDIAN_HOME     dir scanned for Obsidian-*.AppImage (default: ~/application)
#
# WSL prerequisites — see obsidian/AGENTS.md for the full guide:
#   1. Obsidian *installer* 1.12.7+ (the .com redirector ships with the
#      installer, not with the asar auto-update).
#   2. Settings -> General -> "Command line interface" toggle ON + registration.
#   3. The Obsidian app must be running (the first command auto-launches it).
#
# Usage:
#   obsidian search query="PARA" limit=5
#   obsidian read file="My Note"
#   obsidian create name="New Note" path="folder/New Note.md" content="# Hello" silent
#   obsidian                          # no args -> launch the app / GUI
#
# Issue #1023.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# --- private helpers -------------------------------------------------------

# True when running under WSL.
_obsidian_is_wsl() {
	[ -n "${WSL_DISTRO_NAME-}" ] && return 0
	[ -n "${WSL_INTEROP-}" ] && return 0
	[ -r /proc/version ] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

# Resolve the WSL CLI redirector path.
_obsidian_resolve_cli_bin() {
	printf '%s' "${OBSIDIAN_CLI_BIN:-/mnt/c/Program Files/Obsidian/Obsidian.com}"
}

# Resolve the native-Linux AppImage. Globs expand alphabetically — keep the
# LAST executable match so Obsidian-1.8.10 wins over Obsidian-1.7.0 (PR #520).
_obsidian_resolve_appimage_bin() {
	if [ -n "${OBSIDIAN_BIN-}" ]; then
		printf '%s' "$OBSIDIAN_BIN"
		return 0
	fi
	_ob_home="${OBSIDIAN_HOME:-$HOME/application}"
	_ob_found=""
	for _ob_app in "$_ob_home"/Obsidian-*.AppImage; do
		[ -x "$_ob_app" ] && _ob_found="$_ob_app"
	done
	if [ -n "$_ob_found" ]; then
		printf '%s' "$_ob_found"
		unset _ob_home _ob_app _ob_found
		return 0
	fi
	unset _ob_home _ob_app _ob_found
	printf '%s' "$HOME/application/Obsidian-1.8.10.AppImage"
}

# Error / hint helpers: prefer ux_lib, fall back to plain stderr when it is
# not loaded (e.g. a minimal DOTFILES_FORCE_INIT context).
_obsidian_err() {
	if type ux_error >/dev/null 2>&1; then
		ux_error "$1"
	else
		printf 'obsidian: %s\n' "$1" >&2
	fi
}

_obsidian_hint() {
	if type ux_info >/dev/null 2>&1; then
		ux_info "$1"
	else
		printf '  %s\n' "$1" >&2
	fi
}

_obsidian_usage() {
	if type ux_header >/dev/null 2>&1; then
		ux_header "obsidian - launch Obsidian / forward CLI commands"
		ux_info "Usage: obsidian [cli-subcommand args...]"
		ux_info "  WSL:   forwards to Obsidian.com (search/read/create/property:set/backlinks/...)"
		ux_info "  Linux: launches the latest Obsidian-*.AppImage"
		ux_info "  (no args) launches / focuses the app"
		ux_info "Overrides: OBSIDIAN_CLI_BIN (WSL), OBSIDIAN_BIN / OBSIDIAN_HOME (Linux)"
	else
		printf 'obsidian - launch Obsidian / forward CLI commands\n'
		printf 'Usage: obsidian [cli-subcommand args...]\n'
	fi
}

# --- public command --------------------------------------------------------

obsidian() {
	case "${1:-}" in
	-h | --help | help)
		_obsidian_usage
		return 0
		;;
	esac

	if _obsidian_is_wsl; then
		_ob_bin=$(_obsidian_resolve_cli_bin)
		if [ ! -x "$_ob_bin" ]; then
			_obsidian_err "CLI redirector not found at $_ob_bin"
			_obsidian_hint "Obsidian 1.12.7+ 인스톨러 실행 후 설정 -> General -> \"Command line interface\" 토글 ON 필요"
			_obsidian_hint "경로가 다르면 OBSIDIAN_CLI_BIN 으로 오버라이드"
			unset _ob_bin
			return 127
		fi
	else
		_ob_bin=$(_obsidian_resolve_appimage_bin)
		if [ ! -x "$_ob_bin" ]; then
			_obsidian_err "binary not found at $_ob_bin"
			_obsidian_hint "Set OBSIDIAN_BIN or place an AppImage under OBSIDIAN_HOME (default ~/application)."
			unset _ob_bin
			return 1
		fi
	fi

	"$_ob_bin" "$@"
	_ob_rc=$?
	unset _ob_bin
	return "$_ob_rc"
}
