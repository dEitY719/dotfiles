#!/usr/bin/env bats
# tests/bats/integrations/postgresql_sql_inputs.bats
# Every user-supplied identifier is validated before SQL interpolation, and
# passwords are quoted as escaped string literals (#1963).
# psql/sudo are stubbed to log argv (incl. the SQL text); no real server is used.

load '../test_helper'

BAD="x'; DROP DATABASE y;--"

setup() {
    setup_isolated_home
    STUB_BIN="$HOME/stub-bin"
    CALL_LOG="$HOME/calls.log"
    mkdir -p "$STUB_BIN"
    # Each stub drains a piped stdin like the real psql: _admin_sql probes
    # with `printf '\q' | psql` under pipefail, and a stub that exits unread
    # lets that printf die of SIGPIPE under load ("Cannot connect to
    # PostgreSQL as superuser" flake in a parallel run, #2054).
    for bin in psql sudo; do
        printf '#!/bin/sh\n[ -t 0 ] || cat >/dev/null\necho "%s $*" >>"%s"\n' "$bin" "$CALL_LOG" >"$STUB_BIN/$bin"
        chmod +x "$STUB_BIN/$bin"
    done
    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    teardown_isolated_home
}

# $1 = command, $2 = expected error fragment; asserts no psql/sudo call happened.
assert_rejected() {
    local runner
    for runner in run_in_bash run_in_zsh; do
        rm -f "$CALL_LOG"
        "$runner" "$1"
        assert_failure
        assert_output --partial "$2"
        [ ! -e "$CALL_LOG" ]
    done
}

@test "psql_user rename: valid names produce quoted ALTER USER" {
    local runner
    for runner in run_in_bash run_in_zsh; do
        rm -f "$CALL_LOG"
        "$runner" "psql_user rename old_u new_u"
        assert_success
        grep -qF 'ALTER USER "old_u" RENAME TO "new_u";' "$CALL_LOG"
    done
}

@test "psql_user rename rejects injection or spaces in either name" {
    assert_rejected "psql_user rename \"$BAD\" new_u" "Invalid Username"
    assert_rejected "psql_user rename old_u 'a b'" "Invalid Username"
}

@test "psql_db grant: valid names produce quoted GRANTs on the right DB" {
    local runner
    for runner in run_in_bash run_in_zsh; do
        rm -f "$CALL_LOG"
        "$runner" "psql_db grant mydb bob"
        assert_success
        grep -qF -- '-d mydb -c GRANT CONNECT ON DATABASE "mydb" TO "bob";' "$CALL_LOG"
        grep -qF 'GRANT ALL ON FUNCTIONS TO "bob";' "$CALL_LOG"
    done
}

@test "psql_db grant rejects injection in db or user" {
    assert_rejected "psql_db grant \"$BAD\" bob" "Invalid Database Name"
    assert_rejected "psql_db grant mydb \"bo'b\"" "Invalid Username"
}

@test "psql_db create: valid owner produces quoted OWNER clause" {
    local runner
    for runner in run_in_bash run_in_zsh; do
        rm -f "$CALL_LOG"
        "$runner" "psql_db create mydb bob"
        assert_success
        grep -qF 'CREATE DATABASE "mydb" OWNER "bob";' "$CALL_LOG"
    done
}

@test "psql_db create rejects an invalid owner" {
    assert_rejected "psql_db create mydb \"$BAD\"" "Invalid Owner"
}

@test "psql_user create/passwd: password quotes are escaped as SQL literal" {
    local runner
    for runner in run_in_bash run_in_zsh; do
        rm -f "$CALL_LOG"
        "$runner" "printf '%s\n' \"it's\\\$\\\$pw\" | psql_user create bob"
        assert_success
        grep -qF "CREATE USER \"bob\" WITH PASSWORD 'it''s\$\$pw';" "$CALL_LOG"
        rm -f "$CALL_LOG"
        "$runner" "printf '%s\n' \"it's\" | psql_user passwd bob"
        assert_success
        grep -qF "ALTER USER \"bob\" WITH PASSWORD 'it''s';" "$CALL_LOG"
    done
}

@test "psql_bootstrap: password with \$\$ and quote is escaped, not dollar-quoted" {
    run_in_bash "psql_bootstrap mydb bob \"p'w\\\$\\\$x\" myalias"
    assert_success
    grep -qF "CREATE USER \"bob\" WITH PASSWORD 'p''w\$\$x';" "$CALL_LOG"
}
