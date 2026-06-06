#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/obsidian_claude.sh
# Launch Claude Code inside the Obsidian vault with a chosen account.
#
# Enters the TilNote vault directory, then starts claude-yolo for the
# selected account. Default account: work.
#
# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPER NOTES - NAMING CONVENTION (See AGENTS.md:174-178)
# ═══════════════════════════════════════════════════════════════════════════════
# User-facing command: obsidian-claude (dash-form, aliased in aliases/)
# Internal function:   obsidian_claude() (snake_case)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage: obsidian-claude [personal|work|work1] [extra claude args...]

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Derive the vault path lazily at call-time (not source-time) to avoid a
# ~200ms cmd.exe penalty on every shell start.
# Override: export OBSIDIAN_VAULT_DIR before calling to skip auto-detection.
_obsidian_vault_dir() {
	# 1) explicit override wins
	[ -n "${OBSIDIAN_VAULT_DIR-}" ] && {
		printf '%s\n' "$OBSIDIAN_VAULT_DIR"
		return 0
	}
	# 2) Windows %USERPROFILE% universal derivation (works across PCs with different usernames)
	if command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
		local win prof
		win=$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')
		if [ -n "$win" ]; then
			prof=$(wslpath -u "$win" 2>/dev/null)
			[ -n "$prof" ] && {
				printf '%s/Documents/ObsidianVault-TilNote\n' "$prof"
				return 0
			}
		fi
	fi
	return 1
}

obsidian_claude() {
	# zsh compatibility
	if [ -n "${ZSH_VERSION-}" ]; then
		emulate -L sh
	fi

	local account

	# Capture the account selector, keep any remaining args to pass through to
	# claude_yolo (e.g. `obsidian-claude work --resume foo`).
	account="${1:-work}"
	[ $# -gt 0 ] && shift

	case "$account" in
	-h | --help | help)
		ux_header "obsidian-claude - launch Claude in the Obsidian vault"
		ux_info "Usage: obsidian-claude [personal|work|work1] [extra claude args...]"
		ux_info ""
		ux_info "Enters the TilNote vault, then runs claude-yolo for the"
		ux_info "chosen account (default: work)."
		ux_info ""
		ux_info "Accounts:"
		ux_info "  personal  personal default account (claude-yolo)"
		ux_info "  work      work account (default)"
		ux_info "  work1     secondary work account"
		return 0
		;;
	personal) ;; # personal default: no --user
	work)
		# Prepend --user work unless the caller already passed --user.
		case " $* " in
		*" --user "*) ;;
		*) set -- --user work "$@" ;;
		esac
		;;
	work1)
		case " $* " in
		*" --user "*) ;;
		*) set -- --user work1 "$@" ;;
		esac
		;;
	*)
		ux_error "Unknown account: $account"
		ux_info "Available: personal, work, work1"
		return 1
		;;
	esac

	local vault
	vault=$(_obsidian_vault_dir) || {
		ux_error "Obsidian vault 경로를 결정할 수 없음 (cmd.exe/wslpath 확인 또는 OBSIDIAN_VAULT_DIR 설정)"
		return 1
	}

	if [ ! -d "$vault" ]; then
		ux_error "Vault not found: $vault"
		return 1
	fi

	if ! command -v claude_yolo >/dev/null 2>&1; then
		ux_error "claude_yolo not found (is the dotfiles claude integration loaded?)"
		return 1
	fi

	cd "$vault" || return 1
	claude_yolo "$@"
}
