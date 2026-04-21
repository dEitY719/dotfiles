#!/usr/bin/env bash
# git/hooks/checks/main_branch_guard.sh
#
# Blocks commits on protected branches (main, master) to prevent
# accidental direct commits. Intended for workflows where all work
# happens on feature branches and lands on main via pull requests.
#
# Escape hatch:
#   ALLOW_MAIN_COMMIT=1 git commit ...
#
# Returns 0 if the current branch is allowed, 1 otherwise.

# check_main_branch_guard
#
# No arguments. Reads HEAD via `git symbolic-ref` to find current branch.
# Honors env var ALLOW_MAIN_COMMIT=1 as an escape hatch.
check_main_branch_guard() {
    # Escape hatch: user explicitly opted in.
    if [ "${ALLOW_MAIN_COMMIT:-0}" = "1" ]; then
        return 0
    fi

    local current_branch
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)

    # Detached HEAD (e.g. rebase, bisect) — nothing to guard.
    [ -z "$current_branch" ] && return 0

    case "$current_branch" in
        main | master)
            return 1
            ;;
    esac

    return 0
}
