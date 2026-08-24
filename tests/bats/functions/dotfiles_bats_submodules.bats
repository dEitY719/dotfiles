#!/usr/bin/env bats
# tests/bats/functions/dotfiles_bats_submodules.bats
# Regression guard for issue #1398 — a fresh `git clone` never initializes
# the bats-core/bats-support/bats-assert submodules, so onboarding must
# fetch them for the developer instead of leaving ./tests/test to silently
# skip all bats coverage.

load '../test_helper'

HELPER="${DOTFILES_ROOT}/shell-common/functions/dotfiles_bats_submodules.sh"

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "$HELPER"

    FAKE_REPO="$(mktemp -d "${TMPDIR:-/tmp}/bats-submod-test.XXXXXX")"
    FAKE_BIN="$(mktemp -d "${TMPDIR:-/tmp}/bats-submod-bin.XXXXXX")"
    GIT_LOG="${FAKE_BIN}/git.log"
    cat >"${FAKE_BIN}/git" <<EOF
#!/bin/sh
echo "\$@" >> "${GIT_LOG}"
exit 0
EOF
    chmod +x "${FAKE_BIN}/git"
    PATH="${FAKE_BIN}:${PATH}"
}

teardown() {
    rm -rf "$FAKE_REPO" "$FAKE_BIN"
    teardown_isolated_home
}

@test "dotfiles_ensure_bats_submodules: runs git submodule update --init --recursive scoped to tests/bats/lib" {
    mkdir -p "${FAKE_REPO}/.git"
    run dotfiles_ensure_bats_submodules "$FAKE_REPO"
    assert_success
    assert_equal "$(cat "$GIT_LOG")" "-C ${FAKE_REPO} submodule update --init --recursive tests/bats/lib"
}

@test "dotfiles_ensure_bats_submodules: no-ops outside a git checkout" {
    run dotfiles_ensure_bats_submodules "$FAKE_REPO"
    assert_success
    [ ! -f "$GIT_LOG" ]
}
