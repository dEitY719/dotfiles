#!/usr/bin/env bats
# tests/bats/setup/install_stub.bats
# install.sh is a deprecated stub (#2131): it must point at ./setup.sh and exit
# non-zero under both bash and sh, so old callers never succeed silently.

load '../test_helper'

STUB="${_BATS_REAL_DOTFILES_ROOT}/install.sh"

@test "install.sh under bash: exit 2 with the setup.sh notice" {
    run bash "$STUB"
    [ "$status" -eq 2 ]
    [[ "$output" == *"install.sh 는 폐기됨"* ]]
    [[ "$output" == *"./setup.sh"* ]]
}

@test "install.sh under sh: exit 2 with the setup.sh notice" {
    run sh "$STUB"
    [ "$status" -eq 2 ]
    [[ "$output" == *"./setup.sh"* ]]
}

@test "install.sh stays executable" {
    [ -x "$STUB" ]
}
