#!/usr/bin/env bats
# tests/bats/skills/ssh_delegate/test_install_dry_run.bats
# The --dry-run guard must mutate nothing: no manifest, no remote ssh-copy-id,
# no config drop-in. Also covers the lib-level dry-run command rendering.

load '../../test_helper'

SKILL_DIR="${DOTFILES_ROOT}/claude/skills/devx-ssh-delegate"
SKILL_LIB="${SKILL_DIR}/lib"
DELEGATE="${SKILL_DIR}/lib/ssh_delegate.sh"

setup() {
    setup_isolated_home
    export DEVX_SSH_MANIFEST="${TEST_TEMP_HOME}/delegations.yml"
    export DEVX_SSH_CONFIG="${TEST_TEMP_HOME}/ssh_config"
    export DEVX_SSH_CONFIG_DROPIN="${TEST_TEMP_HOME}/ssh_config.d/devx-delegations"
    export DEVX_SSH_AUDIT_LOG="${TEST_TEMP_HOME}/audit.log"
}

teardown() { teardown_isolated_home; }

@test "add --dry-run prints the ssh-copy-id command" {
    run "$DELEGATE" add bwyoon@12.81.221.129 gpu1-bwyoon --dry-run
    assert_success
    assert_output --partial 'ssh-copy-id'
    assert_output --partial 'bwyoon@12.81.221.129'
    # identity path must be tilde-expanded, never a literal /~/ segment
    refute_output --partial '/~/'
}

@test "add --dry-run creates no manifest, no config, no audit log" {
    run "$DELEGATE" add bwyoon@12.81.221.129 gpu1-bwyoon --dry-run
    assert_success
    assert [ ! -f "$DEVX_SSH_MANIFEST" ]
    assert [ ! -f "$DEVX_SSH_CONFIG_DROPIN" ]
    assert [ ! -f "$DEVX_SSH_AUDIT_LOG" ]
}

@test "add with a malformed target exits 2" {
    run "$DELEGATE" add notanemail
    assert_failure 2
}

@test "ssh_install_copy_id --dry-run renders without an installed pubkey" {
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/ux.sh"; . "${SKILL_LIB}/manifest.sh"
    . "${SKILL_LIB}/ssh_config.sh"; . "${SKILL_LIB}/install.sh"
    manifest_ensure
    manifest_upsert gpu1-bwyoon bwyoon 12.81.221.129 '' ''
    run ssh_install_copy_id gpu1-bwyoon --dry-run
    assert_success
    assert_output --partial '-p 22'
    assert_output --partial 'bwyoon@12.81.221.129'
}

@test "default alias is derived from user + dotted host when omitted" {
    run "$DELEGATE" add deity@10.0.0.9 --dry-run
    assert_success
    assert_output --partial 'deity-10-0-0-9'
}
