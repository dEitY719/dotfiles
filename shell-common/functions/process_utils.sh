#!/bin/sh
# shell-common/functions/process_utils.sh
# Process management utilities

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# zsh-compat: psgrep uses `local` (bash/zsh extension), `local` itself is fine
# in zsh but mixed with `ps aux | grep` pipes the variable-assignment tracing
# is noisier in zsh under `set -x`. Stay safe.
[ -n "${ZSH_VERSION-}" ] && emulate -L sh 2>/dev/null

_psgrep_help() {
    if type ux_usage >/dev/null 2>&1; then
        ux_usage "ps-grep" "<pattern>" "Find a running process by name"
        ux_bullet "Example: ps-grep claude"
    else
        echo "Usage: ps-grep <pattern>"
        echo "Example: ps-grep claude"
    fi
}

psgrep() {
    local pattern="${1:-}"

    case "$pattern" in
        ""|-h|--help|help)
            _psgrep_help
            [ -z "$pattern" ] && return 1
            return 0
            ;;
    esac

    local matches
    # shellcheck disable=SC2009 # `ps-grep` semantics deliberately mirror `ps aux | grep`
    matches=$(ps aux | grep "$pattern" | grep -v grep || true)

    if [ -z "$matches" ]; then
        if type ux_info >/dev/null 2>&1; then
            ux_info "No process matched: $pattern"
        else
            echo "No process matched: $pattern"
        fi
        return 1
    fi
    printf '%s\n' "$matches"
}

alias ps-grep='psgrep'
