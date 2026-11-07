#!/bin/bash
# shell-common/tools/custom/bats.sh
# Run the dotfiles-vendored bats-core from PATH, with its helper libraries
# on BATS_LIB_PATH (#2361).
#
# PATH executable (~/.local/bin/bats via config/symlinks.conf) so agents and
# scripts find bats with `command -v bats` instead of judging it missing.
# The dotfiles root comes from resolving this script's own symlink, so it is
# whichever checkout setup.sh ran from (run setup.sh from ~/dotfiles, not a
# worktree, or the link dangles once the worktree is removed). A bats
# installed earlier on PATH still wins.
# readlink -f: GNU coreutils / macOS 12.3+, same as the sibling tools.
#
# BATS_LIB_PATH gets <root>/tests/bats/lib prepended (any existing value is
# kept after it), so `bats_load_library bats-assert` works from any directory.
# No other variable is exported: the tests see the caller's environment.
#
# Usage: bats [bats-core args...]   (all args go to bats-core unchanged)

main() {
    local self root lib bin
    self="$(readlink -f "${BASH_SOURCE[0]}")"
    # Three levels up from shell-common/tools/custom, whatever the file name.
    root="$(cd "${self%/*}/../../.." && pwd -P)"
    lib="${root}/tests/bats/lib"
    bin="${lib}/bats-core/bin/bats"

    if [ ! -x "$bin" ]; then
        # Error path only: ux_lib is sourced here so the success path leaks
        # no shell state into the tests.
        # shellcheck source=/dev/null
        . "${root}/shell-common/tools/ux_lib/ux_lib.sh" 2>/dev/null
        command -v ux_error >/dev/null ||
            ux_error() { printf 'Error: %s\n' "$1" >&2; }
        ux_error "bats: vendored bats-core not found at ${bin}"
        ux_error "bats: run: git -C ${root} submodule update --init --recursive tests/bats/lib"
        exit 1
    fi

    export BATS_LIB_PATH="${lib}${BATS_LIB_PATH:+:${BATS_LIB_PATH}}"
    exec "$bin" "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
