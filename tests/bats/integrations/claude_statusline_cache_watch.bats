#!/usr/bin/env bats
# tests/bats/integrations/claude_statusline_cache_watch.bats
#
# claude/statusline-command.sh (#2026): the cache-watch mod writes
# ~/.cache/claude-cache-watch/<session_id> = "<lastTouchEpochSec> <ttlSec>";
# the statusline appends the remaining prompt-cache lifetime right after the
# ⏱️ TTL segment, inside the same usage_group. Missing/corrupt file or empty
# session_id => segment omitted. Timestamps are relative to real `date +%s`;
# the minute ceiling absorbs the few ms between write and render.

load '../test_helper'

setup() {
    setup_isolated_home
    STATUSLINE="${DOTFILES_ROOT}/claude/statusline-command.sh"
    export ENABLE_PROMPT_CACHING_1H=1
    CW_DIR="${HOME}/.cache/claude-cache-watch"
    mkdir -p "$CW_DIR"
}

teardown() {
    teardown_isolated_home
}

_touch_ago() { # <session_id> <seconds ago> <ttl>
    printf '%s %s\n' "$(($(date +%s) - $2))" "$3" >"${CW_DIR}/$1"
}

@test "cache-watch: 3 minutes after touch renders ⏱️ 1h cache 57m" {
    _touch_ago s1 180 3600
    _render_plain '{"session_id":"s1"}'
    assert_success
    assert_output --partial '⏱️ 1h cache 57m'
}

@test "cache-watch: 59m30s after touch renders cache <1m" {
    _touch_ago s1 3570 3600
    _render_plain '{"session_id":"s1"}'
    assert_success
    assert_output --partial '⏱️ 1h cache <1m'
}

@test "cache-watch: past ttl renders cache expired" {
    _touch_ago s1 3700 3600
    _render_plain '{"session_id":"s1"}'
    assert_success
    assert_output --partial '⏱️ 1h cache expired'
}

@test "cache-watch: 5m ttl field renders minutes against 300s" {
    unset ENABLE_PROMPT_CACHING_1H
    _touch_ago s1 60 300
    _render_plain '{"session_id":"s1"}'
    assert_success
    assert_output --partial '⏱️ 5m cache 4m'
}

@test "cache-watch: clock skew (touch in the future) clamps to ttl" {
    _touch_ago s1 -600 3600
    _render_plain '{"session_id":"s1"}'
    assert_success
    assert_output --partial 'cache 60m'
}

@test "cache-watch: no file renders only ⏱️ 1h" {
    _render_plain '{"session_id":"s1"}'
    assert_success
    assert_output --partial '⏱️ 1h'
    refute_output --partial 'cache '
}

@test "cache-watch: corrupt file omits the segment" {
    printf 'garbage 3600\n' >"${CW_DIR}/s1"
    _render_plain '{"session_id":"s1"}'
    assert_success
    assert_output --partial '⏱️ 1h'
    refute_output --partial 'cache '
}

@test "cache-watch: empty session_id omits the segment" {
    # A file named "" can't exist, but the directory itself must not be read.
    _touch_ago s1 180 3600
    _render_plain '{}'
    assert_success
    assert_output --partial '⏱️ 1h'
    refute_output --partial 'cache '
}

@test "cache-watch: color is red once expired" {
    _touch_ago s1 3700 3600
    _render '{"session_id":"s1"}'
    assert_success
    assert_output --partial "$(printf '\033[31m')cache expired"
}
