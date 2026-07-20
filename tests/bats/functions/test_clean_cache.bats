#!/usr/bin/env bats
# tests/bats/functions/test_clean_cache.bats
# Tests for `del_file --cache` added in issue #1216
# (zsh .zcompdump* cache whitelist + stale .zcompdump-*.lock/ dir offer).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "bash: _cleanup_set_cache_patterns covers .zcompdump" {
    run_in_bash '_cleanup_set_cache_patterns; for p in "${CLEANUP_CACHE_PATTERNS[@]}"; do echo "$p"; done'
    assert_success
    assert_output --partial ".zcompdump"
    assert_output --partial ".zcompdump-*"
}

@test "zsh: _cleanup_set_cache_patterns covers .zcompdump" {
    run_in_zsh '_cleanup_set_cache_patterns; for p in "${CLEANUP_CACHE_PATTERNS[@]}"; do echo "$p"; done'
    assert_success
    assert_output --partial ".zcompdump"
    assert_output --partial ".zcompdump-*"
}

@test "bash: del_file --home --cache is rejected as mutually exclusive" {
    run_in_bash 'del_file --home --cache; echo "rc=$?"'
    assert_output --partial "mutually exclusive"
    assert_output --partial "rc=1"
}

@test "bash: del_file --help documents --cache" {
    run_in_bash 'del_file --help'
    assert_success
    assert_output --partial "--cache"
    assert_output --partial ".zcompdump"
}

@test "bash: del_file --cache refuses without an interactive terminal" {
    run_in_bash 'del_file --cache; echo "rc=$?"'
    assert_output --partial "requires an interactive terminal"
    assert_output --partial "rc=1"
}

@test "bash: cache lock dir offer is a no-op when no lock dirs are present" {
    run_in_bash '_cleanup_offer_cache_lock_dirs "$HOME"; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
}

@test "bash: cache lock dir offer finds a stale .zcompdump-*.lock/ dir" {
    mkdir -p "$HOME/.zcompdump-testhost.lock"
    run_in_bash '_cleanup_offer_cache_lock_dirs "$HOME" <<< "n"'
    assert_success
    assert_output --partial ".zcompdump-testhost.lock"
}
