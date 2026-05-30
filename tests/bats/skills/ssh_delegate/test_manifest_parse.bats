#!/usr/bin/env bats
# tests/bats/skills/ssh_delegate/test_manifest_parse.bats
# Unit tests for the dependency-free manifest engine (lib/manifest.sh) used by
# the devx:ssh-delegate skill (#877). Covers parse (YAML -> fields), defaults,
# membership, upsert idempotency, and field mutation round-trip.

load '../../test_helper'

SKILL_LIB="${DOTFILES_ROOT}/claude/skills/devx-ssh-delegate/lib"

setup() {
    setup_isolated_home
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/ux.sh"
    # shellcheck source=/dev/null
    . "${SKILL_LIB}/manifest.sh"
    export DEVX_SSH_MANIFEST="${TEST_TEMP_HOME}/delegations.yml"
    cat >"$DEVX_SSH_MANIFEST" <<'YML'
version: 1
defaults:
  identity_file: ~/.ssh/id_ed25519
  port: 22
  strict_host_key_checking: yes
entries:
  - alias: gpu1-bwyoon
    user: bwyoon
    host: 12.81.221.129
    note: "Internal GPU box — bwyoon account"
    expires: 2026-08-30
    fingerprint_sha256: SHA256:abcd
    revoked: false
  - alias: gpu1-ssai
    user: ssai
    host: 12.81.221.129
    revoked: true
YML
}

teardown() { teardown_isolated_home; }

@test "manifest_aliases lists every entry alias" {
    run manifest_aliases
    assert_success
    assert_line 'gpu1-bwyoon'
    assert_line 'gpu1-ssai'
}

@test "manifest_get reads simple + quoted fields" {
    run manifest_get gpu1-bwyoon user
    assert_output 'bwyoon'
    run manifest_get gpu1-bwyoon note
    assert_output 'Internal GPU box — bwyoon account'
    run manifest_get gpu1-bwyoon fingerprint_sha256
    assert_output 'SHA256:abcd'
}

@test "manifest_default reads the defaults block" {
    run manifest_default identity_file
    assert_output '~/.ssh/id_ed25519'
    run manifest_default port
    assert_output '22'
}

@test "manifest_has distinguishes present vs absent aliases" {
    run manifest_has gpu1-bwyoon
    assert_success
    run manifest_has nope
    assert_failure
}

@test "two distinct users on the same host coexist (alias is PK)" {
    run manifest_get gpu1-ssai host
    assert_output '12.81.221.129'
    run manifest_get gpu1-ssai revoked
    assert_output 'true'
}

@test "manifest_set_field round-trips through canonical YAML" {
    manifest_set_field gpu1-bwyoon last_verified_at '2026-05-31T00:00:00Z'
    run manifest_get gpu1-bwyoon last_verified_at
    assert_output '2026-05-31T00:00:00Z'
    # other fields survive the rewrite
    run manifest_get gpu1-bwyoon note
    assert_output 'Internal GPU box — bwyoon account'
    run manifest_get gpu1-ssai revoked
    assert_output 'true'
}

@test "manifest_upsert is idempotent for an existing alias (no dup row)" {
    manifest_upsert gpu1-bwyoon bwyoon 12.81.221.129 '' ''
    # Count in-process — a `bash -c` subshell would not see the sourced funcs.
    count="$(manifest_aliases | grep -c '^gpu1-bwyoon$')"
    assert_equal "$count" 1
}

@test "manifest_upsert updates host/note of an existing alias in one pass (#896)" {
    manifest_upsert gpu1-bwyoon bwyoon 10.9.9.9 'moved box' ''
    run manifest_get gpu1-bwyoon host
    assert_output '10.9.9.9'
    run manifest_get gpu1-bwyoon note
    assert_output 'moved box'
    # unrelated entry untouched
    run manifest_get gpu1-ssai revoked
    assert_output 'true'
    # still a single row
    count="$(manifest_aliases | grep -c '^gpu1-bwyoon$')"
    assert_equal "$count" 1
}

@test "manifest_upsert appends a brand-new entry" {
    manifest_upsert box2-deity deity 10.0.0.9 'lab box' 2026-12-31
    run manifest_has box2-deity
    assert_success
    run manifest_get box2-deity host
    assert_output '10.0.0.9'
    run manifest_get box2-deity revoked
    assert_output 'false'
}

@test "manifest_ensure creates a 0600 skeleton when absent" {
    rm -f "$DEVX_SSH_MANIFEST"
    manifest_ensure
    assert [ -f "$DEVX_SSH_MANIFEST" ]
    run stat -c '%a' "$DEVX_SSH_MANIFEST"
    assert_output '600'
}
