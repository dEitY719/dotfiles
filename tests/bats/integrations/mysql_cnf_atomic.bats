#!/usr/bin/env bats
# tests/bats/integrations/mysql_cnf_atomic.bats
# mysql.sh rewrites ~/.my.cnf in every interactive shell. Shells that start
# together (herdr panes) raced on rm -f/touch/chmod and printed
# "chmod: cannot access ~/.my.cnf" (#2429). The rewrite must be an atomic
# same-dir temp file + mv, skipped when the content is unchanged.

load '../test_helper'

MYSQL_SH='$SHELL_COMMON/tools/integrations/mysql.sh'

# Byte-exact output of the pre-#2429 code: each block starts with a blank line.
EXPECTED_CNF='
[client_dmc_dev]
user=dmc_user
password=change_me_strong_pw
host=localhost
database=dmc_playground_dev

[client_dmc_test]
user=dmc_user
password=change_me_strong_pw
host=localhost
database=dmc_playground_test'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# _race <shell...>: source mysql.sh in 20 concurrent processes, wait for all,
# then print every non-empty stderr. Output must be empty.
_race() {
    local i
    mkdir -p "$HOME/err"
    for i in $(seq 1 20); do
        DOTFILES_FORCE_INIT=1 "$@" -c ". \"$MYSQL_SH\"" \
            >/dev/null 2>"$HOME/err/$i" &
    done
    wait
    for i in $(seq 1 20); do
        [ -s "$HOME/err/$i" ] && cat "$HOME/err/$i"
    done
    return 0
}

_check_result() {
    [ "$(stat -c %a "$HOME/.my.cnf")" = "600" ]
    [ "$(cat "$HOME/.my.cnf")" = "$EXPECTED_CNF" ]
    # $(cat) strips trailing newlines; pin the final byte separately.
    [ "$(tail -c 1 "$HOME/.my.cnf" | od -An -c | tr -d ' ')" = '\n' ]
    [ -z "$(find "$HOME" -maxdepth 1 -name '.my.cnf.*')" ]
}

_idempotent() {
    local before after
    "$@" -c ". \"$MYSQL_SH\""
    before=$(stat -c '%i %Y.%y' "$HOME/.my.cnf")
    sleep 1 # mtime has 1s resolution on some filesystems
    "$@" -c ". \"$MYSQL_SH\""
    after=$(stat -c '%i %Y.%y' "$HOME/.my.cnf")
    [ "$before" = "$after" ]
}

@test "bash: 20 concurrent sources of mysql.sh print nothing on stderr" {
    run _race bash --noprofile --norc
    assert_success
    assert_output ""
    _check_result
}

@test "zsh: 20 concurrent sources of mysql.sh print nothing on stderr" {
    run _race zsh -f
    assert_success
    assert_output ""
    _check_result
}

@test "bash: ~/.my.cnf is 600, byte-identical, no temp files left" {
    bash --noprofile --norc -c ". \"$MYSQL_SH\""
    _check_result
}

@test "zsh: ~/.my.cnf is 600, byte-identical, no temp files left" {
    zsh -f -c ". \"$MYSQL_SH\""
    _check_result
}

@test "bash: unchanged content keeps inode and mtime" {
    _idempotent bash --noprofile --norc
}

@test "zsh: unchanged content keeps inode and mtime" {
    _idempotent zsh -f
}

@test "stale content is replaced and permissions tightened to 600" {
    printf 'old\n' >"$HOME/.my.cnf"
    chmod 644 "$HOME/.my.cnf"
    bash --noprofile --norc -c ". \"$MYSQL_SH\""
    _check_result
}
