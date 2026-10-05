#!/usr/bin/env bats
# tests/bats/integrations/postgresql_db_delete.bats
# psql_db delete sent `datname = \ AND ...` plus a stray `-v 1=<db>` (#1943).
# psql/sudo are stubbed to log argv (incl. the SQL text); no real server is used.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$HOME/stub-bin"
    CALL_LOG="$HOME/calls.log"
    mkdir -p "$STUB_BIN"
    for bin in psql sudo; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$bin" "$CALL_LOG" >"$STUB_BIN/$bin"
        chmod +x "$STUB_BIN/$bin"
    done
    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    teardown_isolated_home
}

@test "psql_db delete mydb: terminate SQL quotes the name, no backslash or -v 1" {
    local runner
    for runner in run_in_bash run_in_zsh; do
        rm -f "$CALL_LOG"
        "$runner" "printf 'y\n' | psql_db delete mydb"
        assert_success
        run grep 'pg_terminate_backend' "$CALL_LOG"
        assert_success
        assert_output --partial "datname = 'mydb' AND"
        refute_output --partial "\\"
        refute_output --partial '-v 1='
        grep -q 'DROP DATABASE "mydb";' "$CALL_LOG"
    done
}

@test "psql_db delete rejects a non-identifier name without calling psql" {
    local runner
    for runner in run_in_bash run_in_zsh; do
        "$runner" "printf 'y\n' | psql_db delete \"x'; DROP DATABASE y;--\""
        assert_failure
        assert_output --partial "Invalid Database Name"
    done
    [ ! -e "$CALL_LOG" ]
}
