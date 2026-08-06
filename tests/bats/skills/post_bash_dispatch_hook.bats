#!/usr/bin/env bats
# tests/bats/skills/post_bash_dispatch_hook.bats
# Verify the PostToolUse:Bash dispatcher documented in
#   claude/hooks/post-bash-dispatch.sh
# routes each event to the correct handler (or to none), forwarding the
# untouched stdin JSON. Issue #1144.
#
# POST_BASH_DISPATCH_DIR points the dispatcher at stub handlers that record
# which one was entered plus the exact stdin they received — so the real
# board-sync / manifest-sync logic never runs and cannot mask a routing bug.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/post-bash-dispatch.sh"

setup() {
    setup_isolated_home
    STUB_DIR="$TEST_TEMP_HOME/hooks"
    mkdir -p "$STUB_DIR"
    ROUTE_LOG="$TEST_TEMP_HOME/route.log"
    : > "$ROUTE_LOG"
    cat > "$STUB_DIR/post-gh-pr-create.sh" <<EOF
#!/usr/bin/env bash
printf 'pr-create:%s\n' "\$(cat)" >> "$ROUTE_LOG"
EOF
    cat > "$STUB_DIR/plugin-sync.sh" <<EOF
#!/usr/bin/env bash
printf 'plugin-sync:%s\n' "\$(cat)" >> "$ROUTE_LOG"
EOF
    chmod +x "$STUB_DIR/post-gh-pr-create.sh" "$STUB_DIR/plugin-sync.sh"
    export POST_BASH_DISPATCH_DIR="$STUB_DIR"
    # Pin the #1258 stage-timing log inside the isolated HOME. setup_isolated_home
    # does not touch XDG_STATE_HOME, so without this an inherited value would
    # send test writes to the real ~/.local/state.
    export XDG_STATE_HOME="$TEST_TEMP_HOME/state"
    TIMING_LOG="$XDG_STATE_HOME/claude/post-bash-dispatch-timing.log"
}

teardown() {
    teardown_isolated_home
    unset POST_BASH_DISPATCH_DIR XDG_STATE_HOME
}

@test "dispatch: non-matching Bash command → no handler spawned, exit 0" {
    payload='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
    # #1258: the common path must stay write-free — instrumenting every Bash
    # call would reintroduce exactly the per-call overhead #1144 removed.
    [ ! -e "$TIMING_LOG" ]
}

@test "dispatch: gh pr create → only post-gh-pr-create entered" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title foo"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^pr-create:' "$ROUTE_LOG"
    ! grep -q '^plugin-sync:' "$ROUTE_LOG"
}

@test "dispatch: env-prefixed gh pr create still routes (#390 word-boundary)" {
    payload='{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=x gh pr create --draft"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^pr-create:' "$ROUTE_LOG"
}

@test "dispatch: claude plugin install → only plugin-sync entered" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install foo@bar"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -q '^plugin-sync:' "$ROUTE_LOG"
    ! grep -q '^pr-create:' "$ROUTE_LOG"
}

@test "dispatch: non-Bash tool → immediate exit, no handler" {
    payload='{"tool_name":"Read","tool_input":{"command":"gh pr create"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
}

@test "dispatch: empty stdin → exit 0, no handler" {
    run bash -c "printf '' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
}

@test "dispatch: stdin forwarded verbatim to the routed handler" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"},"tool_response":{"output":"https://github.com/o/r/pull/1"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    grep -qF "pr-create:$payload" "$ROUTE_LOG"
}

@test "dispatch: non-executable handler → silent no-op, exit 0 (PR #1145 gemini)" {
    # Defensive: a missing/non-executable handler must be a silent no-op, not
    # stderr noise + a non-zero pipeline. Strip +x so the -x guard skips it.
    chmod -x "$STUB_DIR/post-gh-pr-create.sh"
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -s "$ROUTE_LOG" ]
    # No handler ran → nothing to time.
    [ ! -e "$TIMING_LOG" ]
}

# ---------------------------------------------------------------------------
# Issue #1258 — stage-timing instrumentation (routed path only)
# ---------------------------------------------------------------------------

@test "timing (#1258): routed gh pr create → one stage-timing line" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title foo"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ -s "$TIMING_LOG" ]
    [ "$(wc -l < "$TIMING_LOG")" -eq 1 ]
    # Format: <entry-ms> <pre-invoke-ms> <post-exit-ms> <handler>
    run cat "$TIMING_LOG"
    assert_output --regexp '^[0-9]+ [0-9]+ [0-9]+ post-gh-pr-create\.sh$'
    # Monotonic, and plausible epoch-ms (13 digits) rather than seconds.
    read -r t_entry t_pre t_post _ < "$TIMING_LOG"
    [ "$t_entry" -le "$t_pre" ]
    [ "$t_pre" -le "$t_post" ]
    [ "${#t_entry}" -ge 13 ]
}

@test "timing (#1258): routed claude plugin → line names plugin-sync.sh" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install foo@bar"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run cat "$TIMING_LOG"
    assert_output --regexp '^[0-9]+ [0-9]+ [0-9]+ plugin-sync\.sh$'
}

@test "timing (#1258): repeated routing appends, one line per invocation" {
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}'
    for _ in 1 2 3; do
        run bash -c "printf '%s' '$payload' | '$HOOK'"
        assert_success
    done
    [ "$(wc -l < "$TIMING_LOG")" -eq 3 ]
}

@test "timing (#1258): unwritable state dir → still exit 0, no stderr noise" {
    # Best-effort contract: a log-write failure must never surface to the user.
    export XDG_STATE_HOME=/proc/nonexistent-state-dir
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    assert_output ''
    # The handler still ran — logging is strictly a side channel.
    grep -q '^pr-create:' "$ROUTE_LOG"
}

@test "timing (#1258): missing lib/pbd_ms.sh → still exit 0, handler still runs" {
    # The dispatcher resolves lib/pbd_ms.sh from its OWN directory, so a lone
    # copy simulates a partial deployment. Its fallback stub must still ASSIGN
    # the output variable: under `set -u` a bare `_pbd_ms() { :; }` leaves
    # _pbd_log_timing's `local _entry` unset and the hook dies 1 with stderr
    # noise — the exact opposite of the best-effort contract.
    local lone="$TEST_TEMP_HOME/lone"
    mkdir -p "$lone"
    cp "$HOOK" "$lone/post-bash-dispatch.sh"
    payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}'
    run bash -c "printf '%s' '$payload' | '$lone/post-bash-dispatch.sh'"
    assert_success
    assert_output ''
    grep -q '^pr-create:' "$ROUTE_LOG"
    # Timings degrade to empty fields, which hook-perf-report.sh drops as a
    # malformed row — never a fake 0ms measurement that would skew the stats.
    run cat "$TIMING_LOG"
    assert_output --regexp '^[[:space:]]*post-gh-pr-create\.sh$'
}

# ---------------------------------------------------------------------------
# Issue #1258 — claude/tools/hook-perf-report.sh, the regression-measurement
# reader for the log the dispatcher above writes. Kept in this file because
# the two halves share one format contract; the script's transcript discovery
# is exercised through its --roots / --timing-log overrides.
# ---------------------------------------------------------------------------

REPORT="${_BATS_REAL_DOTFILES_ROOT}/claude/tools/hook-perf-report.sh"

@test "hook-perf-report (#1258): nearest-rank percentiles over a known sample" {
    # 10 samples 10..100 → p50=v[5], p90=v[9], p99=v[10].
    run bash -c "printf '%s\n' 30 10 100 20 40 90 50 80 60 70 | { . '$REPORT'; hook_perf_stats; }"
    assert_success
    assert_output '10 10 50 90 100 100'
}

@test "hook-perf-report (#1258): empty / non-numeric input → zeroed stats" {
    run bash -c "printf '' | { . '$REPORT'; hook_perf_stats; }"
    assert_success
    assert_output '0 0 0 0 0 0'
    run bash -c "printf '%s\n' 'null' '' 'abc' 12 | { . '$REPORT'; hook_perf_stats; }"
    assert_success
    assert_output '1 12 12 12 12 12'
}

@test "hook-perf-report (#1258): stage-log deltas skip malformed rows" {
    printf '%s\n' \
        '1000 1010 1500 post-gh-pr-create.sh' \
        '2000 2005 2400 plugin-sync.sh' \
        'garbage line' \
        '3000 x 3400 post-gh-pr-create.sh' > "$TEST_TEMP_HOME/stage.log"
    run bash -c '
        . "$1"
        TIMING_LOG="$2"
        _timing_deltas 2 1
    ' _ "$REPORT" "$TEST_TEMP_HOME/stage.log"
    assert_success
    assert_output "$(printf '10\n5')"
}

@test "hook-perf-report (#1258): synthetic transcripts → median/p99 verdict" {
    local proj="$TEST_TEMP_HOME/transcripts/-home-x"
    mkdir -p "$proj"
    _attach() {
        printf '{"type":"attachment","attachment":{"type":"hook_success","hookName":"PostToolUse:Bash","hookEvent":"PostToolUse","command":"${HOME}/dotfiles/claude/hooks/post-bash-dispatch.sh","durationMs":%s}}\n' "$1"
    }
    { _attach 100; _attach 120; _attach 140; } > "$proj/a.jsonl"
    run bash "$REPORT" --roots "$TEST_TEMP_HOME/transcripts" \
        --timing-log "$TEST_TEMP_HOME/absent.log"
    assert_success
    assert_output --partial 'n=3'
    assert_output --partial 'PASS  median 120ms'
    assert_output --partial 'PASS  p99 140ms'

    # Same shape, but over the #1258 budget → FAIL + non-zero exit.
    { _attach 7800; _attach 48700; } > "$proj/a.jsonl"
    run bash "$REPORT" --roots "$TEST_TEMP_HOME/transcripts" \
        --timing-log "$TEST_TEMP_HOME/absent.log"
    assert_failure
    assert_output --partial 'FAIL  median'
    assert_output --partial 'FAIL  p99'
}

@test "hook-perf-report (#1258): no matching attachments → NO DATA, exit 0" {
    mkdir -p "$TEST_TEMP_HOME/transcripts"
    run bash "$REPORT" --roots "$TEST_TEMP_HOME/transcripts" \
        --timing-log "$TEST_TEMP_HOME/absent.log"
    assert_success
    assert_output --partial 'VERDICT: NO DATA'
}

@test "hook-perf-report (#1258): --help exits 0" {
    run bash "$REPORT" --help
    assert_success
    assert_output --partial 'Usage: hook-perf-report.sh'
}
