#!/bin/sh
# shell-common/tools/integrations/obsidian.sh
# Obsidian launcher (POSIX-compatible).
#
# Path resolution order for `obsidian`:
#   1. $OBSIDIAN_BIN   (explicit override)
#   2. Latest Obsidian-*.AppImage under $OBSIDIAN_HOME (default ~/application)
#   3. ~/application/Obsidian-1.8.10.AppImage (legacy hard-coded default)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_obsidian_resolve_bin() {
    if [ -n "${OBSIDIAN_BIN-}" ]; then
        printf "%s" "$OBSIDIAN_BIN"
        return 0
    fi
    _ob_home="${OBSIDIAN_HOME:-$HOME/application}"
    # Pick the latest Obsidian-*.AppImage. Globs expand alphabetically — keep
    # the LAST executable match so `Obsidian-1.8.10` wins over `Obsidian-1.7.0`
    # (gemini PR #520 review).
    _ob_found=""
    for _ob_app in "$_ob_home"/Obsidian-*.AppImage; do
        if [ -x "$_ob_app" ]; then
            _ob_found="$_ob_app"
        fi
    done
    if [ -n "$_ob_found" ]; then
        printf "%s" "$_ob_found"
        unset _ob_home _ob_app _ob_found
        return 0
    fi
    unset _ob_home _ob_app _ob_found
    printf "%s" "$HOME/application/Obsidian-1.8.10.AppImage"
}

obsidian() {
    _ob_bin=$(_obsidian_resolve_bin)
    if [ ! -x "$_ob_bin" ]; then
        if type ux_warning >/dev/null 2>&1; then
            ux_warning "obsidian binary not found at: $_ob_bin"
            ux_info "Set \$OBSIDIAN_BIN or place AppImage under \$OBSIDIAN_HOME (default ~/application)."
        else
            printf 'obsidian: binary not found at %s\n' "$_ob_bin" >&2
            # shellcheck disable=SC2016 # literal var names shown to the user
            printf 'Set $OBSIDIAN_BIN or place AppImage under $OBSIDIAN_HOME (default ~/application).\n' >&2
        fi
        unset _ob_bin
        return 1
    fi
    "$_ob_bin" "$@"
    _ob_rc=$?
    unset _ob_bin
    return "$_ob_rc"
}
