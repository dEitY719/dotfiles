#!/usr/bin/env bats
# tests/bats/functions/senv.bats
# senv: per-project .env encryption wrapper around sops (issue #1833).
# sops / age-keygen are stubs: the "encrypted" file is a plain copy, and every
# sops call is logged so the dotenv type flags can be asserted.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/stubbin"
    KEY_FILE="$TEST_TEMP_HOME/.config/sops/age/keys.txt"
    PROJ="$TEST_TEMP_HOME/proj"
    SOPS_LOG="$TEST_TEMP_HOME/sops.log"
    mkdir -p "$STUB_BIN" "$(dirname "$KEY_FILE")" "$PROJ"
    cat >"$STUB_BIN/sops" <<STUB
#!/bin/sh
echo "\$*" >>"$SOPS_LOG"
[ -n "\${SOPS_STUB_FAIL-}" ] && { echo "stub decrypt failure" >&2; exit 1; }
for last in "\$@"; do :; done
case "\$1" in -e | -d) cat "\$last" ;; esac
STUB
    cat >"$STUB_BIN/age-keygen" <<'STUB'
#!/bin/sh
[ "$1" = "-y" ] && { echo "age1first"; echo "age1second"; echo "AGE-SECRET-KEY-1LEAK"; }
STUB
    chmod +x "$STUB_BIN/sops" "$STUB_BIN/age-keygen"
    printf 'AGE-SECRET-KEY-1LEAK\n' >"$KEY_FILE"
}

teardown() {
    teardown_isolated_home
}

# Run senv inside the project dir with the stubs first on PATH.
_senv() {
    run_in_bash "PATH='$STUB_BIN:/usr/bin:/bin'; cd '$PROJ' && $1"
}

@test "init writes .sops.yaml + .gitignore and is idempotent" {
    _senv "senv init"
    assert_success
    grep -qF "path_regex: '(^|/)\\.env(\\.enc)?\$'" "$PROJ/.sops.yaml"
    grep -qx "    age: age1first,age1second" "$PROJ/.sops.yaml"
    [ "$(grep -c SECRET "$PROJ/.sops.yaml")" -eq 0 ]
    [ "$(cat "$PROJ/.gitignore")" = ".env" ]
    assert_output --partial "senv enc"

    echo "# edited" >>"$PROJ/.sops.yaml"
    _senv "senv init"
    assert_success
    assert_output --partial "already exists"
    grep -q "# edited" "$PROJ/.sops.yaml"
    [ "$(grep -cx '.env' "$PROJ/.gitignore")" -eq 1 ]
}

@test "init appends .env on its own line to a .gitignore without trailing newline" {
    printf 'node_modules' >"$PROJ/.gitignore"
    _senv "senv init"
    assert_success
    [ "$(cat "$PROJ/.gitignore")" = "$(printf 'node_modules\n.env')" ]
}

@test "init without a key file fails with a setup hint" {
    rm "$KEY_FILE"
    _senv "senv init"
    assert_failure
    assert_output --partial "sops-help setup"
    [ ! -e "$PROJ/.sops.yaml" ]
}

@test "enc calls sops with dotenv flags and writes .env.enc" {
    printf 'FOO=1\n' >"$PROJ/.env"
    : >"$PROJ/.sops.yaml"
    _senv "senv enc"
    assert_success
    grep -qx -- "-e --input-type dotenv --output-type dotenv .env" "$SOPS_LOG"
    [ "$(cat "$PROJ/.env.enc")" = "FOO=1" ]
}

@test "enc without .sops.yaml hints senv init; failed sops keeps old .env.enc" {
    printf 'FOO=1\n' >"$PROJ/.env"
    _senv "senv enc"
    assert_failure
    assert_output --partial "senv init"

    : >"$PROJ/.sops.yaml"
    echo "OLD" >"$PROJ/.env.enc"
    _senv "SOPS_STUB_FAIL=1 senv enc"
    assert_failure
    [ "$(cat "$PROJ/.env.enc")" = "OLD" ]
    [ "$(find "$PROJ" -name '.env.enc.*' | wc -l)" -eq 0 ]
}

@test "dec refuses to overwrite without -f; -f works and sets mode 600" {
    printf 'FOO=new\n' >"$PROJ/.env.enc"
    echo "FOO=old" >"$PROJ/.env"
    _senv "senv dec"
    assert_failure
    assert_output --partial "senv dec -f"
    [ "$(cat "$PROJ/.env")" = "FOO=old" ]

    _senv "senv dec -f"
    assert_success
    [ "$(cat "$PROJ/.env")" = "FOO=new" ]
    [ "$(stat -c '%a' "$PROJ/.env")" = "600" ]
    grep -qx -- "-d --input-type dotenv --output-type dotenv .env.enc" "$SOPS_LOG"
}

@test "edit passes dotenv flags" {
    printf 'FOO=1\n' >"$PROJ/.env.enc"
    _senv "senv edit"
    assert_success
    grep -qx -- "edit --input-type dotenv --output-type dotenv .env.enc" "$SOPS_LOG"
}

@test "run exports vars literally and never evals" {
    printf '# c\n\nFOO=hello world\nBAR=$(touch pwned)\nbad-key=x\n' >"$PROJ/.env.enc"
    _senv "senv run sh -c 'printf \"%s|%s\\n\" \"\$FOO\" \"\$BAR\"'"
    assert_success
    assert_output 'hello world|$(touch pwned)'
    [ ! -e "$PROJ/pwned" ]
}

@test "run propagates the command exit code" {
    printf 'FOO=1\n' >"$PROJ/.env.enc"
    _senv "senv run sh -c 'exit 7'"
    [ "$status" -eq 7 ]
}

@test "run does not execute the command when decryption fails" {
    printf 'FOO=1\n' >"$PROJ/.env.enc"
    _senv "SOPS_STUB_FAIL=1 senv run touch ran"
    assert_failure
    assert_output --partial "command not run"
    [ ! -e "$PROJ/ran" ]
}

@test "unknown subcommand returns 2 with usage; no args prints usage" {
    _senv "senv bogus"
    [ "$status" -eq 2 ]
    assert_output --partial "unknown senv command: bogus"
    _senv "senv"
    assert_success
    [ "$(printf '%s\n' "$output" | wc -l)" -le 12 ]
}

@test "missing sops hints install-sops-age" {
    rm "$STUB_BIN/sops"
    _senv "senv enc"
    assert_failure
    assert_output --partial "install-sops-age"
}

@test "zsh: run exports literally and propagates exit code" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    printf 'FOO=a b\nBAR=$(touch pwned)\n' >"$PROJ/.env.enc"
    run_in_zsh "PATH='$STUB_BIN:/usr/bin:/bin'; cd '$PROJ' && senv run sh -c 'echo \"\$FOO|\$BAR\"; exit 5'"
    [ "$status" -eq 5 ]
    assert_output 'a b|$(touch pwned)'
    [ ! -e "$PROJ/pwned" ]
}
