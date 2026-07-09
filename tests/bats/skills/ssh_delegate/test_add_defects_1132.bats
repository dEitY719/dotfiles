#!/usr/bin/env bats
# tests/bats/skills/ssh_delegate/test_add_defects_1132.bats
# Issue #1132 — three `add` defects:
#   A (P0) a hand-written `Host` block's IdentityFile silently shadows the key
#          `add` installs; `add` must detect it via `ssh -G` and adopt it.
#   C (P1) `ssh-copy-id` in a non-interactive shell dies as a misleading
#          Permission denied; `add` must fail fast with guidance instead.
#   B (P2) `--key-only` installs the key without regenerating ssh config, for a
#          host that already has a working hand-written alias.

load '../../test_helper'

SKILL_DIR="${DOTFILES_ROOT}/claude/skills/devx-ssh-delegate"
SKILL_LIB="${SKILL_DIR}/lib"
DELEGATE="${SKILL_LIB}/ssh_delegate.sh"

setup() {
    setup_isolated_home
    export TEST_TEMP_HOME
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/ux.sh"
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/manifest.sh"
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/ssh_config.sh"
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/install.sh"

    export DEVX_SSH_MANIFEST="${TEST_TEMP_HOME}/delegations.yml"
    export DEVX_SSH_CONFIG="${TEST_TEMP_HOME}/ssh_config"
    export DEVX_SSH_CONFIG_DROPIN="${TEST_TEMP_HOME}/ssh_config.d/devx-delegations"
    export DEVX_SSH_AUDIT_LOG="${TEST_TEMP_HOME}/audit.log"
    # Fingerprint capture must never hit the network in tests.
    export DEVX_SSH_KEYSCAN_BIN=true

    STUB_BIN="${TEST_TEMP_HOME}/bin"
    mkdir -p "$STUB_BIN" "${TEST_TEMP_HOME}/.ssh"

    # Mock ssh: `-G` prints identityfile lines from $FAKE_SSH_G (space-separated
    # ~-paths); any other call (a BatchMode verify) exits $FAKE_SSH_RC.
    cat >"${STUB_BIN}/ssh" <<'SSH'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = "-G" ]; then
        for id in $FAKE_SSH_G; do printf 'identityfile %s\n' "$id"; done
        exit 0
    fi
done
exit "${FAKE_SSH_RC:-0}"
SSH
    chmod +x "${STUB_BIN}/ssh"
    export DEVX_SSH_BIN="${STUB_BIN}/ssh"

    # Mock ssh-copy-id: succeed without touching a remote.
    cat >"${STUB_BIN}/ssh-copy-id" <<'COPY'
#!/usr/bin/env bash
exit 0
COPY
    chmod +x "${STUB_BIN}/ssh-copy-id"
    export DEVX_SSH_COPY_ID_BIN="${STUB_BIN}/ssh-copy-id"
}

teardown() { teardown_isolated_home; }

# --- Defect A: ssh_config_conflicting_identity ------------------------------

@test "A: no conflict when our intended key is among the resolved identities" {
    export FAKE_SSH_G='~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa'
    run ssh_config_conflicting_identity somealias "${TEST_TEMP_HOME}/.ssh/id_ed25519"
    assert_failure # return 1 => no conflict
    assert_output ''
}

@test "A: conflict echoes the shadowing identity when ours is absent" {
    export FAKE_SSH_G='~/.ssh/id_rsa_ssai_bwyoon'
    run ssh_config_conflicting_identity ssai-dev "${TEST_TEMP_HOME}/.ssh/id_ed25519"
    assert_success # return 0 => conflict
    assert_output '~/.ssh/id_rsa_ssai_bwyoon'
}

@test "A: add adopts a pre-existing IdentityFile (installed key == connect key)" {
    export DEVX_SSH_ASSUME_TTY=1
    export FAKE_SSH_G='~/.ssh/id_rsa_ssai_bwyoon'
    : >"${TEST_TEMP_HOME}/.ssh/id_rsa_ssai_bwyoon.pub"
    run "$DELEGATE" add bwyoon@ssai-dev ssai-dev
    assert_success
    assert_output --partial 'adopted existing IdentityFile'
    run manifest_get ssai-dev identity_file
    assert_output '~/.ssh/id_rsa_ssai_bwyoon'
}

@test "A: fresh alias keeps the manifest default (no adoption)" {
    export DEVX_SSH_ASSUME_TTY=1
    export FAKE_SSH_G='~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa'
    : >"${TEST_TEMP_HOME}/.ssh/id_ed25519.pub"
    run "$DELEGATE" add deity@10.0.0.9 box
    assert_success
    refute_output --partial 'adopted existing IdentityFile'
    run manifest_get box identity_file
    assert_output '' # empty => falls back to the default id_ed25519
}

@test "A: dry-run surfaces the adoption warning + adopted key, mutates nothing" {
    export FAKE_SSH_G='~/.ssh/id_rsa_ssai_bwyoon'
    run "$DELEGATE" add bwyoon@ssai-dev ssai-dev --dry-run
    assert_success
    assert_output --partial 'would adopt it'
    assert_output --partial 'id_rsa_ssai_bwyoon.pub'
    assert [ ! -f "$DEVX_SSH_MANIFEST" ]
}

# --- Defect C: ssh_install_can_prompt + add fail-fast -----------------------

@test "C: can_prompt is true when DEVX_SSH_ASSUME_TTY=1" {
    export DEVX_SSH_ASSUME_TTY=1
    run ssh_install_can_prompt
    assert_success
}

@test "C: can_prompt is false when non-interactive with no askpass" {
    export DEVX_SSH_ASSUME_TTY=0
    unset SSH_ASKPASS SSH_ASKPASS_REQUIRE
    run ssh_install_can_prompt
    assert_failure
}

@test "C: can_prompt is true when a forced SSH_ASKPASS is configured" {
    export DEVX_SSH_ASSUME_TTY=0
    askpass="${TEST_TEMP_HOME}/askpass"
    printf '#!/bin/sh\necho pw\n' >"$askpass"
    chmod +x "$askpass"
    export SSH_ASKPASS="$askpass"
    export SSH_ASKPASS_REQUIRE=force
    run ssh_install_can_prompt
    assert_success
}

@test "C: add fails fast (exit 3) and mutates nothing without a TTY" {
    export DEVX_SSH_ASSUME_TTY=0
    unset SSH_ASKPASS SSH_ASKPASS_REQUIRE
    export FAKE_SSH_G='~/.ssh/id_ed25519'
    : >"${TEST_TEMP_HOME}/.ssh/id_ed25519.pub"
    run "$DELEGATE" add bwyoon@12.81.221.129 gpu1
    assert_failure 3
    assert_output --partial 'interactive terminal'
    assert [ ! -f "$DEVX_SSH_MANIFEST" ]
    assert [ ! -f "$DEVX_SSH_CONFIG_DROPIN" ]
}

# --- Defect B: --key-only ---------------------------------------------------

@test "B: --key-only installs the key but writes no ssh config drop-in" {
    export DEVX_SSH_ASSUME_TTY=1
    export FAKE_SSH_G='~/.ssh/id_ed25519'
    : >"${TEST_TEMP_HOME}/.ssh/id_ed25519.pub"
    run "$DELEGATE" add bwyoon@ssai-dev ssai-dev --key-only
    assert_success
    assert_output --partial '--key-only'
    assert [ ! -f "$DEVX_SSH_CONFIG_DROPIN" ]
    run manifest_has ssai-dev
    assert_success
}

@test "B: plain add (no --key-only) does regenerate the drop-in" {
    export DEVX_SSH_ASSUME_TTY=1
    export FAKE_SSH_G='~/.ssh/id_ed25519'
    : >"${TEST_TEMP_HOME}/.ssh/id_ed25519.pub"
    run "$DELEGATE" add bwyoon@ssai-dev ssai-dev
    assert_success
    assert [ -f "$DEVX_SSH_CONFIG_DROPIN" ]
}
