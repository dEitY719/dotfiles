#!/usr/bin/env bats
# tests/bats/scripts/remove_git_crypt_local_config.bats
# Validate scripts/remove-git-crypt-local-config.sh (#2345): it deletes the
# leftover filter.git-crypt / diff.git-crypt sections from the repo-local
# .git/config and always exits 0. The script edits the config of the repo it
# lives in, so it only ever runs from a copy inside a mktemp fixture repo --
# never the real checkout.

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/scripts/remove-git-crypt-local-config.sh"

setup() {
    setup_isolated_home
    FIXTURE="$(mktemp -d)"
    mkdir -p "$FIXTURE/repo/scripts" "$FIXTURE/repo/shell-common/tools/ux_lib"
    cp "$SCRIPT_UNDER_TEST" "$FIXTURE/repo/scripts/"
    cp "${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh" \
        "$FIXTURE/repo/shell-common/tools/ux_lib/"
    git -C "$FIXTURE/repo" init -q
    FIXTURE_SCRIPT="$FIXTURE/repo/scripts/remove-git-crypt-local-config.sh"
}

teardown() {
    cd /
    [ -n "$FIXTURE" ] && rm -rf "$FIXTURE"
    teardown_isolated_home
}

_seed_git_crypt_sections() {
    git -C "$FIXTURE/repo" config filter.git-crypt.smudge cat
    git -C "$FIXTURE/repo" config filter.git-crypt.clean cat
    git -C "$FIXTURE/repo" config filter.git-crypt.required false
    git -C "$FIXTURE/repo" config diff.git-crypt.textconv cat
}

@test "remove-git-crypt-local-config: deletes both sections when present" {
    _seed_git_crypt_sections
    git -C "$FIXTURE/repo" config user.name keep-me

    run bash "$FIXTURE_SCRIPT"
    assert_success

    run git -C "$FIXTURE/repo" config --local --get-regexp 'git-crypt'
    assert_failure
    assert_output ""
    # Unrelated local config survives.
    run git -C "$FIXTURE/repo" config --local user.name
    assert_output "keep-me"
}

@test "remove-git-crypt-local-config: rerun after removal exits 0" {
    _seed_git_crypt_sections
    run bash "$FIXTURE_SCRIPT"
    assert_success
    run bash "$FIXTURE_SCRIPT"
    assert_success
}

@test "remove-git-crypt-local-config: exits 0 when sections are absent" {
    run bash "$FIXTURE_SCRIPT"
    assert_success
    run git -C "$FIXTURE/repo" config --local --get-regexp 'git-crypt'
    assert_output ""
}
