#!/usr/bin/env bash
# git/hooks/checks/interactive_guard_check.sh
#
# Auto-sourced shell-common files start with the interactive guard
#   case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# within their first 10 lines (AGENTS.md, shell-common/AGENTS.md #1877).
# Exception, as #1877 states it: a file without the guard says why in a header
# comment naming the "interactive guard" (pure function libraries such as
# gh_host.sh, mount.sh's functions above the guard). tools/custom/ is out of
# scope: those scripts are executed, not sourced.

check_interactive_guard() { # <abs_path> <repo_rel_path> <out>
    head -n 10 "$1" | grep -q 'case \$- in \*i\*)' && return 0
    head -n 30 "$1" | grep -qiE '^[[:space:]]*#.*interactive guard' && return 0
    echo "$2: no 'case \$- in *i*)' guard in the first 10 lines and no header comment explaining its absence" >>"$3"
    return 1
}

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
CHECK_NAME=interactive_guard
CHECK_SCOPE=per-file
CHECK_SEVERITY=warning
CHECK_TITLE="Missing interactive guard"
CHECK_REPORT_LINES=5
check_run() {
    case "$3" in
    shell-common/aliases/*.sh | shell-common/env/*.sh | shell-common/functions/*.sh | shell-common/tools/integrations/*.sh) ;;
    *) return 0 ;;
    esac
    [ -f "$1/$3" ] || return 0
    check_interactive_guard "$1/$3" "$3" "$4"
}
