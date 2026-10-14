#!/bin/sh
# shell-common/lib/setup/mode.sh — setup-mode resolution (#2137)
#
# Guard-free pure lib, POSIX sh, explicit source only (bootstrap: see
# common.sh). Lets setup steps receive the mode explicitly instead of
# re-reading the file another step wrote as a side effect.
#
# dotfiles_setup_mode_resolve [--mode <m>]
#   Prints public | internal | external, or "" when nothing is set.
#   Precedence: DOTFILES_SETUP_MODE env > --mode arg > ~/.dotfiles-setup-mode.
#   Accepts the legacy 1|2|3 aliases. Unknown value -> error, return 1.

: "${SHELL_COMMON:=${DOTFILES_ROOT:?export SHELL_COMMON or DOTFILES_ROOT before sourcing lib/setup}/shell-common}"
# shellcheck source=shell-common/lib/setup/common.sh
. "${SHELL_COMMON}/lib/setup/common.sh"
# shellcheck source=shell-common/util/setup_mode_read.sh
. "${SHELL_COMMON}/util/setup_mode_read.sh"

dotfiles_setup_mode_resolve() {
    _dsmr_arg=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode)
                # dash aborts the whole script on a shift past $#; guard it.
                [ $# -ge 2 ] || { ux_error "dotfiles_setup_mode_resolve: --mode needs a value"; return 2; }
                _dsmr_arg="$2" && shift
                ;;
            --mode=*) _dsmr_arg="${1#*=}" ;;
            *) ux_error "dotfiles_setup_mode_resolve: unknown option: $1"; return 2 ;;
        esac
        shift
    done
    # _dotfiles_setup_mode applies env > file and canonicalizes; --mode slots
    # in between by standing in for the file.
    if [ -z "${DOTFILES_SETUP_MODE-}" ] && [ -n "$_dsmr_arg" ]; then
        _dsmr_mode=$(DOTFILES_SETUP_MODE="$_dsmr_arg" _dotfiles_setup_mode)
    else
        _dsmr_mode=$(_dotfiles_setup_mode)
    fi
    case "$_dsmr_mode" in
        public | internal | external | "") printf '%s\n' "$_dsmr_mode" ;;
        *)
            ux_error "unknown setup mode: $_dsmr_mode (expected public|internal|external)"
            return 1
            ;;
    esac
}
