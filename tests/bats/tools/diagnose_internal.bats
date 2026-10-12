#!/usr/bin/env bats
# tests/bats/tools/diagnose_internal.bats
# diagnose_internal.sh (#2099): no-op outside internal mode, read-only PASS/
# FAIL/WARN report inside it, and no AWS/Bedrock check revived.

load '../test_helper'

SCRIPT_REL=shell-common/tools/custom/diagnose_internal.sh

setup() {
    setup_isolated_home
    SCRIPT="$DOTFILES_ROOT/$SCRIPT_REL"
    unset CLAUDE_CONFIG_DIR NODE_EXTRA_CA_CERTS SSL_CERT_FILE no_proxy NO_PROXY
    export DOTFILES_SKIP_LOCAL_ENV=1
}

teardown() {
    teardown_isolated_home
}

_home_snapshot() { (cd "$HOME" && find . | sort); }

@test "non-internal modes: notice only, exit 0, no checks" {
    local mode
    for mode in public external; do
        printf '%s\n' "$mode" >"$HOME/.dotfiles-setup-mode"
        run bash "$SCRIPT"
        assert_success
        assert_output --partial "setup-mode='$mode'"
        refute_output --partial "[PASS]"
        refute_output --partial "[FAIL]"
    done
    rm -f "$HOME/.dotfiles-setup-mode"
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "setup-mode='none'"
}

@test "internal mode: reports PASS/FAIL/WARN, writes nothing" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude"
    cp "$DOTFILES_ROOT/claude/settings.json" "$HOME/.claude/settings.json"
    printf -- '-----BEGIN CERTIFICATE-----\nFAKEFP\n' >"$HOME/ca.crt"
    local before
    before="$(_home_snapshot)"
    run env NODE_EXTRA_CA_CERTS="$HOME/ca.crt" DOTFILES_PROXY_CA_FINGERPRINT=FAKEFP \
        DOTFILES_INTERNAL_DOMAIN=corp.test no_proxy='*.corp.test' \
        https_proxy=http://p.test http_proxy=http://p.test bash "$SCRIPT"
    assert_failure 1
    assert_output --partial "[PASS] 사내 프록시 인증서 포함됨"
    assert_output --partial "[FAIL] no_proxy 에 와일드카드(*.corp.test)"
    assert_output --partial "[PASS] .hooks 가 dotfiles SSOT 와 일치"
    assert_output --partial "[PASS] .statusLine 이 dotfiles SSOT 와 일치"
    [ "$(_home_snapshot)" = "$before" ]
}

@test "internal mode: unset internal.local.sh expectations degrade to WARN" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    printf -- '-----BEGIN CERTIFICATE-----\n' >"$HOME/ca.crt"
    run env -u DOTFILES_PROXY_CA_FINGERPRINT -u DOTFILES_INTERNAL_DOMAIN \
        NODE_EXTRA_CA_CERTS="$HOME/ca.crt" no_proxy=.corp.test bash "$SCRIPT"
    assert_output --partial "[WARN] 사내 프록시 인증서 포함 여부: internal.local.sh 미설정"
    assert_output --partial "[WARN] no_proxy 사내 도메인: internal.local.sh 미설정"
}

@test "internal mode: lookalike no_proxy entries do not satisfy the domain" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    local np
    for np in 'localhost,notcorp.test' 'corp.test.evil,localhost'; do
        run env DOTFILES_INTERNAL_DOMAIN=corp.test no_proxy="$np" bash "$SCRIPT"
        assert_output --partial "[FAIL] no_proxy 에 corp.test 미포함"
    done
    run env DOTFILES_INTERNAL_DOMAIN=corp.test no_proxy='localhost, .corp.test' bash "$SCRIPT"
    assert_output --partial "[PASS] no_proxy 에 corp.test 포함됨"
}

@test "internal mode: all required items OK exits 0" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude" "$HOME/.local/bin"
    cp "$DOTFILES_ROOT/claude/settings.json" "$HOME/.claude/settings.json"
    printf '#!/bin/sh\n' >"$HOME/.local/bin/claude"
    chmod +x "$HOME/.local/bin/claude"
    printf -- '-----BEGIN CERTIFICATE-----\nFAKE.FP\n' >"$HOME/ca.crt"
    run env PATH="$HOME/.local/bin:$PATH" NODE_EXTRA_CA_CERTS="$HOME/ca.crt" \
        DOTFILES_PROXY_CA_FINGERPRINT=FAKE.FP DOTFILES_INTERNAL_DOMAIN=corp.test \
        no_proxy=localhost,.corp.test https_proxy=http://p.test http_proxy=http://p.test \
        bash "$SCRIPT"
    assert_success
    refute_output --partial "[FAIL]"
    assert_output --partial "모든 필수 항목이 정상입니다."
}

@test "internal mode: invalid settings.json skips the SSOT comparison" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude"
    printf '{not json' >"$HOME/.claude/settings.json"
    run bash "$SCRIPT"
    assert_output --partial "[FAIL] JSON 형식 오류"
    refute_output --partial ".hooks 가 dotfiles SSOT 와 다름"
}

@test "no AWS/Bedrock check revived" {
    run grep -iE 'bedrock|aws sts|AWS_CA_BUNDLE' "$SCRIPT"
    assert_failure 1
}
