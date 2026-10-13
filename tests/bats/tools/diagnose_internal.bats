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

@test "internal mode: correct no_proxy entry next to a wildcard passes with WARN" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    run env DOTFILES_INTERNAL_DOMAIN=corp.test no_proxy='.corp.test,*.corp.test' bash "$SCRIPT"
    assert_output --partial "[PASS] no_proxy 에 corp.test 포함됨"
    assert_output --partial "[WARN] no_proxy 에 와일드카드(*.corp.test) 도 있음"
    refute_output --partial "[FAIL] no_proxy"
}

@test "internal mode: .hooks/.statusLine drift from the SSOT is a FAIL" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude"
    printf '{"hooks":{},"statusLine":null}' >"$HOME/.claude/settings.json"
    run bash "$SCRIPT"
    assert_failure 1
    assert_output --partial "[FAIL] .hooks 가 dotfiles SSOT 와 다름"
    assert_output --partial "[FAIL] .statusLine 이 dotfiles SSOT 와 다름"
}

@test "unknown argument: usage + exit 2, no checks" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    run bash "$SCRIPT" --hlep
    assert_failure 2
    assert_output --partial "알 수 없는 인자: --hlep"
    refute_output --partial "[PASS]"
}

@test "no AWS/Bedrock check revived" {
    run grep -iE 'bedrock|aws sts|AWS_CA_BUNDLE' "$SCRIPT"
    assert_failure 1
}

# 자체 서명 인증서 생성 → $BATS_TEST_TMPDIR/<name>.crt, 지문은 stdout (#2103).
_mk_cert() {
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -keyout "$BATS_TEST_TMPDIR/$1.key" -out "$BATS_TEST_TMPDIR/$1.crt" \
        -subj "/CN=$1" -days 1 >/dev/null 2>&1
    openssl x509 -in "$BATS_TEST_TMPDIR/$1.crt" -noout -fingerprint -sha256 | sed 's/.*=//'
}

# $1 만 뺀 PATH 디렉터리 — 나머지 도구는 그대로 쓴다. 경로는 stdout.
# shortcut: 시스템 bin 3곳만 링크한다 — bash 가 그 밖에만 있는 PC 면 테스트가 깨진다, 그때 PATH 전체를 훑도록 넓힌다.
_path_without() {
    local bin="$BATS_TEST_TMPDIR/no-$1" f
    mkdir -p "$bin"
    for f in /usr/local/bin/* /usr/bin/* /bin/*; do
        [ "${f##*/}" = "$1" ] && continue
        [ -e "$f" ] || continue # 안 맞은 glob('*' 리터럴)·깨진 링크는 건너뛴다
        ln -s "$f" "$bin/" 2>/dev/null || true # 앞 디렉터리 우선, 중복은 무시
    done
    printf '%s' "$bin"
}

@test "internal mode: CA check compares real SHA-256 fingerprints per certificate" {
    command -v openssl >/dev/null 2>&1 || skip "openssl not installed"
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    local fp other_fp
    fp="$(_mk_cert target)"
    other_fp="$(_mk_cert other)"
    run env NODE_EXTRA_CA_CERTS="$BATS_TEST_TMPDIR/other.crt" DOTFILES_PROXY_CA_FINGERPRINT="$fp" bash "$SCRIPT"
    assert_output --partial "[FAIL] 사내 프록시 인증서 미포함"
    cat "$BATS_TEST_TMPDIR/other.crt" "$BATS_TEST_TMPDIR/target.crt" >"$BATS_TEST_TMPDIR/bundle.crt"
    # 콜론 없음 + 소문자도 같은 지문으로 정규화된다.
    run env NODE_EXTRA_CA_CERTS="$BATS_TEST_TMPDIR/bundle.crt" \
        DOTFILES_PROXY_CA_FINGERPRINT="$(printf '%s' "$fp" | tr -d ':' | tr 'A-F' 'a-f')" \
        DOTFILES_EXTRA_CA_FINGERPRINTS="$other_fp" bash "$SCRIPT"
    assert_output --partial "[PASS] 사내 프록시 인증서 포함됨"
    assert_output --partial "[PASS] 추가 사내 CA 인증서 #1 포함됨"
    refute_output --partial "지문 형식이 아님"
}

@test "internal mode: large bundle with a broken block still finds the last certificate (#2109)" {
    command -v openssl >/dev/null 2>&1 || skip "openssl not installed"
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    local fp i
    fp="$(_mk_cert target)"
    _mk_cert other >/dev/null
    # 병렬 지문 계산 폭보다 많은 블록 + 중간의 깨진 블록 — 나머지 인증서는 그대로 읽힌다.
    for i in $(seq 40); do cat "$BATS_TEST_TMPDIR/other.crt"; done >"$BATS_TEST_TMPDIR/bundle.crt"
    printf -- '-----BEGIN CERTIFICATE-----\nnot-a-cert\n-----END CERTIFICATE-----\n' >>"$BATS_TEST_TMPDIR/bundle.crt"
    cat "$BATS_TEST_TMPDIR/target.crt" >>"$BATS_TEST_TMPDIR/bundle.crt"
    run env NODE_EXTRA_CA_CERTS="$BATS_TEST_TMPDIR/bundle.crt" DOTFILES_PROXY_CA_FINGERPRINT="$fp" bash "$SCRIPT"
    assert_output --partial "[PASS] 사내 프록시 인증서 포함됨"
    refute_output --partial "지문을 하나도 읽지 못함"
}

@test "internal mode: non-fingerprint CA value falls back to substring with WARN" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    printf -- '-----BEGIN CERTIFICATE-----\nFAKEFP\n' >"$HOME/ca.crt"
    run env NODE_EXTRA_CA_CERTS="$HOME/ca.crt" DOTFILES_PROXY_CA_FINGERPRINT=FAKEFP bash "$SCRIPT"
    assert_output --partial "[WARN] 사내 프록시 인증서: SHA-256 지문 형식이 아님"
    assert_output --partial "[PASS] 사내 프록시 인증서 포함됨"
}

@test "internal mode: missing openssl skips the fingerprint comparison with WARN" {
    command -v openssl >/dev/null 2>&1 || skip "openssl not installed"
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    local fp
    fp="$(_mk_cert target)"
    run env PATH="$(_path_without openssl)" NODE_EXTRA_CA_CERTS="$BATS_TEST_TMPDIR/target.crt" DOTFILES_EXTRA_CA_FINGERPRINTS="$fp" \
        DOTFILES_PROXY_CA_FINGERPRINT="$fp" bash "$SCRIPT"
    assert_output --partial "[WARN] 사내 프록시 인증서: openssl 미설치"
    [ "$(printf '%s\n' "$output" | grep -c 'openssl 미설치')" -eq 1 ]
    refute_output --partial "사내 프록시 인증서 포함됨"
    refute_output --partial "사내 프록시 인증서 미포함"
    assert_output --partial "2) Claude Code 설치 & PATH"
}

@test "internal mode: unparseable bundle is told apart from a missing CA" {
    command -v openssl >/dev/null 2>&1 || skip "openssl not installed"
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    printf -- '-----BEGIN CERTIFICATE-----\nnot-a-cert\n-----END CERTIFICATE-----\n' >"$HOME/ca.crt"
    run env NODE_EXTRA_CA_CERTS="$HOME/ca.crt" \
        DOTFILES_PROXY_CA_FINGERPRINT="$(printf 'AB:%.0s' $(seq 32) | sed 's/:$//')" bash "$SCRIPT"
    assert_output --partial "[WARN] bundle 에서 인증서 지문을 하나도 읽지 못함"
    assert_output --partial "[FAIL] 사내 프록시 인증서 미포함"
}

# --- #2104: 남은 커버리지 공백 ---

@test "internal mode: internal.local.sh is really loaded without DOTFILES_SKIP_LOCAL_ENV" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    # 스크립트는 자기 위치로 DOTFILES_ROOT 를 정한다 — 실제 트리를 건드리지 않게
    # 필요한 파일만 임시 트리로 복사한다 (setup_isolated_dotfiles_root 는
    # shell-common 을 실제 트리로 symlink 하므로 여기엔 맞지 않는다).
    local real="$DOTFILES_ROOT" iso="$BATS_TEST_TMPDIR/iso"
    mkdir -p "$iso/shell-common/tools/custom" "$iso/shell-common/util" "$iso/shell-common/env"
    cp "$real/$SCRIPT_REL" "$real/shell-common/tools/custom/init.sh" "$iso/shell-common/tools/custom/"
    cp -R "$real/shell-common/tools/ux_lib" "$iso/shell-common/tools/"
    cp "$real/shell-common/util/setup_mode_read.sh" "$iso/shell-common/util/"
    cp "$real/shell-common/env/internal.sh" "$iso/shell-common/env/"
    printf 'export DOTFILES_INTERNAL_DOMAIN=corp.test\n' >"$iso/shell-common/env/internal.local.sh"
    run env -u DOTFILES_SKIP_LOCAL_ENV -u DOTFILES_INTERNAL_DOMAIN no_proxy=localhost,.corp.test \
        bash "$iso/$SCRIPT_REL"
    # exit 1 = 끝까지 돌고 다른 항목(CA/PATH/프록시) FAIL — 복사 목록 누락으로 중간에 죽으면 다른 코드.
    assert_failure 1
    assert_output --partial "[PASS] no_proxy 에 corp.test 포함됨"
    refute_output --partial "no_proxy 사내 도메인: internal.local.sh 미설정"
    # 같은 트리라도 SKIP 가드가 켜지면 로딩하지 않는다.
    run env -u DOTFILES_INTERNAL_DOMAIN DOTFILES_SKIP_LOCAL_ENV=1 no_proxy=localhost,.corp.test \
        bash "$iso/$SCRIPT_REL"
    assert_output --partial "[WARN] no_proxy 사내 도메인: internal.local.sh 미설정"
}

@test "internal mode: CA file without .crt extension is a FAIL" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    printf -- '-----BEGIN CERTIFICATE-----\n' >"$HOME/ca.pem"
    run env NODE_EXTRA_CA_CERTS="$HOME/ca.pem" bash "$SCRIPT"
    assert_failure 1
    assert_output --partial "[FAIL] 인증서 확장자가 .crt 가 아님 (현재: pem)"
}

@test "internal mode: broken BEGIN CERTIFICATE line is a FAIL" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    # vim 붙여넣기 사고 재현 — 첫 글자가 잘린 BEGIN 줄.
    printf -- '----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n' >"$HOME/ca.crt"
    run env NODE_EXTRA_CA_CERTS="$HOME/ca.crt" bash "$SCRIPT"
    assert_failure 1
    assert_output --partial "[FAIL] 인증서 첫 줄이 깨져 있을 수 있음"
    refute_output --partial "[PASS] 인증서 첫 줄 형식 정상"
}

@test "internal mode: settings.json symlink is a FAIL" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude"
    cp "$DOTFILES_ROOT/claude/settings.json" "$HOME/real-settings.json"
    ln -s "$HOME/real-settings.json" "$HOME/.claude/settings.json"
    run bash "$SCRIPT"
    assert_failure 1
    assert_output --partial "[FAIL] settings.json 이 symlink"
    refute_output --partial "[PASS] settings.json 실파일 존재"
}

@test "internal mode: DOTFILES_EXTRA_CA_FINGERPRINTS present is PASS, missing is WARN" {
    command -v openssl >/dev/null 2>&1 || skip "openssl not installed"
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    local fp other_fp
    fp="$(_mk_cert target)"
    other_fp="$(_mk_cert other)"
    run env NODE_EXTRA_CA_CERTS="$BATS_TEST_TMPDIR/target.crt" \
        DOTFILES_EXTRA_CA_FINGERPRINTS="$fp $other_fp" bash "$SCRIPT"
    assert_output --partial "[PASS] 추가 사내 CA 인증서 #1 포함됨"
    assert_output --partial "[WARN] 추가 사내 CA 인증서 #2 미포함"
    refute_output --partial "[FAIL] 추가 사내 CA"
}

@test "internal mode: missing jq skips settings.json validation with WARN" {
    printf 'internal\n' >"$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude"
    printf '{not json' >"$HOME/.claude/settings.json"
    local bin
    bin="$(_path_without jq)"
    [ -z "$(PATH="$bin" command -v jq)" ] # stub PATH 에서 jq 가 정말 빠졌는지
    run env PATH="$bin" bash "$SCRIPT"
    assert_output --partial "[WARN] jq 미설치 → settings.json 검증 생략"
    refute_output --partial "JSON 형식 오류"
    refute_output --partial "[PASS] JSON 형식 유효"
    refute_output --partial ".hooks 가 dotfiles SSOT"
}
