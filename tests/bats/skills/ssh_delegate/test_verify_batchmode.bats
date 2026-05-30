#!/usr/bin/env bats
# tests/bats/skills/ssh_delegate/test_verify_batchmode.bats
# ssh_verify_alias must use BatchMode (never an interactive password) and
# refresh last_verified_at only on success. ssh is mocked via $DEVX_SSH_BIN.

load '../../test_helper'

SKILL_LIB="${DOTFILES_ROOT}/claude/skills/devx-ssh-delegate/lib"

setup() {
    setup_isolated_home
    export TEST_TEMP_HOME   # the ssh stub writes its argv under this path
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/ux.sh"; . "${SKILL_LIB}/manifest.sh"; . "${SKILL_LIB}/verify.sh"
    export DEVX_SSH_MANIFEST="${TEST_TEMP_HOME}/delegations.yml"
    manifest_ensure
    manifest_upsert gpu1-bwyoon bwyoon 12.81.221.129 '' ''

    # Mock ssh: record argv, exit per FAKE_SSH_RC.
    STUB_BIN="${TEST_TEMP_HOME}/bin"
    mkdir -p "$STUB_BIN"
    cat >"${STUB_BIN}/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${TEST_TEMP_HOME}/ssh_argv"
exit "${FAKE_SSH_RC:-0}"
SSH
    chmod +x "${STUB_BIN}/ssh"
    export DEVX_SSH_BIN="${STUB_BIN}/ssh"
}

teardown() { teardown_isolated_home; }

@test "verify succeeds and refreshes last_verified_at when ssh exits 0" {
    FAKE_SSH_RC=0 run ssh_verify_alias gpu1-bwyoon
    assert_success
    run manifest_get gpu1-bwyoon last_verified_at
    refute_output ''
}

@test "verify always passes BatchMode=yes (no password fallback)" {
    FAKE_SSH_RC=0 ssh_verify_alias gpu1-bwyoon
    run cat "${TEST_TEMP_HOME}/ssh_argv"
    assert_output --partial 'BatchMode=yes'
}

@test "verify fails and does not set last_verified_at when ssh exits 1" {
    FAKE_SSH_RC=1 run ssh_verify_alias gpu1-bwyoon
    assert_failure
    run manifest_get gpu1-bwyoon last_verified_at
    assert_output ''
}

@test "verify --dry-run prints the command and runs no ssh" {
    run ssh_verify_alias gpu1-bwyoon --dry-run
    assert_success
    assert_output --partial 'BatchMode=yes'
    assert [ ! -f "${TEST_TEMP_HOME}/ssh_argv" ]
}

@test "revoked alias is skipped by verify" {
    manifest_set_field gpu1-bwyoon revoked true
    FAKE_SSH_RC=0 run ssh_verify_alias gpu1-bwyoon
    assert_failure
}

@test "unknown alias is rejected before any ssh call (#896 review)" {
    FAKE_SSH_RC=0 run ssh_verify_alias nope-not-here
    assert_failure
    assert_output --partial 'not found in manifest'
    assert [ ! -f "${TEST_TEMP_HOME}/ssh_argv" ]
}
