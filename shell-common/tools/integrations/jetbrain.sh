#!/bin/sh
# shell-common/tools/integrations/jetbrain.sh
# JetBrains IDE launcher aliases (POSIX-compatible).
#
# Path resolution order for `pycharm`:
#   1. $PYCHARM_BIN   (explicit override, e.g. `export PYCHARM_BIN=~/bin/pycharm`)
#   2. $JETBRAIN_HOME/pycharm-*/bin/pycharm (auto-discover most recent version)
#   3. ~/application/pycharm-2025.2.0.1/bin/pycharm (legacy hard-coded default)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_jetbrain_resolve_pycharm() {
    if [ -n "${PYCHARM_BIN-}" ]; then
        printf "%s" "$PYCHARM_BIN"
        return 0
    fi
    _jb_home="${JETBRAIN_HOME:-$HOME/application}"
    # Pick the most recent pycharm-* directory if any exists.
    # Globs expand alphabetically, so iterate and keep the LAST match —
    # `pycharm-2025.2.0.1` beats `pycharm-2024.1` that way. First-match would
    # pin us to the oldest version on disk (gemini PR #520 review).
    _jb_found=""
    for _jb_dir in "$_jb_home"/pycharm-*; do
        if [ -x "$_jb_dir/bin/pycharm" ]; then
            _jb_found="$_jb_dir/bin/pycharm"
        fi
    done
    if [ -n "$_jb_found" ]; then
        printf "%s" "$_jb_found"
        unset _jb_home _jb_dir _jb_found
        return 0
    fi
    unset _jb_home _jb_dir _jb_found
    printf "%s" "$HOME/application/pycharm-2025.2.0.1/bin/pycharm"
}

# Lazy resolution: re-evaluated on each invocation so a later $PYCHARM_BIN
# export still takes effect without re-sourcing this file.
pycharm() {
    _jb_bin=$(_jetbrain_resolve_pycharm)
    if [ ! -x "$_jb_bin" ]; then
        if type ux_warning >/dev/null 2>&1; then
            ux_warning "pycharm binary not found at: $_jb_bin"
            ux_info "Set \$PYCHARM_BIN or install under \$JETBRAIN_HOME (default ~/application)."
        else
            printf 'pycharm: binary not found at %s\n' "$_jb_bin" >&2
            # shellcheck disable=SC2016 # literal var names shown to the user
            printf 'Set $PYCHARM_BIN or install under $JETBRAIN_HOME (default ~/application).\n' >&2
        fi
        unset _jb_bin
        return 1
    fi
    "$_jb_bin" "$@"
    _jb_rc=$?
    unset _jb_bin
    return "$_jb_rc"
}
