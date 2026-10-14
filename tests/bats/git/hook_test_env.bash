# shellcheck shell=bash
# tests/bats/git/hook_test_env.bash
#
# Shared setup for the hook integration suites (test_hooks_*.bats,
# test_pre_push_hook.bats, #2163). Load after ../test_helper. Each test gets:
#   - an isolated HOME / XDG dirs (setup_isolated_home) and an empty global
#     git config, so a fixture commit never reads the user's ~/.gitconfig
#     (hooksPath, gpgsign, templateDir, ...) and nothing lands in the real HOME;
#   - no repo-locating vars git exports to hooks (a linked worktree's pre-push
#     sees an absolute GIT_DIR, which would point fixture `git -C <tmp>` calls
#     at the real repo), and no hook escape hatch / leak-guard config from the
#     caller, so an exported SKIP_LEAK_GUARD=1 cannot flip an expected verdict;
#   - mise shims (shellcheck, shfmt, ...) still resolvable after HOME moves.

hook_test_setup() {
    # Expanded before HOME moves: pin mise data/config/state (trust)/cache.
    export MISE_DATA_DIR="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
    export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}"
    export MISE_STATE_DIR="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}"
    export MISE_CACHE_DIR="${MISE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mise}"

    setup_isolated_home
    : >"$HOME/.gitconfig"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR \
        GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
        GIT_PREFIX GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT \
        SKIP_LEAK_GUARD SKIP_PRE_PUSH GIT_HOOKS_SKIP_GLOBAL \
        ALLOW_MAIN_COMMIT UPSTREAM_REMOTES_ERE LEAK_PATTERNS_ERE \
        PRE_PUSH_TEST PRE_PUSH_FULL_TEST
    # The cases were written for `set -euo pipefail`: bats already runs -e,
    # and -u stays off because bats' own code reads unset variables.
    set -o pipefail
}

hook_test_teardown() {
    teardown_isolated_home
}
