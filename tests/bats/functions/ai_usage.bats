#!/usr/bin/env bats
# tests/bats/functions/ai_usage.bats
# Unit tests for _ai_usage_run's transient-error retry (issue #651).
#
# Background: PR #726's worker burned $0.28 / 14 turns because a single
# ECONNRESET from the proxy was treated as a permanent failure. The fix
# wraps the claude branch in a retry loop that classifies API errors
# matching ECONNRESET/ETIMEDOUT/EHOSTUNREACH/EAI_AGAIN/"fetch failed" as
# transient and retries up to AI_USAGE_RETRY_TRANSIENT_MAX times.
#
# Strategy: stub `claude` via PATH so each invocation reads
# $CLAUDE_ATTEMPT_COUNTER, increments it, and emits the JSON staged
# under $CLAUDE_RESPONSES_DIR/attempt<N>.json (last file is reused if
# the counter overshoots). Tests verify return code, retry count, and
# usage.jsonl record cardinality. AI_USAGE_RETRY_SLEEP_BASE=0 keeps
# sleeps at zero so tests are fast.

load '../test_helper'

setup() {
    setup_isolated_home
    _setup_claude_stub
}

teardown() {
    teardown_isolated_home
    unset AI_USAGE_RETRY_TRANSIENT_MAX AI_USAGE_RETRY_SLEEP_BASE
}

# Stage a PATH directory with a stubbed `claude` that replays canned
# JSON responses from $CLAUDE_RESPONSES_DIR. The stub bumps a counter
# file on each invocation so a test can assert "called N times".
_setup_claude_stub() {
    STUB_BIN="$TEST_TEMP_HOME/stub-bin"
    CLAUDE_RESPONSES_DIR="$TEST_TEMP_HOME/claude-responses"
    CLAUDE_ATTEMPT_COUNTER="$TEST_TEMP_HOME/claude-attempts"
    USAGE_LOG="$TEST_TEMP_HOME/usage.jsonl"
    mkdir -p "$STUB_BIN" "$CLAUDE_RESPONSES_DIR"
    : >"$CLAUDE_ATTEMPT_COUNTER"

    cat >"$STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
# Stub claude — replay $CLAUDE_RESPONSES_DIR/attempt<N>.json based on
# the counter in $CLAUDE_ATTEMPT_COUNTER. The shape we emit matches
# what `claude --output-format json` would produce.
n=$(cat "$CLAUDE_ATTEMPT_COUNTER" 2>/dev/null)
n=$((${n:-0} + 1))
printf '%s\n' "$n" >"$CLAUDE_ATTEMPT_COUNTER"

response="$CLAUDE_RESPONSES_DIR/attempt${n}.json"
if [ ! -f "$response" ]; then
    # Fall back to the highest-numbered response so "more retries than
    # staged JSON" reuses the last canned answer.
    response=$(ls "$CLAUDE_RESPONSES_DIR"/attempt*.json 2>/dev/null | sort -V | tail -1)
fi
cat "$response"
exit 0
STUB
    chmod +x "$STUB_BIN/claude"
}

# Stage a fake claude JSON response for attempt N.
#   _stage_response <n> transient|permanent|success
_stage_response() {
    local n="$1" kind="$2"
    local file="$CLAUDE_RESPONSES_DIR/attempt${n}.json"
    case "$kind" in
    transient)
        cat >"$file" <<'JSON'
{"is_error":true,"result":"API Error: Unable to connect to API (ECONNRESET)","num_turns":0,"duration_ms":1500,"duration_api_ms":1500,"total_cost_usd":0,"session_id":"sess-transient","usage":{"input_tokens":10,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"modelUsage":{}}
JSON
        ;;
    permanent)
        cat >"$file" <<'JSON'
{"is_error":true,"result":"Authentication failed: invalid API key","num_turns":1,"duration_ms":500,"duration_api_ms":500,"total_cost_usd":0,"session_id":"sess-permanent","usage":{"input_tokens":5,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"modelUsage":{}}
JSON
        ;;
    success)
        cat >"$file" <<'JSON'
{"is_error":false,"result":"ok","num_turns":2,"duration_ms":2000,"duration_api_ms":1900,"total_cost_usd":0.01,"session_id":"sess-ok","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"modelUsage":{"claude-3-5-sonnet":{}}}
JSON
        ;;
    esac
}

# Run _ai_usage_run with the stubbed claude on PATH, retry sleep
# disabled (AI_USAGE_RETRY_SLEEP_BASE=0), and the given env vars.
#   _run_ai_usage [max-retries] [extra exports]
_run_ai_usage() {
    local max="${1:-2}"
    local extra="${2:-}"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:/usr/bin:/bin'
        export CLAUDE_RESPONSES_DIR='${CLAUDE_RESPONSES_DIR}'
        export CLAUDE_ATTEMPT_COUNTER='${CLAUDE_ATTEMPT_COUNTER}'
        export AI_USAGE_RETRY_TRANSIENT_MAX='${max}'
        export AI_USAGE_RETRY_SLEEP_BASE=0
        ${extra}
        . '${DOTFILES_ROOT}/shell-common/functions/ai_usage.sh'
        _ai_usage_run claude '${USAGE_LOG}' 'test-label' 'fake-prompt'
        echo \"rc=\$?\"
    "
}

_attempt_count() {
    cat "$CLAUDE_ATTEMPT_COUNTER" 2>/dev/null || echo 0
}

_usage_record_count() {
    if [ -s "$USAGE_LOG" ]; then
        wc -l <"$USAGE_LOG" | tr -d ' '
    else
        echo 0
    fi
}

# ---------------------------------------------------------------------------
# Classifier — exposed so other call sites can grow their own retry
# loops without re-deriving the pattern set.
# ---------------------------------------------------------------------------

@test "classifier: ECONNRESET is transient" {
    run bash -c ". '${DOTFILES_ROOT}/shell-common/functions/ai_usage.sh' && \
                 _ai_usage_is_transient 'API Error: Unable to connect to API (ECONNRESET)' && \
                 echo transient"
    assert_success
    assert_output --partial "transient"
}

@test "classifier: ETIMEDOUT is transient" {
    run bash -c ". '${DOTFILES_ROOT}/shell-common/functions/ai_usage.sh' && \
                 _ai_usage_is_transient 'fetch failed: ETIMEDOUT' && \
                 echo transient"
    assert_success
    assert_output --partial "transient"
}

@test "classifier: EAI_AGAIN is transient" {
    run bash -c ". '${DOTFILES_ROOT}/shell-common/functions/ai_usage.sh' && \
                 _ai_usage_is_transient 'getaddrinfo EAI_AGAIN api.anthropic.com' && \
                 echo transient"
    assert_success
    assert_output --partial "transient"
}

@test "classifier: 'fetch failed' alone is transient" {
    run bash -c ". '${DOTFILES_ROOT}/shell-common/functions/ai_usage.sh' && \
                 _ai_usage_is_transient 'API Error: fetch failed' && \
                 echo transient"
    assert_success
    assert_output --partial "transient"
}

@test "classifier: auth error is NOT transient" {
    run bash -c ". '${DOTFILES_ROOT}/shell-common/functions/ai_usage.sh' && \
                 if _ai_usage_is_transient 'Authentication failed: invalid API key'; \
                 then echo transient; else echo permanent; fi"
    assert_success
    assert_output --partial "permanent"
}

@test "classifier: empty string is NOT transient" {
    run bash -c ". '${DOTFILES_ROOT}/shell-common/functions/ai_usage.sh' && \
                 if _ai_usage_is_transient ''; \
                 then echo transient; else echo permanent; fi"
    assert_success
    assert_output --partial "permanent"
}

# ---------------------------------------------------------------------------
# Retry loop — the issue #651 fix.
# ---------------------------------------------------------------------------

@test "retry: ECONNRESET twice then success → rc=0, claude called 3 times" {
    _stage_response 1 transient
    _stage_response 2 transient
    _stage_response 3 success

    _run_ai_usage 2

    assert_output --partial "rc=0"
    [ "$(_attempt_count)" -eq 3 ]
    # Each attempt appends one record (2 errors + 1 success).
    [ "$(_usage_record_count)" -eq 3 ]
}

@test "retry: single ECONNRESET then success → rc=0, called 2 times" {
    _stage_response 1 transient
    _stage_response 2 success

    _run_ai_usage 2

    assert_output --partial "rc=0"
    [ "$(_attempt_count)" -eq 2 ]
    [ "$(_usage_record_count)" -eq 2 ]
}

@test "retry: max=0 disables retry (pre-#651 behaviour)" {
    _stage_response 1 transient
    _stage_response 2 success

    _run_ai_usage 0

    # rc=1 because is_error=true and no retry → first record's error
    # propagates as exit 1, identical to pre-#651 behaviour.
    assert_output --partial "rc=1"
    [ "$(_attempt_count)" -eq 1 ]
    [ "$(_usage_record_count)" -eq 1 ]
}

@test "retry: permanent error is NOT retried" {
    _stage_response 1 permanent
    _stage_response 2 success

    _run_ai_usage 2

    # Auth failure doesn't match the transient pattern → first attempt
    # returns 1 immediately, success.json on attempt 2 is never read.
    assert_output --partial "rc=1"
    [ "$(_attempt_count)" -eq 1 ]
    [ "$(_usage_record_count)" -eq 1 ]
}

@test "retry: exhausts max retries → rc=1 with full attempt budget" {
    # All attempts return transient → loop hits the budget and returns
    # the final is_error as failure. claude is called max+1 times
    # (initial attempt + max retries).
    _stage_response 1 transient
    _stage_response 2 transient
    _stage_response 3 transient

    _run_ai_usage 2

    assert_output --partial "rc=1"
    [ "$(_attempt_count)" -eq 3 ]
    [ "$(_usage_record_count)" -eq 3 ]
}

@test "retry: success on first attempt → no retry, 1 record" {
    _stage_response 1 success

    _run_ai_usage 2

    assert_output --partial "rc=0"
    [ "$(_attempt_count)" -eq 1 ]
    [ "$(_usage_record_count)" -eq 1 ]
}

@test "retry: each retry writes its own usage.jsonl record (cost tracking preserved)" {
    # The issue's main constraint: retries must not silently drop their
    # cost records — the worker still needs to see every API call in
    # usage.jsonl so the summary's `claude.total_cost_usd` adds up.
    _stage_response 1 transient
    _stage_response 2 success

    _run_ai_usage 2

    assert_output --partial "rc=0"
    # 2 records. Both must have session_id (which proves jq parsed them
    # rather than falling through to the cli_failed shim).
    [ "$(jq -s 'length' "$USAGE_LOG")" = "2" ]
    [ "$(jq -s '[.[] | select(.session_id != null)] | length' "$USAGE_LOG")" = "2" ]
}
