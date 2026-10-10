#!/usr/bin/env bats
# tests/bats/integrations/hermes_skill_install.bats
# hermes_skill_install (shell-common/tools/integrations/hermes.sh): a skill URL
# on $DOTFILES_GHES_HOST gets per-command HERMES_ALLOW_PRIVATE_URLS=1 +
# SSL_CERT_FILE=<bundle>; every other URL is a plain passthrough (#2071).

load '../test_helper'

GHES='ghes.example.invalid'

setup() {
    setup_isolated_home
    STUB_DIR="$TEST_TEMP_HOME/bin"
    STUB_LOG="$TEST_TEMP_HOME/hermes.log"
    BUNDLE="$TEST_TEMP_HOME/ca-bundle.crt"
    mkdir -p "$STUB_DIR"
    : >"$BUNDLE"
    # Records the env the wrapper hands hermes, plus its argv.
    cat >"$STUB_DIR/hermes" <<EOF
#!/bin/sh
{
    echo "ALLOW=\${HERMES_ALLOW_PRIVATE_URLS-<unset>}"
    echo "CERT=\${SSL_CERT_FILE-<unset>}"
    echo "ARGS=\$*"
} >'$STUB_LOG'
exit "\${STUB_RC:-0}"
EOF
    chmod +x "$STUB_DIR/hermes"
}

teardown() {
    teardown_isolated_home
}

# Body prefix: stub on PATH, bundle override, caller-side SSL_CERT_FILE marker.
_pre() {
    printf '%s' "export PATH='$STUB_DIR':\$PATH; export HERMES_SKILL_CA_BUNDLE='$BUNDLE'; unset HERMES_ALLOW_PRIVATE_URLS; export SSL_CERT_FILE=/caller/proxy.pem; $1"
}

@test "bash: GHES host URL gets private-URL + CA bundle env and original args" {
    run_in_bash "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install https://$GHES/org/repo/raw/main/s/SKILL.md -y")"
    assert_success
    run cat "$STUB_LOG"
    assert_line "ALLOW=1"
    assert_line "CERT=$BUNDLE"
    assert_line "ARGS=skills install https://$GHES/org/repo/raw/main/s/SKILL.md -y"
}

@test "zsh: GHES host URL gets private-URL + CA bundle env and original args" {
    run_in_zsh "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install https://$GHES/org/repo/raw/main/s/SKILL.md -y")"
    assert_success
    run cat "$STUB_LOG"
    assert_line "ALLOW=1"
    assert_line "CERT=$BUNDLE"
    assert_line "ARGS=skills install https://$GHES/org/repo/raw/main/s/SKILL.md -y"
}

@test "bash: other host is a plain passthrough (caller SSL_CERT_FILE preserved)" {
    run_in_bash "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install https://raw.githubusercontent.com/o/r/main/SKILL.md -y")"
    assert_success
    run cat "$STUB_LOG"
    assert_line "ALLOW=<unset>"
    assert_line "CERT=/caller/proxy.pem"
    assert_line "ARGS=skills install https://raw.githubusercontent.com/o/r/main/SKILL.md -y"
}

@test "zsh: other host is a plain passthrough (caller SSL_CERT_FILE preserved)" {
    run_in_zsh "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install https://raw.githubusercontent.com/o/r/main/SKILL.md -y")"
    assert_success
    run cat "$STUB_LOG"
    assert_line "ALLOW=<unset>"
    assert_line "CERT=/caller/proxy.pem"
}

@test "bash: DOTFILES_GHES_HOST unset is a plain passthrough" {
    run_in_bash "$(_pre "unset DOTFILES_GHES_HOST; hermes_skill_install https://$GHES/o/r/raw/main/SKILL.md")"
    assert_success
    run cat "$STUB_LOG"
    assert_line "ALLOW=<unset>"
    assert_line "CERT=/caller/proxy.pem"
}

@test "bash: caller env is unchanged after a GHES install" {
    run_in_bash "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install https://$GHES/o/r/SKILL.md; echo \"after=\${HERMES_ALLOW_PRIVATE_URLS-<unset>}|\$SSL_CERT_FILE\"")"
    assert_success
    assert_line "after=<unset>|/caller/proxy.pem"
    run cat "$STUB_LOG"
    assert_line "ALLOW=1"
}

@test "zsh: caller env is unchanged after a GHES install" {
    run_in_zsh "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install https://$GHES/o/r/SKILL.md; echo \"after=\${HERMES_ALLOW_PRIVATE_URLS-<unset>}|\$SSL_CERT_FILE\"")"
    assert_success
    assert_line "after=<unset>|/caller/proxy.pem"
    run cat "$STUB_LOG"
    assert_line "ALLOW=1"
}

@test "bash: missing CA bundle fails without calling hermes" {
    run_in_bash "$(_pre "export DOTFILES_GHES_HOST=$GHES; export HERMES_SKILL_CA_BUNDLE=/nonexistent/ca.crt; hermes_skill_install https://$GHES/o/r/SKILL.md")"
    assert_failure
    assert_output --partial "/nonexistent/ca.crt"
    [ ! -e "$STUB_LOG" ]
}

@test "bash: URL with user@ and :port still matches the GHES host" {
    run_in_bash "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install -y http://me@$GHES:8443/o/r/SKILL.md")"
    assert_success
    run cat "$STUB_LOG"
    assert_line "ALLOW=1"
    assert_line "CERT=$BUNDLE"
    assert_line "ARGS=skills install -y http://me@$GHES:8443/o/r/SKILL.md"
}

@test "zsh: URL with user@ and :port still matches the GHES host" {
    run_in_zsh "$(_pre "export DOTFILES_GHES_HOST=$GHES; hermes_skill_install -y http://me@$GHES:8443/o/r/SKILL.md")"
    assert_success
    run cat "$STUB_LOG"
    assert_line "ALLOW=1"
}

@test "bash: hermes exit code is propagated" {
    run_in_bash "$(_pre "export STUB_RC=3; export DOTFILES_GHES_HOST=$GHES; hermes_skill_install https://$GHES/o/r/SKILL.md")"
    assert_failure 3
}
