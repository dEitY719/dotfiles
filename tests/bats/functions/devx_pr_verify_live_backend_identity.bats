#!/usr/bin/env bats
# tests/bats/functions/devx_pr_verify_live_backend_identity.bats
# Unit tests for devx_pr_verify_live_backend_identity function.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_verify_live_backend_identity.sh"
}

teardown() {
    teardown_isolated_home
}

@test "help flag -> prints usage and exits 0" {
    run devx_pr_verify_live_backend_identity --help
    assert_success
    assert_output --partial "Usage: devx-pr-verify-live-backend-identity"
}

@test "missing required arguments -> exits 2" {
    run devx_pr_verify_live_backend_identity --repo-root /tmp
    assert_failure 2
    assert_output --partial "Usage: devx-pr-verify-live-backend-identity"
}

@test "unknown argument -> exits 2" {
    run devx_pr_verify_live_backend_identity --repo-root /tmp --target-repo foo/bar --target-sha abc --base-url http://localhost --unknown-flag
    assert_failure 2
}

@test "python helper missing -> falls back to outputting unverified JSON" {
    # Point SHELL_COMMON to an empty temp dir so helper path fails to locate
    export SHELL_COMMON="$TEST_TEMP_HOME/empty"
    mkdir -p "$SHELL_COMMON"

    run devx_pr_verify_live_backend_identity --repo-root /tmp --target-repo foo/bar --target-sha abc --base-url http://localhost
    assert_success
    assert_output --partial '"result": "unverified"'
    assert_output --partial "helper_script_missing"
}
