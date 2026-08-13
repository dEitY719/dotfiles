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

@test "wrapper preserves spaced arguments when invoking python helper" {
    export SHELL_COMMON="$TEST_TEMP_HOME/shell-common"
    export TEST_TEMP_HOME
    mkdir -p "$SHELL_COMMON/functions"
    mkdir -p "$TEST_TEMP_HOME/bin"
    export PATH="$TEST_TEMP_HOME/bin:$PATH"

    cat <<'EOF' > "$TEST_TEMP_HOME/bin/python3"
#!/bin/sh
printf '%s\n' "$@" > "${TEST_TEMP_HOME}/python3.args"
printf '{"result":"unverified","layer":"backend","reason":"captured"}\n'
EOF
    chmod +x "$TEST_TEMP_HOME/bin/python3"

    cat <<'EOF' > "$SHELL_COMMON/functions/devx_pr_verify_live_backend_identity.py"
#!/bin/sh
exit 0
EOF
    chmod +x "$SHELL_COMMON/functions/devx_pr_verify_live_backend_identity.py"

    run devx_pr_verify_live_backend_identity \
        --repo-root "/tmp/repo with space" \
        --target-repo "foo/bar" \
        --target-sha "abc 123" \
        --base-url "http://localhost:3000/path with space" \
        --backend-ports "8000, 8001" \
        --container-name "api service"

    assert_success
    assert_output --partial '"reason":"captured"'
    run cat "$TEST_TEMP_HOME/python3.args"
    assert_success
    assert_output --partial "$SHELL_COMMON/functions/devx_pr_verify_live_backend_identity.py"
    assert_output --partial "/tmp/repo with space"
    assert_output --partial "abc 123"
    assert_output --partial "http://localhost:3000/path with space"
    assert_output --partial "8000, 8001"
    assert_output --partial "api service"
}
