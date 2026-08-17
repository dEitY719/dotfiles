#!/usr/bin/env bash
# claude/skills/obsidian-session-clip/lib/resolve-vault.sh
#
# F-1 vault default resolution for the obsidian:session-clip skill.
#
# The hardcoded single default ($HOME/para/project/obsidian-para) ignores
# this repo's PC-mode SSOT (docs/.ssot/pc-environment.md): internal PCs keep
# a separate company vault at obsidian-para-company, so with no --vault and
# no OBSIDIAN_VAULT_DIR, an internal-mode PC always stopped at vault-missing
# (dEitY719/dotfiles#1351). This script only widens the *default candidate* —
# existence checking stays SKILL.md Step 1's job.
#
# Usage:
#   resolve-vault.sh [explicit-vault-path]
#   resolve-vault.sh -h | --help | help

set -euo pipefail

usage() {
    cat <<'EOF'
resolve-vault.sh — PC-mode-aware vault default for obsidian:session-clip

Usage:
  resolve-vault.sh [explicit-vault-path]
      Print the resolved vault path on stdout, by priority:
        1. <explicit-vault-path>, if non-empty (e.g. --vault from the caller)
        2. $OBSIDIAN_VAULT_DIR, if non-empty
        3. $HOME/.dotfiles-setup-mode, read and trimmed:
             internal | 2  -> $HOME/para/project/obsidian-para-company
             (anything else, incl. missing/unreadable file) ->
                               $HOME/para/project/obsidian-para
      Always exits 0. Does not check whether the resolved path exists.

  resolve-vault.sh -h | --help | help
      Print this text.
EOF
}

resolve() {
    explicit="${1:-}"

    if [ -n "$explicit" ]; then
        printf '%s\n' "$explicit"
        return 0
    fi

    if [ -n "${OBSIDIAN_VAULT_DIR:-}" ]; then
        printf '%s\n' "$OBSIDIAN_VAULT_DIR"
        return 0
    fi

    mode="$( { cat "$HOME/.dotfiles-setup-mode" 2>/dev/null || true; } | tr -d '[:space:]')"
    case "$mode" in
        internal | 2)
            printf '%s\n' "$HOME/para/project/obsidian-para-company"
            ;;
        *)
            printf '%s\n' "$HOME/para/project/obsidian-para"
            ;;
    esac
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    resolve "${1:-}"
}

main "$@"
