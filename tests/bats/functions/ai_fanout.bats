#!/usr/bin/env bats
# tests/bats/functions/ai_fanout.bats
# ai_fanout_run (#2381): the lane loop moved out of devx_pr_review_all_fanout.
# A stub entry command stands in for a review engine; the core appends the
# lane as its last argument and runs it in <workdir>.
load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_SHELL_COMMON:?}/lib/ai_fanout.sh"
    ENTRY="$TEST_TEMP_HOME/entry.sh"
    cat >"$ENTRY" <<'EOF'
#!/bin/sh
# $1 = fixed arg from the caller, $2 = lane
case "$2" in
ok*) echo "lane stdout $1 $2"; pwd -P >"$OUT_DIR/$2.cwd"; exit 0 ;;
fail) printf '\n  boom:\tbroke  \n' >&2; exit 1 ;;
quiet) exit 4 ;;
hang) sleep 5; exit 0 ;;
esac
EOF
    chmod +x "$ENTRY"
    export OUT_DIR="$TEST_TEMP_HOME/out"
    mkdir -p "$OUT_DIR"
}

teardown() {
    teardown_isolated_home
}

@test "ai_fanout_run: ok and skip lines in lane order, stdout not leaked" {
    run ai_fanout_run "" 30 "ok1,fail,quiet,ok2" "$ENTRY" fixed
    assert_success
    [ "${#lines[@]}" -eq 4 ]
    assert_line --index 0 "ok1:ok"
    assert_line --index 1 "$(printf 'fail:skip\tboom: broke')"
    assert_line --index 2 "$(printf 'quiet:skip\texit 4')"
    assert_line --index 3 "ok2:ok"
}

@test "ai_fanout_run: a hung lane is cut by the timeout" {
    run ai_fanout_run "" 1 "hang,ok1" "$ENTRY" fixed
    assert_success
    assert_line --index 0 "$(printf 'hang:skip\ttimeout 1s')"
    assert_line --index 1 "ok1:ok"
}

@test "ai_fanout_run: lanes run in <workdir>, the caller's cwd is untouched" {
    local wd="$TEST_TEMP_HOME/wd" before="$PWD"
    mkdir -p "$wd"
    run ai_fanout_run "$wd" 30 "ok1,ok:x" "$ENTRY" fixed
    assert_success
    assert_line --index 1 "ok:x:ok"
    [ "$(cat "$OUT_DIR/ok1.cwd")" = "$(cd -P "$wd" && pwd)" ]
    [ "$PWD" = "$before" ]
}

@test "ai_fanout_run: argument errors -> rc 2" {
    run ai_fanout_run "" 30 "" "$ENTRY"
    assert_failure 2
    run ai_fanout_run "" 30 "ok1"
    assert_failure 2
    run ai_fanout_run "" 30 "a/b" "$ENTRY"
    assert_failure 2
    run ai_fanout_run "$TEST_TEMP_HOME/missing" 30 "ok1" "$ENTRY"
    assert_failure 2
    run ai_fanout_run "" 30 "ok1,ok2,ok1" "$ENTRY"
    assert_failure 2
    assert_output --partial "lane repeated: 'ok1'"
}
