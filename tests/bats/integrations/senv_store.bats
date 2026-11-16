#!/usr/bin/env bats
# tests/bats/integrations/senv_store.bats
# senv set/get/push/keys: the dotfiles .enc.env store cycle.
#
# Unlike senv.bats (stub sops), this suite runs the REAL sops + age-keygen
# (via mise; skip when absent) against an isolated fixture dotfiles repo with
# a local bare remote — the value of these four commands is the exact
# sops/git round-trip and the push semantics, which a cat-stub cannot prove.
#
# SHELL_COMMON points at the fixture's shell-common/, so _senv_dotfiles_root
# resolves to the fixture. run_in_bash cannot be used: bootstrap.sh would
# overwrite SHELL_COMMON with the real tree, so ux_lib.sh + sops.sh are
# sourced directly in the subprocess.

load '../test_helper'

# Resolve mise tools while $HOME is still the real one: setup_isolated_home
# repoints HOME/XDG_DATA_HOME at a temp dir, and mise would find nothing there.
_STORE_SOPS_BIN=$(mise which sops 2>/dev/null || true)
_STORE_AGE_BIN=$(mise which age 2>/dev/null || true)
_STORE_SOPS_DIR="${_STORE_SOPS_BIN:+$(dirname "$_STORE_SOPS_BIN")}"
_STORE_AGE_DIR="${_STORE_AGE_BIN:+$(dirname "$_STORE_AGE_BIN")}"
[ -n "$_STORE_SOPS_DIR" ] && [ -x "$_STORE_AGE_DIR/age-keygen" ] || _STORE_SOPS_DIR=""

setup() {
    setup_isolated_home
    [ -n "$_STORE_SOPS_DIR" ] || skip "sops/age (mise) not installed"
    SOPS_DIR="$_STORE_SOPS_DIR"
    AGE_DIR="$_STORE_AGE_DIR"

    DF="$TEST_TEMP_HOME/store-dotfiles"
    REMOTE="$TEST_TEMP_HOME/store-remote.git"
    export SOPS_AGE_KEY_FILE="$TEST_TEMP_HOME/keys.txt"

    mkdir -p "$DF/shell-common"
    "$AGE_DIR/age-keygen" -o "$SOPS_AGE_KEY_FILE" >/dev/null 2>&1
    local pub
    pub=$("$AGE_DIR/age-keygen" -y "$SOPS_AGE_KEY_FILE")

    git init -q --bare -b main "$REMOTE"
    git init -q -b main "$DF"
    git -C "$DF" config user.email t@example.test
    git -C "$DF" config user.name t
    git -C "$DF" config core.hooksPath /dev/null
    printf "creation_rules:\n  - path_regex: '(^|/)\\.(enc\\.)?env(\\.enc)?\$'\n    age: %s\n" "$pub" >"$DF/.sops.yaml"
    printf '.env\n' >"$DF/.gitignore"
    printf '# store fixture\nEXISTING=oldval\nEMPTY=\n' >"$DF/.env"
    (cd "$DF" && PATH="$SOPS_DIR:$PATH" sops -e --input-type dotenv --output-type dotenv .env >.enc.env)
    rm "$DF/.env"
    git -C "$DF" add .sops.yaml .gitignore .enc.env
    git -C "$DF" commit -q -m init
    git -C "$DF" remote add origin "$REMOTE"
    git -C "$DF" push -q -u origin main
    git -C "$DF" remote set-head origin main
}

teardown() {
    teardown_isolated_home
}

# Commit count on the bare remote: how many store commits happened.
_remote_commits() {
    git --git-dir="$REMOTE" log --oneline | wc -l
}

_store() {
    run bash --noprofile --norc -c "
        export SHELL_COMMON='$DF/shell-common'
        export SOPS_AGE_KEY_FILE='$SOPS_AGE_KEY_FILE'
        export DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE=1 TERM=dumb
        export HOME='$HOME'
        export PATH='$SOPS_DIR:$AGE_DIR:/usr/bin:/bin'
        . '$_BATS_REAL_SHELL_COMMON/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_SHELL_COMMON/tools/integrations/sops.sh'
        $1
    "
}

_store_zsh() {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -f -c "
        export SHELL_COMMON='$DF/shell-common'
        export SOPS_AGE_KEY_FILE='$SOPS_AGE_KEY_FILE'
        export DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE=1 TERM=dumb
        export HOME='$HOME'
        export PATH='$SOPS_DIR:$AGE_DIR:/usr/bin:/bin'
        . '$_BATS_REAL_SHELL_COMMON/tools/ux_lib/ux_lib.sh'
        . '$_BATS_REAL_SHELL_COMMON/tools/integrations/sops.sh'
        $1
    "
}

@test "set: rejects an invalid KEY name before touching anything" {
    _store "printf 'v' | senv set BAD-KEY --stdin"
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid KEY name"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "set --stdin: commits only .enc.env, pushes, never echoes the value" {
    _store "printf 'NEWSECRET1' | senv set MYKEY --stdin"
    assert_success
    refute_output --partial "NEWSECRET1"
    [ "$(_remote_commits)" -eq 2 ]
    [[ "$(git --git-dir="$REMOTE" log --format=%s -1)" == *"MYKEY"* ]]
    [ "$(git --git-dir="$REMOTE" show --name-only --format= HEAD | tr '\n' '|')" = ".enc.env|" ]
    # the ciphertext never contains the plaintext, not even in history
    if git --git-dir="$REMOTE" log -p | grep -q NEWSECRET1; then
        fail "plaintext leaked into git history"
    fi
    # plaintext .env stays behind (gitignored) and the worktree is otherwise clean
    [ -f "$DF/.env" ]
    [ -z "$(git -C "$DF" status --porcelain)" ]
}

@test "get: prints only the value" {
    _store "senv get EXISTING"
    assert_output "oldval"
}

@test "get: a missing key fails with a senv keys hint" {
    _store "senv get NOPE"
    assert_failure
    [[ "$output" == *"senv keys"* ]]
}

@test "keys: lists key names, never values" {
    _store "senv keys"
    assert_output "EXISTING
EMPTY"
}

@test "set: replacing an existing KEY commits with the update message" {
    _store "printf 'newval2' | senv set EXISTING --stdin"
    assert_success
    [[ "$(git --git-dir="$REMOTE" log --format=%s -1)" == *"갱신"* ]]
    _store "senv get EXISTING"
    assert_output "newval2"
}

@test "set: writing the same value is a no-op" {
    _store "printf 'oldval' | senv set EXISTING --stdin"
    assert_success
    [[ "$output" == *"no change"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "set: without a tty and without --stdin it refuses before reading" {
    _store "senv set ANOTHER </dev/null"
    assert_failure
    [[ "$output" == *"--stdin"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "set: refuses off the default branch, before reading the value" {
    git -C "$DF" switch -q -c feature
    _store "printf 'v' | senv set X1 --stdin"
    assert_failure
    [[ "$output" == *"default branch"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "set: refuses when other changes are staged" {
    printf 'x\n' >"$DF/other"
    git -C "$DF" add other
    _store "printf 'v' | senv set X1 --stdin"
    assert_failure
    [[ "$output" == *"other"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "push: re-encrypts a manual .env edit and commits it" {
    printf '# store fixture\nEXISTING=edited3\nEMPTY=\n' >"$DF/.env"
    _store "senv push"
    assert_success
    [ "$(_remote_commits)" -eq 2 ]
    _store "senv get EXISTING"
    assert_output "edited3"
}

@test "push: an unchanged .env is a no-op" {
    printf '# store fixture\nEXISTING=oldval\nEMPTY=\n' >"$DF/.env"
    _store "senv push"
    assert_success
    [[ "$output" == *"no change"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "push: refuses off the default branch" {
    printf '# store fixture\nEXISTING=oldval\nEMPTY=\n' >"$DF/.env"
    git -C "$DF" switch -q -c feature
    _store "senv push"
    assert_failure
    [[ "$output" == *"default branch"* ]]
    [ "$(_remote_commits)" -eq 1 ]
}

@test "push and keys reject arguments" {
    _store "senv push extra; senv keys extra"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no arguments"* ]]
}

@test "PC2 clone: get extracts a value pushed from the other machine" {
    _store "printf 'CLONEVAL9' | senv set SHARED --stdin"
    assert_success
    local pc2="$TEST_TEMP_HOME/pc2"
    git clone -q "$REMOTE" "$pc2"
    mkdir -p "$pc2/shell-common"
    DF="$pc2"
    _store "senv get SHARED"
    assert_output "CLONEVAL9"
    _store "senv keys"
    [[ "$output" == *"SHARED"* ]]
}

@test "zsh: set --stdin and get round-trip" {
    _store_zsh "printf 'ZSECRET7' | senv set ZKEY --stdin && senv get ZKEY"
    assert_success
    [ "${output##*$'\n'}" = "ZSECRET7" ]
    [ "$(git --git-dir="$REMOTE" show --name-only --format= HEAD | tr '\n' '|')" = ".enc.env|" ]
}
