#!/usr/bin/env bats
# tests/bats/tools/symlink_manager.bats
# symlinks.conf sources must resolve to the same physical dotfiles root that
# ssh/setup.sh links to. symlinks.conf used to hardcode ${HOME}/dotfiles, so on
# a PC whose checkout is elsewhere (or reached through a symlink) running
# `symlink-manager init` and ./setup.sh rewrote ~/.ssh/config back and forth.

load '../test_helper'

MANAGER="${DOTFILES_ROOT}/shell-common/tools/custom/symlink-manager.sh"

setup() {
    setup_isolated_home
    REAL_ROOT="$(cd "$DOTFILES_ROOT" && pwd -P)"
    # Reach the checkout through a symlink, as on a PC with ~/dotfiles -> repo.
    ln -s "$REAL_ROOT" "$HOME/dotlink"
}

teardown() {
    teardown_isolated_home
}

_ssh_link() { readlink "$HOME/.ssh/config"; }

@test "symlinks.conf: no hardcoded \${HOME}/dotfiles sources" {
    run grep -c '[$][{]HOME[}]/dotfiles' "${DOTFILES_ROOT}/shell-common/config/symlinks.conf"
    assert_output "0"
}

@test "ssh/setup.sh and symlink-manager agree: ~/.ssh/config never flaps" {
    run bash "$HOME/dotlink/ssh/setup.sh"
    assert_success
    first="$(_ssh_link)"
    [ "$first" = "$REAL_ROOT/ssh/config" ]

    run env -u DOTFILES_TEST_MODE DOTFILES_ROOT="$HOME/dotlink" bash "$HOME/dotlink/shell-common/tools/custom/symlink-manager.sh" init
    assert_success
    [ "$(_ssh_link)" = "$first" ]

    run bash "$HOME/dotlink/ssh/setup.sh"
    assert_success
    assert_output --partial "Symlink already correct"
    [ "$(_ssh_link)" = "$first" ]
}

@test "symlink-manager init twice: second run changes nothing" {
    run env -u DOTFILES_TEST_MODE bash "$MANAGER" init
    assert_success
    before="$(find "$HOME" -maxdepth 4 -type l -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \; | sort)"
    run env -u DOTFILES_TEST_MODE bash "$MANAGER" init
    assert_success
    refute_output --partial "Updating symlink"
    after="$(find "$HOME" -maxdepth 4 -type l -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \; | sort)"
    [ "$before" = "$after" ]
    [[ "$after" == *".tmux.conf -> $REAL_ROOT/tmux/tmux.conf"* ]]
}
