#!/usr/bin/env bats
# tests/bats/functions/help_flag_data_services.bats
# -h/--help on docker/mysql/postgresql/redis commands prints help, exits 0 and
# never reaches the backing CLI (#1916). Before the guard, `dvol_rm -h` ran
# `docker volume rm -h` and `psql_del -h` / `redis_flush -h` treated the flag
# as a target. Every backing binary is stubbed to record any call.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$HOME/stub-bin"
    CALL_LOG="$HOME/calls.log"
    mkdir -p "$STUB_BIN"
    for bin in docker mysql psql redis-cli sudo systemctl service; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$bin" "$CALL_LOG" >"$STUB_BIN/$bin"
        chmod +x "$STUB_BIN/$bin"
    done
    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    teardown_isolated_home
}

@test "destructive dvol_rm / psql_del / redis_flush -h|--help: section help, exit 0, no CLI call (bash + zsh)" {
    local runner flag
    for runner in run_in_bash run_in_zsh; do
        for flag in -h --help; do
            "$runner" "dvol_rm $flag"
            assert_success
            assert_output --partial "volume rm"
            "$runner" "psql_del $flag"
            assert_success
            assert_output --partial "Remove service"
            "$runner" "redis_flush $flag"
            assert_success
            assert_output --partial "Flush data"
        done
    done
    [ ! -e "$CALL_LOG" ]
}

@test "every guarded data-service command -h|--help: exit 0, no CLI call (bash + zsh)" {
    local runner flag fn
    for runner in run_in_bash run_in_zsh; do
        for fn in dcl dcr dcl_errors dbash denv dinspect_env dlog_last \
            mysql_list mysql_cmd mysql_server \
            psql_user psql_db psql_bootstrap psql_server \
            redis_server redis_ping redis_info redis_keys redis_config_get redis_slowlog; do
            for flag in -h --help; do
                "$runner" "$fn $flag"
                assert_success
            done
        done
    done
    [ ! -e "$CALL_LOG" ]
}

@test "psql_user / psql_db dispatch their action (action was hard-wired to empty)" {
    run_in_bash "psql_user list"
    assert_success
    refute_output --partial "PostgreSQL User Management"
    run_in_bash "psql_db list"
    assert_success
    refute_output --partial "PostgreSQL Database Management"
    [ -s "$CALL_LOG" ]
}
