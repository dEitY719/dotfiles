#!/usr/bin/env bash
# tests/bats/test_helper.bash
# Common helper for all bats tests.
# Provides environment isolation and dotfiles loading via subprocesses.

# Load bats libraries
_BATS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"
load "${_BATS_LIB_DIR}/bats-support/load"
load "${_BATS_LIB_DIR}/bats-assert/load"

# Project paths
export DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

# Frozen snapshot. setup_isolated_dotfiles_root overrides DOTFILES_ROOT for
# its caller's test body; setup_isolated_home / teardown_isolated_home use
# this snapshot to restore the real-tree value before/after each test so a
# stale override from the previous test cannot leak.
_BATS_REAL_DOTFILES_ROOT="$DOTFILES_ROOT"
_BATS_REAL_SHELL_COMMON="$SHELL_COMMON"

# Test isolation
export DOTFILES_TEST_MODE=1
export DOTFILES_FORCE_INIT=1

setup_isolated_home() {
    # Restore real DOTFILES_ROOT first — the previous test may have pointed
    # it at a (now-deleted) isolated tree via setup_isolated_dotfiles_root.
    export DOTFILES_ROOT="$_BATS_REAL_DOTFILES_ROOT"
    export SHELL_COMMON="$_BATS_REAL_SHELL_COMMON"

    TEST_TEMP_HOME="$(mktemp -d)"
    export HOME="$TEST_TEMP_HOME"
    export ZDOTDIR="$TEST_TEMP_HOME"
    export XDG_CONFIG_HOME="$TEST_TEMP_HOME"
    export XDG_CACHE_HOME="$TEST_TEMP_HOME"
    export XDG_DATA_HOME="$TEST_TEMP_HOME"
    export TERM=dumb
}

teardown_isolated_home() {
    if [ -n "$TEST_TEMP_HOME" ] && [ -d "$TEST_TEMP_HOME" ]; then
        rm -rf "$TEST_TEMP_HOME"
    fi
    export DOTFILES_ROOT="$_BATS_REAL_DOTFILES_ROOT"
    export SHELL_COMMON="$_BATS_REAL_SHELL_COMMON"
}

# Stage an isolated DOTFILES_ROOT for tests that invoke claude/setup.sh or
# write to ${DOTFILES_ROOT}/claude/. Without this, setup.sh leaves
# `settings.json.pre-statusline-fix-*` backup files in the version-controlled
# tree and fixture writes mutate the gitignored claude/settings.json — both
# survive interrupted runs (issue #303).
#
# Layout: $TEST_TEMP_HOME/dotfiles-iso/
#   bash, zsh, shell-common  → symlinks to real tree (read-only by tests)
#   claude/                  → real dir (mutable; setup.sh writes backups here)
#     setup.sh               → cp of real (NOT symlink — setup.sh resolves
#                              DOTFILES_ROOT via realpath of its own path,
#                              so a symlink would escape isolation)
#     statusline-command.sh, settings.template.json → symlinks (read-only)
#     settings.json          → cp of template (gitignored convention)
#     skills/, docs/, global-memory/ → empty dirs (satisfy setup.sh's
#                              `[ -d ]` source-existence guards)
#
# Side effect: re-exports DOTFILES_ROOT and SHELL_COMMON to point at the
# isolated tree. teardown_isolated_home restores the real values.
# Precondition: setup_isolated_home must have run (TEST_TEMP_HOME exists).
setup_isolated_dotfiles_root() {
    # Hard-fail if the precondition isn't met. Without this, an empty
    # TEST_TEMP_HOME makes `iso_root` resolve to `/dotfiles-iso` (system root).
    [ -n "$TEST_TEMP_HOME" ] || {
        echo "setup_isolated_dotfiles_root: TEST_TEMP_HOME not set — call setup_isolated_home first" >&2
        return 1
    }
    local real_root="$_BATS_REAL_DOTFILES_ROOT"
    local iso_root="$TEST_TEMP_HOME/dotfiles-iso"

    mkdir -p "$iso_root/claude"
    ln -s "$real_root/shell-common" "$iso_root/shell-common"
    ln -s "$real_root/bash" "$iso_root/bash"
    ln -s "$real_root/zsh" "$iso_root/zsh"

    cp "$real_root/claude/setup.sh" "$iso_root/claude/setup.sh"
    ln -s "$real_root/claude/statusline-command.sh"  "$iso_root/claude/statusline-command.sh"
    ln -s "$real_root/claude/settings.template.json" "$iso_root/claude/settings.template.json"

    mkdir -p "$iso_root/claude/skills" "$iso_root/claude/docs" "$iso_root/claude/global-memory"

    if [ -f "$iso_root/claude/settings.template.json" ]; then
        cp "$iso_root/claude/settings.template.json" "$iso_root/claude/settings.json"
    else
        echo '{}' > "$iso_root/claude/settings.json"
    fi

    export DOTFILES_ROOT="$iso_root"
    export SHELL_COMMON="$iso_root/shell-common"
}

# Run a command in bash subprocess with dotfiles loaded
run_in_bash() {
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        source '${DOTFILES_ROOT}/bash/main.bash'
        $1
    "
}

# Run a command in zsh subprocess with dotfiles loaded
run_in_zsh() {
    run zsh -f -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export ZDOTDIR='${HOME}'
        export TERM=dumb
        source '${DOTFILES_ROOT}/zsh/main.zsh'
        $1
    "
}
