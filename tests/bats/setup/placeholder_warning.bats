#!/usr/bin/env bats
# tests/bats/setup/placeholder_warning.bats
# Issue #2021 — setup warns for every variable of a copied *.local.example
# template that still holds a fake value (domain and non-domain alike), names
# the variables, and never prints their values. Fake values only.

load '../test_helper'

setup() {
    setup_isolated_home
    FX="$TEST_TEMP_HOME/dotfiles"
    ENV_DIR="$FX/shell-common/env"
    mkdir -p "$ENV_DIR" "$FX/shell-common/tools/ux_lib"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" "$FX/shell-common/"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" "$FX/shell-common/tools/ux_lib/"
}

teardown() {
    teardown_isolated_home
}

warn_for() {
    run bash --noprofile --norc -c "
        cd '$FX/shell-common'
        . './setup.sh'
        _warn_if_placeholder '$1'
    " </dev/null
}

@test "verbatim internal template: every fake-valued variable is named" {
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/internal.local.example" "$ENV_DIR/internal.local.sh"
    warn_for "$ENV_DIR/internal.local.sh"
    assert_success
    for v in DOTFILES_GHES_HOST DOTFILES_SSH_KEY_NAME DOTFILES_CLAUDE_USAGE_API_URL \
        DOTFILES_CLAUDE_USAGE_ID DOTFILES_AWS_BEDROCK_URL DOTFILES_AWS_SSO_START_URL \
        DOTFILES_AWS_SSO_ACCOUNT_ID DOTFILES_INTERNAL_DOMAIN DOTFILES_PROXY_CA_FINGERPRINT \
        DOTFILES_OTEL_ENDPOINT_HOST DOTFILES_OTEL_NO_PROXY_DOMAINS \
        DOTFILES_OPENCODE_BASE_URL DOTFILES_OPENCODE_REVIEW_MODEL; do
        assert_output --partial "$v"
    done
    refute_output --partial "id_rsa_example"
    refute_output --partial "example.invalid"
}

@test "only the unchanged variables are listed" {
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/internal.local.example" "$ENV_DIR/internal.local.sh"
    sed -i -e 's/ghes\.example\.invalid/ghes.corp-fake.test/' "$ENV_DIR/internal.local.sh"
    warn_for "$ENV_DIR/internal.local.sh"
    refute_output --partial "DOTFILES_GHES_HOST"
    assert_output --partial "DOTFILES_SSH_KEY_NAME"
}

@test "a fully filled-in file produces no warning" {
    cat >"$ENV_DIR/internal.local.sh" <<'EOT'
export DOTFILES_GHES_HOST="ghes.corp-fake.test"
export DOTFILES_SSH_KEY_NAME="id_fake_key"
export DOTFILES_CLAUDE_USAGE_ID="EMP12345"
export DOTFILES_AWS_SSO_ACCOUNT_ID="123456789012"
export DOTFILES_OPENCODE_REVIEW_MODEL="corp-fake/model-x"
EOT
    warn_for "$ENV_DIR/internal.local.sh"
    assert_success
    refute_output --partial "placeholder"
}
