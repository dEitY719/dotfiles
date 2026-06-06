#!/bin/sh
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
# Usage: obsidian-claude [yolo|work|work1]

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Windows-side Obsidian vault, mounted under WSL. Intentionally absolute.
OBSIDIAN_VAULT_DIR="/mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote"  # allow-abs-home

obsidian_claude() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-work}" in
        -h|--help|help)
            ux_header "obsidian-claude - launch Claude in the Obsidian vault"
            ux_info "Usage: obsidian-claude [yolo|work|work1]"
            ux_info ""
            ux_info "Enters the TilNote vault, then runs claude-yolo for the"
            ux_info "chosen account (default: work)."
            ux_info ""
            ux_info "Accounts:"
            ux_info "  yolo    personal default account (claude-yolo)"
            ux_info "  work    work account (default)"
            ux_info "  work1   secondary work account"
            return 0
            ;;
        yolo)  set -- ;;
        work)  set -- --user work ;;
        work1) set -- --user work1 ;;
        *)
            ux_error "Unknown account: $1"
            ux_info "Available: yolo, work, work1"
            return 1
            ;;
    esac

    if [ ! -d "$OBSIDIAN_VAULT_DIR" ]; then
        ux_error "Vault not found: $OBSIDIAN_VAULT_DIR"
        return 1
    fi

    cd "$OBSIDIAN_VAULT_DIR" || return 1
    claude_yolo "$@"
}
