#!/usr/bin/env bats
# tests/bats/functions/sops_help.bats
# sops-help / age-help topic and sops_age_status diagnostics (issue #1833).

load '../test_helper'

SECRET='AGE-SECRET-KEY-1QQQQFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/stubbin"
    KEY_FILE="$TEST_TEMP_HOME/.config/sops/age/keys.txt"
    mkdir -p "$STUB_BIN" "$(dirname "$KEY_FILE")"
}

teardown() {
    teardown_isolated_home
}

# Stubs for sops/age/age-keygen. age-keygen -y deliberately also prints the
# secret, so the test proves sops_age_status filters it rather than trusting
# the tool.
_install_stubs() {
    printf '#!/bin/sh\necho "sops 3.13.3"\n' >"$STUB_BIN/sops"
    printf '#!/bin/sh\necho "v1.3.2"\n' >"$STUB_BIN/age"
    cat >"$STUB_BIN/age-keygen" <<EOF
#!/bin/sh
case "\$1" in
    -y) echo "age1fakepublickey"; echo "$SECRET" ;;
    *) echo "v1.3.2" ;;
esac
EOF
    chmod +x "$STUB_BIN/sops" "$STUB_BIN/age" "$STUB_BIN/age-keygen"
}

_write_key() {
    printf '# public key: age1fakepublickey\n%s\n' "$SECRET" >"$KEY_FILE"
    chmod "$1" "$KEY_FILE"
}

@test "sops-help and age-help both alias sops_help (same output)" {
    # Aliases are not expanded in a non-interactive -c string, so assert the
    # alias targets; same target function => identical output.
    run_in_bash "alias sops-help; alias age-help; sops_help"
    assert_success
    assert_output --partial "sops-help='sops_help'"
    assert_output --partial "age-help='sops_help'"
    assert_output --partial "Usage: sops-help [section|--list|--all]"
}

@test "summary is at most 15 lines" {
    run_in_bash "sops_help"
    assert_success
    [ "$(printf '%s\n' "$output" | wc -l)" -le 15 ]
}

@test "--list shows all 8 sections" {
    run_in_bash "sops_help --list"
    assert_success
    for s in overview setup newproject usage newpc risks trouble more; do
        assert_output --partial "$s"
    done
}

@test "each section renders non-empty output" {
    for s in overview setup newproject usage newpc risks trouble more; do
        run_in_bash "sops_help $s"
        assert_success
        [ -n "$output" ]
    done
}

@test "usage section carries the verified dotenv forms" {
    run_in_bash "sops_help usage"
    assert_output --partial "sops -e --input-type dotenv --output-type dotenv .env > .env.enc"
    assert_output --partial "sops -d --input-type dotenv --output-type dotenv .env.enc > .env"
    assert_output --partial "sops exec-env .enc.env"
}

@test "--all renders every section" {
    run_in_bash "sops_help --all"
    assert_success
    assert_output --partial "위험 요소"
    assert_output --partial "age -p -o keys.txt.age"
}

@test "unknown section errors with a --list hint and non-zero exit" {
    run_in_bash "sops_help nosuchsection"
    assert_failure
    assert_output --partial "Unknown sops-help section: nosuchsection"
    assert_output --partial "Try: sops-help --list"
}

@test "zsh: sops_help and aliases are defined" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run_in_zsh "alias sops-help age-help && sops_help --list"
    assert_success
    assert_output --partial "age-help=sops_help"
    assert_output --partial "newpc"
}

@test "sops_age_status: mode 644 is reported, secret never printed" {
    _install_stubs
    _write_key 644
    run_in_bash "PATH='$STUB_BIN:/usr/bin:/bin'; sops_age_status"
    assert_success
    assert_output --partial "mode 644, expected 600"
    assert_output --partial "chmod 600"
    assert_output --partial "public key: age1fakepublickey"
    refute_output --partial "AGE-SECRET-KEY"
    # never changes the mode itself
    [ "$(stat -c '%a' "$KEY_FILE")" = "644" ]
}

@test "sops_age_status: mode 600 is accepted" {
    _install_stubs
    _write_key 600
    run_in_bash "PATH='$STUB_BIN:/usr/bin:/bin'; sops_age_status"
    assert_success
    assert_output --partial "(mode 600)"
    refute_output --partial "expected 600"
    refute_output --partial "AGE-SECRET-KEY"
}

@test "sops_age_status: missing tools and missing key are reported" {
    run_in_bash "PATH='$STUB_BIN:/usr/bin:/bin'; sops_age_status"
    assert_success
    assert_output --partial "sops: not installed"
    assert_output --partial "age-keygen: not installed"
    assert_output --partial "install-sops-age"
    assert_output --partial "key file not found"
}

@test "sops_age_status honours SOPS_AGE_KEY_FILE" {
    _install_stubs
    local alt="$TEST_TEMP_HOME/alt-keys.txt"
    printf '%s\n' "$SECRET" >"$alt"
    chmod 600 "$alt"
    run_in_bash "PATH='$STUB_BIN:/usr/bin:/bin'; SOPS_AGE_KEY_FILE='$alt' sops_age_status"
    assert_success
    assert_output --partial "$alt (mode 600)"
    refute_output --partial "AGE-SECRET-KEY"
}
