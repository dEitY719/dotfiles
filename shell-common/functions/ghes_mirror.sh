#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/ghes_mirror.sh
# ghes-mirror — wrapper (#2155) around the PATH executable
# tools/custom/ghes_mirror.sh (also ~/.local/bin/ghes-mirror). The wizard ends
# inside the new clone; only a function can move this shell there, so the
# executable writes the clone path to GHES_MIRROR_CD_FILE and this cds into it.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

ghes_mirror() {
    local _gm_exe="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"/tools/custom/ghes_mirror.sh
    local _gm_cd_file _gm_rc
    _gm_cd_file=$(mktemp) || return 1
    GHES_MIRROR_CD_FILE="$_gm_cd_file" "$_gm_exe" "$@"
    _gm_rc=$?
    if [ -s "$_gm_cd_file" ]; then
        cd "$(cat "$_gm_cd_file")" || _gm_rc=1
    fi
    command rm -f "$_gm_cd_file"
    return "$_gm_rc"
}

alias ghes-mirror='ghes_mirror'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_func ghes_mirror "Mirror a public repo to an internal GHES instance"
