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

# _stat <gnu-fmt> <bsd-fmt> <file>: GNU stat -c first, BSD/macOS stat -f.
_stat() {
    stat -c "$1" "$3" 2>/dev/null || stat -f "$2" "$3"
}

# _race <shell...>: source mysql.sh in 20 concurrent processes, wait for all,
# then print every non-zero exit and non-empty stderr. Output must be empty.
_race() {
    local i pids=()
    mkdir -p "$HOME/err"
    for i in $(seq 1 20); do
        DOTFILES_FORCE_INIT=1 "$@" -c ". \"$MYSQL_SH\"" \
            >/dev/null 2>"$HOME/err/$i" &
        pids+=("$!")
    done
    # Explicit PIDs: a bare wait also blocks on bats' timeout watchdog (#2054).
    # One wait per PID: a multi-PID wait reports only the last status.
    for i in "${pids[@]}"; do
        wait "$i" || echo "pid $i exited $?"
    done
    for i in $(seq 1 20); do
        [ -s "$HOME/err/$i" ] && cat "$HOME/err/$i"
    done
    return 0
}

_check_result() {
    [ "$(_stat %a %Lp "$HOME/.my.cnf")" = "600" ]
    [ "$(cat "$HOME/.my.cnf")" = "$EXPECTED_CNF" ]
    # $(cat) strips trailing newlines; pin the final byte separately.
    [ "$(tail -c 1 "$HOME/.my.cnf" | od -An -c | tr -d ' ')" = '\n' ]
    [ -z "$(find "$HOME" -maxdepth 1 -name '.my.cnf.*')" ]
}

_idempotent() {
    local before after
    "$@" -c ". \"$MYSQL_SH\""
    # Backdate instead of sleeping: a rewrite would reset mtime to now.
    touch -t 200001010000 "$HOME/.my.cnf"
    before=$(_stat '%i %Y' '%i %m' "$HOME/.my.cnf")
    "$@" -c ". \"$MYSQL_SH\""
    after=$(_stat '%i %Y' '%i %m' "$HOME/.my.cnf")
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

@test "unchanged content with mode 644 is tightened to 600 in place" {
    bash --noprofile --norc -c ". \"$MYSQL_SH\""
    chmod 644 "$HOME/.my.cnf"
    before=$(_stat %i %i "$HOME/.my.cnf")
    bash --noprofile --norc -c ". \"$MYSQL_SH\""
    [ "$(_stat %i %i "$HOME/.my.cnf")" = "$before" ]
    _check_result
}
