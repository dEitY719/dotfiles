#!/usr/bin/env bats
# tests/bats/lint/setup_steps.bats
# Issue #2142 — scripts/lint_setup_steps.sh 회귀 가드.
# 모듈 setup.sh 는 root setup.sh main() 에 등록되거나 <module>/.setup-optin 을 가져야 한다.

load '../test_helper'

LINTER="${_BATS_REAL_DOTFILES_ROOT}/scripts/lint_setup_steps.sh"

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/alpha" "$REPO/beta"
    git -C "$REPO" init -q
    cat >"$REPO/setup.sh" <<'EOF'
main() {
    # step_run beta optional ./beta/setup.sh  (comment: not a registration)
    step_run alpha critical ./alpha/setup.sh # trailing comment: not ./beta/setup.sh
}
EOF
    touch "$REPO/alpha/setup.sh" "$REPO/beta/setup.sh"
    git -C "$REPO" add setup.sh alpha/setup.sh beta/setup.sh
}

run_linter() {
    cd "$REPO" && run sh "$LINTER"
}

@test "unregistered module without .setup-optin fails" {
    run_linter
    assert_failure 1
    assert_output --partial "FAIL  beta"
    assert_output --partial "checked=2 errors=1"
}

@test "unregistered module with .setup-optin passes and prints the reason" {
    echo "manual install" >"$REPO/beta/.setup-optin"
    run_linter
    assert_success
    assert_output --partial "info  beta — opt-in: manual install"
    assert_output --partial "checked=2 errors=0"
}

@test "registered module with .setup-optin fails as a contradiction" {
    echo "manual install" >"$REPO/beta/.setup-optin"
    echo "x" >"$REPO/alpha/.setup-optin"
    run_linter
    assert_failure 1
    assert_output --partial "FAIL  alpha"
    assert_output --partial "모순"
}

@test "a path that only ends in ./<module>/setup.sh is not a registration" {
    echo "manual install" >"$REPO/beta/.setup-optin"
    sed -i 's#\./alpha/setup\.sh#../alpha/setup.sh#' "$REPO/setup.sh"
    run_linter
    assert_failure 1
    assert_output --partial "FAIL  alpha"
}

@test "an empty module list fails instead of passing silently" {
    git -C "$REPO" rm -q --cached alpha/setup.sh beta/setup.sh
    run_linter
    assert_failure 1
    assert_output --partial "checked=0"
}

@test "real tree passes" {
    cd "$_BATS_REAL_DOTFILES_ROOT" && run sh "$LINTER"
    assert_success
    assert_output --partial "graphify — opt-in"
}
