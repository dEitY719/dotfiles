#!/usr/bin/env bats
# tests/bats/functions/setup_local_files.bats
# shell-common/setup.sh must never clobber real values in a *.local.sh (#1969):
# the tracked *.local.example templates now hold fake placeholders only, so a
# lost local file could not be regenerated. Fake values only in this file.

load '../test_helper'

setup() {
    setup_isolated_home

    FIXTURE_DOTFILES="$TEST_TEMP_HOME/dotfiles"
    ENV_DIR="$FIXTURE_DOTFILES/shell-common/env"
    mkdir -p "$ENV_DIR" "$FIXTURE_DOTFILES/shell-common/tools/ux_lib"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" \
       "$FIXTURE_DOTFILES/shell-common/setup.sh"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" \
       "$FIXTURE_DOTFILES/shell-common/tools/ux_lib/ux_lib.sh"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/proxy.local.example" \
       "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/security.local.example" \
       "$ENV_DIR/"
}

teardown() {
    teardown_isolated_home
}

# Source setup.sh (direct-exec guard skips main) and run the given functions.
run_setup_fn() {
    run bash --noprofile --norc -c "
        set -e
        cd '$FIXTURE_DOTFILES/shell-common'
        . './setup.sh'
        $*
    " </dev/null
}

@test "existing local file is kept byte-identical" {
    printf 'export http_proxy="http://real-proxy.test:3128"\n' >"$ENV_DIR/proxy.local.sh"
    cp "$ENV_DIR/proxy.local.sh" "$TEST_TEMP_HOME/expected"

    run_setup_fn copy_local_files internal
    assert_success
    assert_output --partial "Kept existing: env/proxy.local.sh"
    cmp "$ENV_DIR/proxy.local.sh" "$TEST_TEMP_HOME/expected"
}

@test "cleanup then install (mode re-run) restores real values, not the template" {
    printf 'export http_proxy="http://real-proxy.test:3128"\n' >"$ENV_DIR/proxy.local.sh"
    cp "$ENV_DIR/proxy.local.sh" "$TEST_TEMP_HOME/expected"

    run_setup_fn cleanup_local_files
    assert_success
    [ ! -f "$ENV_DIR/proxy.local.sh" ]

    run_setup_fn copy_local_files internal
    assert_success
    assert_output --partial "Restored: env/proxy.local.sh"
    cmp "$ENV_DIR/proxy.local.sh" "$TEST_TEMP_HOME/expected"
    [ ! -f "$ENV_DIR/proxy.backup.local.sh" ]
}

@test "fresh template copy warns that placeholders must be filled in" {
    run_setup_fn copy_local_files internal
    assert_success
    assert_output --partial "Created: env/proxy.local.sh"
    assert_output --partial "env/proxy.local.sh still has placeholder values"
    assert_output --partial "env/security.local.sh still has placeholder values"
}

@test "external mode leaves a moved-aside proxy backup alone" {
    printf 'export http_proxy="http://real-proxy.test:3128"\n' >"$ENV_DIR/proxy.local.sh"
    run_setup_fn cleanup_local_files
    run_setup_fn copy_local_files external
    assert_success
    [ ! -f "$ENV_DIR/proxy.local.sh" ]
    [ -f "$ENV_DIR/proxy.backup.local.sh" ]
}

@test "security toggles work on the placeholder template paths" {
    cp "$ENV_DIR/security.local.example" "$ENV_DIR/security.local.sh"
    run_setup_fn setup_security_config external
    assert_success
    grep -q '^CA_CERT="/usr/local/share/ca-certificates/example-ca.crt"' "$ENV_DIR/security.local.sh"
    grep -q '^SSL_CERT_FILE="/usr/local/share/' "$ENV_DIR/security.local.sh"

    run_setup_fn setup_security_config internal
    assert_success
    grep -q '^CA_CERT="/etc/ssl/certs/ca-certificates.crt"' "$ENV_DIR/security.local.sh"
    grep -q '^SSL_CERT_FILE="/usr/share/ca-certificates/' "$ENV_DIR/security.local.sh"
}

@test "tracked env templates carry only placeholder hosts" {
    run grep -E '^export (http_proxy|https_proxy)=' \
        "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/proxy.local.example"
    assert_success
    ! printf '%s\n' "$output" | grep -v 'proxy\.example\.invalid'
}
