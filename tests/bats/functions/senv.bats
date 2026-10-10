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
    # Derives "public keys" only from a file that looks like a private key.
    cat >"$STUB_BIN/age-keygen" <<'STUB'
#!/bin/sh
[ "$1" = "-y" ] && grep -q AGE-SECRET-KEY "$2" && { echo "age1first"; echo "age1second"; echo "AGE-SECRET-KEY-1LEAK"; }
STUB
    # age -p / -d stand-in: the "locked" file is a plain copy.
    cat >"$STUB_BIN/age" <<'STUB'
#!/bin/sh
out=""
while [ $# -gt 1 ]; do
    case "$1" in -o) out="$2"; shift ;; esac
    shift
done
if [ -n "$out" ]; then cat "$1" >"$out"; else cat "$1"; fi
STUB
    chmod +x "$STUB_BIN/sops" "$STUB_BIN/age-keygen" "$STUB_BIN/age"
    printf 'AGE-SECRET-KEY-1LEAK\n' >"$KEY_FILE"
    chmod 600 "$KEY_FILE"
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
    grep -qF "path_regex: '(^|/)\\.(enc\\.)?env(\\.enc)?\$'" "$PROJ/.sops.yaml"
    # The written regex matches .env, .enc.env and legacy .env.enc only.
    re=$(sed -n "s/.*path_regex: '\(.*\)'/\1/p" "$PROJ/.sops.yaml")
    for f in .env .enc.env .env.enc sub/.enc.env; do echo "$f" | grep -qE "$re"; done
    [ -z "$(echo ".env.local" | grep -E "$re")" ]
    grep -qx "    age: age1first,age1second" "$PROJ/.sops.yaml"
    [ "$(grep -c SECRET "$PROJ/.sops.yaml")" -eq 0 ]
    [ "$(cat "$PROJ/.gitignore")" = ".env" ]
    assert_output --partial "git add .sops.yaml .gitignore .enc.env"

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

@test "enc calls sops with dotenv flags and writes .enc.env by default" {
    printf 'FOO=1\n' >"$PROJ/.env"
    : >"$PROJ/.sops.yaml"
    _senv "senv enc"
    assert_success
    assert_output --partial ".env -> .enc.env"
    grep -qx -- "-e --input-type dotenv --output-type dotenv .env" "$SOPS_LOG"
    [ "$(cat "$PROJ/.enc.env")" = "FOO=1" ]
    [ ! -e "$PROJ/.env.enc" ]
}

@test "enc with an explicit file keeps the <file>.enc name" {
    printf 'FOO=2\n' >"$PROJ/prod.env"
    : >"$PROJ/.sops.yaml"
    _senv "senv enc prod.env"
    assert_success
    [ "$(cat "$PROJ/prod.env.enc")" = "FOO=2" ]
    [ ! -e "$PROJ/.enc.env" ]
}

@test "enc without .sops.yaml hints senv init; failed sops keeps old .enc.env" {
    printf 'FOO=1\n' >"$PROJ/.env"
    _senv "senv enc"
    assert_failure
    assert_output --partial "senv init"

    : >"$PROJ/.sops.yaml"
    echo "OLD" >"$PROJ/.enc.env"
    _senv "SOPS_STUB_FAIL=1 senv enc"
    assert_failure
    [ "$(cat "$PROJ/.enc.env")" = "OLD" ]
    [ "$(find "$PROJ" -name '.enc.env.*' | wc -l)" -eq 0 ]
}

@test "dec refuses to overwrite without -f; -f works and sets mode 600" {
    printf 'FOO=new\n' >"$PROJ/.enc.env"
    echo "FOO=old" >"$PROJ/.env"
    _senv "senv dec"
    assert_failure
    assert_output --partial "senv dec -f"
    [ "$(cat "$PROJ/.env")" = "FOO=old" ]

    _senv "senv dec -f"
    assert_success
    [ "$(cat "$PROJ/.env")" = "FOO=new" ]
    [ "$(stat -c '%a' "$PROJ/.env")" = "600" ]
    grep -qx -- "-d --input-type dotenv --output-type dotenv .enc.env" "$SOPS_LOG"
}

@test "edit passes dotenv flags" {
    printf 'FOO=1\n' >"$PROJ/.enc.env"
    _senv "senv edit"
    assert_success
    grep -qx -- "edit --input-type dotenv --output-type dotenv .enc.env" "$SOPS_LOG"
}

@test "run exports vars literally and never evals" {
    printf '# c\n\nFOO=hello world\nBAR=$(touch pwned)\nbad-key=x\n' >"$PROJ/.enc.env"
    _senv "senv run sh -c 'printf \"%s|%s\\n\" \"\$FOO\" \"\$BAR\"'"
    assert_success
    assert_output 'hello world|$(touch pwned)'
    [ ! -e "$PROJ/pwned" ]
}

@test "run propagates the command exit code" {
    printf 'FOO=1\n' >"$PROJ/.enc.env"
    _senv "senv run sh -c 'exit 7'"
    [ "$status" -eq 7 ]
}

@test "run does not execute the command when decryption fails" {
    printf 'FOO=1\n' >"$PROJ/.enc.env"
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
    [ "$(printf '%s\n' "$output" | wc -l)" -le 20 ]
    assert_output --partial "키 백업: senv key export -> cp ~/senv-key.age ~/para/area/vault/secrets/"
    assert_output --partial "senv key import ~/para/area/vault/secrets/senv-key.age -> senv dec -f"
    assert_output --partial "senv check"
}

@test "missing sops hints install-sops-age" {
    rm "$STUB_BIN/sops"
    _senv "senv enc"
    assert_failure
    assert_output --partial "install-sops-age"
}

@test "zsh: run exports literally and propagates exit code" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    printf 'FOO=a b\nBAR=$(touch pwned)\n' >"$PROJ/.enc.env"
    run_in_zsh "PATH='$STUB_BIN:/usr/bin:/bin'; cd '$PROJ' && senv run sh -c 'echo \"\$FOO|\$BAR\"; exit 5'"
    [ "$status" -eq 5 ]
    assert_output 'a b|$(touch pwned)'
    [ ! -e "$PROJ/pwned" ]
}

# --- #2058: .enc.env detection, check, key show/import/export -------------

# Stand-in for an interactive terminal: age (stubbed) needs no passphrase.
TTY_OK='_senv_has_tty() { return 0; };'

@test "dec/run/edit/check fall back to legacy .env.enc when .enc.env is absent" {
    printf 'FOO=1\n' >"$PROJ/.env.enc"
    _senv "senv dec"
    assert_success
    [ "$(cat "$PROJ/.env")" = "FOO=1" ]
    grep -qx -- "-d --input-type dotenv --output-type dotenv .env.enc" "$SOPS_LOG"
    _senv "senv run sh -c 'echo \$FOO'"
    assert_output "1"
    _senv "senv edit"
    grep -qx -- "edit --input-type dotenv --output-type dotenv .env.enc" "$SOPS_LOG"
    _senv "senv check"
    assert_output --partial "decrypts: .env.enc"
}

@test "dec prefers .enc.env over .env.enc; an explicit file wins" {
    printf 'FOO=a\n' >"$PROJ/.env.enc"
    printf 'FOO=b\n' >"$PROJ/.enc.env"
    _senv "senv dec"
    [ "$(cat "$PROJ/.env")" = "FOO=b" ]
    _senv "senv dec -f .env.enc"
    [ "$(cat "$PROJ/.env")" = "FOO=a" ]
}

@test "missing ciphertext errors name the standard .enc.env" {
    _senv "senv run true"
    assert_failure
    assert_output --partial ".enc.env (or legacy .env.enc) not found"
    _senv "senv dec"
    assert_failure
    assert_output --partial "input not found: .enc.env"
}

@test "senv help and sops-help workflow use .enc.env" {
    _senv "senv"
    assert_output --partial "encrypt .env -> .enc.env"
    _senv "sops_help newproject; sops_help usage"
    assert_success
    assert_output --partial "senv enc    # .env -> .enc.env"
    assert_output --partial "git add .sops.yaml .gitignore .enc.env"
    refute_output --partial "git add .sops.yaml .gitignore .env.enc"
}

@test "check passes and never prints plaintext" {
    printf 'creation_rules:\n  - age: age1first\n' >"$PROJ/.sops.yaml"
    printf 'FOO=topsecret\n' >"$PROJ/.enc.env"
    _senv "senv check"
    assert_success
    assert_output --partial "decrypts: .enc.env"
    refute_output --partial "topsecret"
    refute_output --partial "AGE-SECRET-KEY"
}

@test "check reports each failure with a next step" {
    printf 'creation_rules:\n  - age: age1other\n' >"$PROJ/.sops.yaml"
    printf 'FOO=topsecret\n' >"$PROJ/.enc.env"
    chmod 644 "$KEY_FILE"
    _senv "SOPS_STUB_FAIL=1 senv check"
    assert_failure
    assert_output --partial "chmod 600"
    assert_output --partial "not a recipient"
    assert_output --partial "cannot decrypt"
    refute_output --partial "topsecret"

    rm "$KEY_FILE"
    _senv "senv check"
    assert_failure
    assert_output --partial "senv key import"
}

@test "key show prints only the public key and the match result" {
    printf 'creation_rules:\n  - age: age1second\n' >"$PROJ/.sops.yaml"
    _senv "senv key show"
    assert_success
    assert_output --partial "age1first age1second"
    assert_output --partial "matches .sops.yaml"
    refute_output --partial "AGE-SECRET-KEY"

    printf 'creation_rules:\n  - age: age1other\n' >"$PROJ/.sops.yaml"
    _senv "senv key show"
    assert_failure
    assert_output --partial "not a recipient"
}

@test "key import refuses without a tty and over an existing key without -f" {
    cp "$KEY_FILE" "$TEST_TEMP_HOME/senv-key.age"
    _senv "senv key import </dev/null"
    assert_failure
    assert_output --partial "already exists"

    rm "$KEY_FILE"
    _senv "senv key import </dev/null"
    assert_failure
    assert_output --partial "no terminal"
    [ ! -e "$KEY_FILE" ]
}

@test "key import installs the key with mode 600 and checks .sops.yaml" {
    printf 'AGE-SECRET-KEY-1NEW\n' >"$TEST_TEMP_HOME/senv-key.age"
    rm -r "$(dirname "$KEY_FILE")"
    printf 'creation_rules:\n  - age: age1first\n' >"$PROJ/.sops.yaml"
    _senv "$TTY_OK senv key import"
    assert_success
    assert_output --partial "matches .sops.yaml"
    [ "$(cat "$KEY_FILE")" = "AGE-SECRET-KEY-1NEW" ]
    [ "$(stat -c '%a' "$KEY_FILE")" = "600" ]

    printf 'creation_rules:\n  - age: age1other\n' >"$PROJ/.sops.yaml"
    _senv "$TTY_OK senv key import -f"
    assert_success
    assert_output --partial "not a recipient"
}

@test "key import rejects a file that is not an age key and leaves no key" {
    printf 'garbage\n' >"$PROJ/k.age"
    rm "$KEY_FILE"
    _senv "$TTY_OK senv key import k.age"
    assert_failure
    [ ! -e "$KEY_FILE" ]
    [ "$(find "$(dirname "$KEY_FILE")" -type f | wc -l)" -eq 0 ]
}

@test "key export guards: git work tree, existing file, no tty" {
    git -C "$PROJ" init -q
    _senv "senv key export -o '$PROJ/k.age' </dev/null"
    assert_failure
    assert_output --partial "git work tree"
    [ ! -e "$PROJ/k.age" ]

    echo old >"$TEST_TEMP_HOME/senv-key.age"
    _senv "senv key export </dev/null"
    assert_failure
    assert_output --partial "already exists"
    [ "$(cat "$TEST_TEMP_HOME/senv-key.age")" = "old" ]

    _senv "senv key export -f </dev/null"
    assert_failure
    assert_output --partial "no terminal"
    [ "$(cat "$TEST_TEMP_HOME/senv-key.age")" = "old" ]
}

@test "key export writes a verified locked copy (stubbed age)" {
    _senv "$TTY_OK senv key export"
    assert_success
    cmp -s "$TEST_TEMP_HOME/senv-key.age" "$KEY_FILE"
    [ "$(stat -c '%a' "$TEST_TEMP_HOME/senv-key.age")" = "600" ]
}
