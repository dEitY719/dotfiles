#!/bin/bash
# shell-common/tools/custom/psgrep.sh
# Process management utilities
#
# PATH executable since #2195 (~/.local/bin/ps-grep via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'ps-grep'` resolves it.
# functions/process_utils.sh keeps the `psgrep` / `ps-grep` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

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
    # zsh-compat: `emulate -L sh` is only valid inside a function. The earlier
    # top-level invocation was silently a no-op (gemini #524 review).
    [ -n "${ZSH_VERSION:-}" ] && emulate -L sh

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
    # grep -vF "$0": as an executable, this script's own command line holds the pattern.
    matches=$(ps aux | grep "$pattern" | grep -v grep | grep -vF -- "$0" || true)

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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    psgrep "$@"
fi
