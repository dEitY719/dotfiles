#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/util/loader.sh
# Category module loader — the single loading core for bash/main.bash and
# zsh/main.zsh (#2134). Sourced by util/bootstrap.sh after safe_source.sh.
#
# Usage:
#   load_category "env"                            # shell-common/env/*.sh
#   load_category "integrations" "${SHELL_COMMON}/tools"
#   dotfiles_load_all                              # every category, in order

# Direct-exec guard: This file should be sourced, not executed

if [ "${0##*/}" != "loader.sh" ] && [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This file should be sourced, not executed directly" >&2
    exit 1
fi

# Configuration
LOADER_DEBUG="${DEBUG_DOTFILES:-0}"

# Load all .sh files from a category directory through safe_source, so the
# #1454/#1504 stderr policy and SOURCED_FILES_COUNT apply to every file.
load_category() {
    local category="$1"
    local base_dir="${2:-${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}}"
    local category_dir="${base_dir}/${category}"
    local f _nullglob_off=0

    if [ ! -d "$category_dir" ]; then
        if [ "$LOADER_DEBUG" = "1" ]; then
            echo "DEBUG: Category directory not found: $category_dir" >&2
        fi
        return 1
    fi

    if [ "$LOADER_DEBUG" = "1" ]; then
        echo "DEBUG: Loading category: $category from $category_dir" >&2
    fi

    # zsh: an empty category must not abort with "no matches found". nullglob
    # is on only while the glob expands (not via localoptions), so it neither
    # leaks into the sourced files nor reverts a `setopt` they run.
    if [ -n "${ZSH_VERSION-}" ] && ! [[ -o nullglob ]]; then
        _nullglob_off=1
        setopt nullglob
    fi
    set -- "${category_dir}"/*.sh
    [ "$_nullglob_off" = 1 ] && unsetopt nullglob

    for f in "$@"; do
        [ -f "$f" ] || continue

        # Skip .local.sh files (user overrides, not auto-loaded)
        case "$f" in
        *.local.sh) continue ;;
        esac

        safe_source "$f" "Failed to load ${category}" || true
    done
    return 0
}

# Remove *help functions (except my_help) before reloading, so stale help
# definitions do not persist across `src` reloads.
_dotfiles_clear_help_functions() {
    local _fn
    for _fn in $(
        if [ -n "${ZSH_VERSION-}" ]; then
            typeset +f
        else
            compgen -A function
        fi
    ); do
        case "$_fn" in
        my_help | run-help) ;; # run-help: zsh builtin autoload, not ours
        *help) unset -f "$_fn" 2>/dev/null ;;
        esac
    done
}

# Load every shell-common category in order:
#   env -> aliases -> functions -> integrations -> (help adapter) -> projects
# Shell-specific modules (bash/env, zsh/app) are the entry point's job and
# load AFTER this, so they can override the common values.
dotfiles_load_all() {
    _dotfiles_clear_help_functions
    load_category env
    load_category aliases
    load_category functions
    load_category integrations "${SHELL_COMMON}/tools"
    # Normalize help interfaces after all help providers are sourced.
    if command -v apply_help_standard_adapter >/dev/null 2>&1; then
        apply_help_standard_adapter
    fi
    load_category projects
    return 0
}

# Print the init summary in an interactive shell unless suppressed
# (DOTFILES_SUPPRESS_MESSAGE=1, set by zsh/zshrc). bash requires a TTY on
# stdout; zsh requires a TTY on stderr or a top-level shell.
dotfiles_show_init_summary() {
    case $- in *i*) ;; *) return 0 ;; esac
    [ "${DOTFILES_SUPPRESS_MESSAGE:-0}" = "1" ] && return 0
    command -v dotfiles_init_summary >/dev/null 2>&1 || return 0
    if [ -n "${ZSH_VERSION-}" ]; then
        [ -t 2 ] || [ -z "${ZSH_SUBSHELL-}" ] || return 0
    else
        [ -t 1 ] || return 0
    fi
    dotfiles_init_summary "$SOURCED_FILES_COUNT"
}
