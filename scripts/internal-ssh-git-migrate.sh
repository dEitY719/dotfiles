#!/bin/bash

# scripts/internal-ssh-git-migrate.sh: seed the machine-local SSH / git
# override files on an internal PC (#2006)
#
# PURPOSE: ssh/config and git/.gitconfig used to carry internal Host blocks
# and the internal GHES credential section. They now only `Include` /
# `[include]` gitignored files under $HOME:
#   ~/.ssh/config.internal.local   <- the last tracked ssh/config that still
#                                     held the real values, verbatim
#   ~/.gitconfig.internal.local    <- the internal [credential "https://..."]
#                                     sections of the last such git/.gitconfig
# The real values are read from this repo's git history (newest version of
# each file without the include line), so this works before or after the
# swap is pulled. ./setup.sh runs it in internal mode.
#
# SAFETY: dry-run by default; never overwrites an existing file; never
# prints file contents; verifies each write (cmp); files are created 0600.
#
# EXIT: 0 on success, 1 when a write fails verification, 2 on bad usage.

_SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT="$(cd "$_SCRIPT_PATH/.." && pwd)"
UX_LIB="$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh"
if [ ! -f "$UX_LIB" ]; then
    echo "CRITICAL ERROR: UX library not found at $UX_LIB. Exiting." >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$UX_LIB"

usage() {
    ux_header "internal-ssh-git-migrate.sh"
    ux_info "Usage: scripts/internal-ssh-git-migrate.sh [--apply] [-h|--help]"
    ux_bullet "--dry-run  (default) report what would be written, write nothing"
    ux_bullet "--apply    write ~/.ssh/config.internal.local and ~/.gitconfig.internal.local when absent"
}

apply=0
case "${1:-}" in
    "" | --dry-run) ;;
    --apply) apply=1 ;;
    -h | --help) usage; exit 0 ;;
    *) ux_error "Unknown option: $1"; usage; exit 2 ;;
esac

# _pre_swap <repo path> <marker>: print the newest committed version of the
# file that does not contain <marker> (the include line added by #2006).
_pre_swap() {
    local c
    for c in $(git -C "$DOTFILES_ROOT" log --format=%H -- "$1" 2>/dev/null); do
        if git -C "$DOTFILES_ROOT" cat-file -e "$c:$1" 2>/dev/null &&
            ! git -C "$DOTFILES_ROOT" show "$c:$1" | grep -qF "$2"; then
            git -C "$DOTFILES_ROOT" show "$c:$1"
            return 0
        fi
    done
    return 1
}

# Keep only [credential "https://<host>"] sections for non-github.com hosts.
_internal_credential_sections() {
    awk '/^[[:space:]]*\[/ {
            keep = ($0 ~ /^\[credential "https:\/\//) &&
                   ($0 !~ /"https:\/\/(gist\.)?github\.com"/)
        }
        keep'
}

failed=0
# _seed <dst under $HOME> <content>
_seed() {
    local dst="$1" content="$2" label="${1#"$HOME"/}"
    if [ -e "$dst" ]; then
        ux_info "Exists, kept as-is: ~/$label"
    elif [ -z "$content" ]; then
        ux_warning "Skipped (no pre-swap values in git history): ~/$label — create it by hand"
    elif [ "$apply" -eq 0 ]; then
        ux_info "Would write: ~/$label"
    else
        [ -d "$(dirname "$dst")" ] || mkdir -m 700 "$(dirname "$dst")"
        if (umask 077 && printf '%s\n' "$content" >"$dst") &&
            printf '%s\n' "$content" | cmp -s - "$dst"; then
            ux_success "Written and verified: ~/$label"
        else
            ux_error "Write failed verification: ~/$label"
            failed=1
        fi
    fi
}

if [ "$apply" -eq 1 ]; then
    ux_header "Seed SSH / git machine-local overrides (apply)"
else
    ux_header "Seed SSH / git machine-local overrides (dry-run, nothing is written)"
fi

_seed "$HOME/.ssh/config.internal.local" \
    "$(_pre_swap ssh/config 'config.internal.local')"
_seed "$HOME/.gitconfig.internal.local" \
    "$(_pre_swap git/.gitconfig 'gitconfig.internal.local' | _internal_credential_sections)"

[ "$failed" -eq 0 ] || exit 1
[ "$apply" -eq 1 ] || ux_info "Dry-run only. Re-run with --apply to write."
