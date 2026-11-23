#!/usr/bin/env bats
# tests/bats/integrations/senv_vault_push.bats
# senv vault-push: copy the CWD project's .enc.env (+ .sops.yaml) into the
# vault repo under secrets/<NAME>/, commit only those paths, push.
#
# Same fixture style as senv_store.bats: the REAL sops + age-keygen (via mise;
# skip when absent), a fixture vault clone with a local bare remote (no
# network). ux_lib.sh + sops.sh are sourced directly in the subprocess.

load '../test_helper'

_VP_SOPS_BIN=$(mise which sops 2>/dev/null || true)
_VP_AGE_BIN=$(mise which age 2>/dev/null || true)
_VP_SOPS_DIR="${_VP_SOPS_BIN:+$(dirname "$_VP_SOPS_BIN")}"
_VP_AGE_DIR="${_VP_AGE_BIN:+$(dirname "$_VP_AGE_BIN")}"
[ -n "$_VP_SOPS_DIR" ] && [ -x "$_VP_AGE_DIR/age-keygen" ] || _VP_SOPS_DIR=""

setup() {
    setup_isolated_home
    [ -n "$_VP_SOPS_DIR" ] || skip "sops/age (mise) not installed"
    SOPS_DIR="$_VP_SOPS_DIR"
    AGE_DIR="$_VP_AGE_DIR"

    PROJ="$TEST_TEMP_HOME/work/freellmapi"
    VAULT="$TEST_TEMP_HOME/vault"
    REMOTE="$TEST_TEMP_HOME/vault-remote.git"
    export SOPS_AGE_KEY_FILE="$TEST_TEMP_HOME/keys.txt"

    "$AGE_DIR/age-keygen" -o "$SOPS_AGE_KEY_FILE" >/dev/null 2>&1
    local pub
    pub=$("$AGE_DIR/age-keygen" -y "$SOPS_AGE_KEY_FILE")

    mkdir -p "$PROJ"
    printf "creation_rules:\n  - path_regex: '(^|/)\\.(enc\\.)?env(\\.enc)?\$'\n    age: %s\n" "$pub" >"$PROJ/.sops.yaml"
    printf 'API_KEY=plainsecret1\n' >"$PROJ/.env"
    (cd "$PROJ" && PATH="$SOPS_DIR:$PATH" sops -e --input-type dotenv --output-type dotenv .env >.enc.env)

    git init -q --bare -b main "$REMOTE"
    git init -q -b main "$VAULT"
    git -C "$VAULT" config user.email t@example.test
    git -C "$VAULT" config user.name t
    git -C "$VAULT" config core.hooksPath /dev/null
    printf 'vault\n' >"$VAULT/README"
    git -C "$VAULT" add README
    git -C "$VAULT" commit -q -m init
    git -C "$VAULT" remote add origin "$REMOTE"
    git -C "$VAULT" push -q -u origin main
    git -C "$VAULT" remote set-head origin main
}

teardown() {
    teardown_isolated_home
}

_remote_commits() {
    git --git-dir="$REMOTE" log --oneline | wc -l
}

# Files touched by the remote's HEAD commit, '|'-joined.
_remote_head_files() {
    git --git-dir="$REMOTE" show --name-only --format= HEAD | tr '\n' '|'
}

_vp() {
    run bash --noprofile --norc -c "
        export SOPS_AGE_KEY_FILE='$SOPS_AGE_KEY_FILE' SENV_VAULT_DIR='$VAULT'
        export DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE=1 TERM=dumb
        export HOME='$HOME'
        export PATH='$SOPS_DIR:$AGE_DIR:/usr/bin:/bin'
        . '$_BATS_REAL_SHELL_COMMON/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_SHELL_COMMON/tools/integrations/sops.sh'
        cd '$PROJ' || exit 99
        $1
    "
}

@test "default: copies .enc.env + .sops.yaml to secrets/<dir>/, commits and pushes" {
    _vp "senv vault-push"
    assert_success
    [ "$(_remote_commits)" -eq 2 ]
    [ "$(git --git-dir="$REMOTE" log --format=%s -1)" = "chore: add freellmapi .enc.env" ]
    [ "$(_remote_head_files)" = "secrets/freellmapi/.enc.env|secrets/freellmapi/.sops.yaml|" ]
    cmp -s "$PROJ/.enc.env" "$VAULT/secrets/freellmapi/.enc.env"
    # no trailer, no plaintext anywhere in history
    if git --git-dir="$REMOTE" log --format=%B -1 | grep -q Co-Authored-By; then fail "trailer"; fi
    if git --git-dir="$REMOTE" log -p | grep -q plainsecret1; then fail "plaintext leaked"; fi
    [ ! -e "$VAULT/secrets/freellmapi/.env" ]
}

@test "second run with the same content is a no-op" {
    _vp "senv vault-push"
    assert_success
    _vp "senv vault-push"
    assert_success
    [[ "$output" == *"no change"* ]]
    [ "$(_remote_commits)" -eq 2 ]
}

@test ".env with blank lines and comments does not force a re-encrypt" {
    printf '# note\nAPI_KEY=plainsecret1\n\n\nOTHER=x\n' >"$PROJ/.env"
    (cd "$PROJ" && PATH="$SOPS_DIR:$PATH" sops -e --input-type dotenv --output-type dotenv .env >.enc.env)
    _vp "senv vault-push"
    assert_success
    _vp "senv vault-push"
    assert_success
    [[ "$output" != *"re-encrypting"* ]]
    [[ "$output" == *"no change"* ]]
    [ "$(_remote_commits)" -eq 2 ]
}

@test "changed .env is re-encrypted and committed as an update" {
    _vp "senv vault-push"
    printf 'API_KEY=plainsecret2\n' >"$PROJ/.env"
    _vp "senv vault-push"
    assert_success
    [ "$(git --git-dir="$REMOTE" log --format=%s -1)" = "chore: update freellmapi .enc.env" ]
    run env PATH="$SOPS_DIR:$PATH" SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" \
        sops -d --input-type dotenv --output-type dotenv "$VAULT/secrets/freellmapi/.enc.env"
    assert_output "API_KEY=plainsecret2"
}

@test "-n changes the name in the default path and message" {
    _vp "senv vault-push -n other"
    assert_success
    [ "$(git --git-dir="$REMOTE" log --format=%s -1)" = "chore: add other .enc.env" ]
    [ -f "$VAULT/secrets/other/.enc.env" ]
}

@test "-d overrides the destination, -m the message" {
    _vp "senv vault-push -d secrets/team/foo/ -m 'custom msg'"
    assert_success
    [ "$(git --git-dir="$REMOTE" log --format=%s -1)" = "custom msg" ]
    [ "$(_remote_head_files)" = "secrets/team/foo/.enc.env|secrets/team/foo/.sops.yaml|" ]
}

@test "--no-push commits locally only" {
    _vp "senv vault-push --no-push"
    assert_success
    [ "$(_remote_commits)" -eq 1 ]
    [ "$(git -C "$VAULT" log --format=%s -1)" = "chore: add freellmapi .enc.env" ]
}

@test "--no-sops copies .enc.env only" {
    _vp "senv vault-push --no-sops"
    assert_success
    [ "$(_remote_head_files)" = "secrets/freellmapi/.enc.env|" ]
    [ ! -e "$VAULT/secrets/freellmapi/.sops.yaml" ]
}

@test "path traversal and absolute paths are rejected" {
    _vp "senv vault-push -d ../escape"
    [ "$status" -eq 2 ]
    _vp "senv vault-push -d /tmp/x"
    [ "$status" -eq 2 ]
    _vp "senv vault-push -n ''"
    [ "$status" -eq 2 ]
    _vp "senv vault-push -d ''"
    [ "$status" -eq 2 ]
    _vp "senv vault-push -n a/../../b"
    [ "$status" -eq 2 ]
    [ "$(_remote_commits)" -eq 1 ]
    [ ! -e "$TEST_TEMP_HOME/escape" ]
}

@test "unknown option fails with status 2" {
    _vp "senv vault-push --bogus"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "missing .enc.env points at senv enc" {
    rm "$PROJ/.enc.env"
    _vp "senv vault-push"
    assert_failure
    [[ "$output" == *"senv enc"* ]]
}

@test "missing vault dir points at git clone" {
    _vp "senv vault-push -v '$TEST_TEMP_HOME/nope'"
    assert_failure
    [[ "$output" == *"git clone"* ]]
}

@test "refuses when the vault is off the default branch" {
    git -C "$VAULT" switch -q -c feature
    _vp "senv vault-push"
    assert_failure
    [[ "$output" == *"default branch"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "refuses when other changes are staged in the vault" {
    printf 'x\n' >"$VAULT/other"
    git -C "$VAULT" add other
    _vp "senv vault-push"
    assert_failure
    [[ "$output" == *"other"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "zsh: default vault-push works" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -f -c "
        export SOPS_AGE_KEY_FILE='$SOPS_AGE_KEY_FILE' SENV_VAULT_DIR='$VAULT'
        export DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE=1 TERM=dumb HOME='$HOME'
        export PATH='$SOPS_DIR:$AGE_DIR:/usr/bin:/bin'
        . '$_BATS_REAL_SHELL_COMMON/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_SHELL_COMMON/tools/integrations/sops.sh'
        cd '$PROJ' && senv vault-push
    "
    assert_success
    [ "$(_remote_head_files)" = "secrets/freellmapi/.enc.env|secrets/freellmapi/.sops.yaml|" ]
}
