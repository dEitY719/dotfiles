#!/usr/bin/env bats
# tests/bats/functions/zsh_p10k_cache.bats
# Regression test for issue #705 — `_zsh_clear_p10k_caches` must remove
# every p10k cache variant (instant-prompt + dump + .zwc + per-user dir),
# not just the single `p10k-instant-prompt-${USER}.zsh` file that the
# prior cleaner targeted.

load '../test_helper'

setup() {
    setup_isolated_home
    # setup_isolated_home points XDG_CACHE_HOME at TEST_TEMP_HOME (a flat
    # dir, not $HOME/.cache); the cleaner reads XDG_CACHE_HOME directly,
    # so we stage fixtures there.
    P10K_CACHE_DIR="$XDG_CACHE_HOME"
    mkdir -p "$P10K_CACHE_DIR"
}

teardown() {
    teardown_isolated_home
}

_stage_all_fixtures() {
    # Use literal $USER from the env so the cleaner's pattern matches.
    : >"${P10K_CACHE_DIR}/p10k-instant-prompt-${USER}.zsh"
    : >"${P10K_CACHE_DIR}/p10k-instant-prompt-${USER}.zsh.zwc"
    : >"${P10K_CACHE_DIR}/p10k-dump-${USER}.zsh"
    : >"${P10K_CACHE_DIR}/p10k-dump-${USER}.zsh.zwc"
    mkdir -p "${P10K_CACHE_DIR}/p10k-${USER}"
    : >"${P10K_CACHE_DIR}/p10k-${USER}/state"
}

@test "bash: _zsh_clear_p10k_caches function exists" {
    run_in_bash 'declare -f _zsh_clear_p10k_caches >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _zsh_clear_p10k_caches function exists" {
    run_in_zsh 'declare -f _zsh_clear_p10k_caches >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: zsh-clear-p10k-caches alias exists" {
    run_in_bash 'alias zsh-clear-p10k-caches'
    assert_success
}

@test "bash: cleaner removes instant-prompt .zsh and .zwc" {
    _stage_all_fixtures
    run_in_bash '_zsh_clear_p10k_caches'
    assert_success
    [ ! -e "${P10K_CACHE_DIR}/p10k-instant-prompt-${USER}.zsh" ]
    [ ! -e "${P10K_CACHE_DIR}/p10k-instant-prompt-${USER}.zsh.zwc" ]
}

@test "bash: cleaner removes dump .zsh and .zwc (issue #705 core regression)" {
    _stage_all_fixtures
    run_in_bash '_zsh_clear_p10k_caches'
    assert_success
    # The prior cleaner missed these two files — they are the heart of #705.
    [ ! -e "${P10K_CACHE_DIR}/p10k-dump-${USER}.zsh" ]
    [ ! -e "${P10K_CACHE_DIR}/p10k-dump-${USER}.zsh.zwc" ]
}

@test "bash: cleaner removes per-user p10k scratch dir" {
    _stage_all_fixtures
    run_in_bash '_zsh_clear_p10k_caches'
    assert_success
    [ ! -d "${P10K_CACHE_DIR}/p10k-${USER}" ]
}

@test "bash: cleaner reports total artifact count (5 fixtures → 5)" {
    _stage_all_fixtures
    run_in_bash '_zsh_clear_p10k_caches'
    assert_success
    # 4 files + 1 dir = 5 artifacts removed.
    assert_output "5"
}

@test "bash: cleaner reports 0 when nothing to remove" {
    run_in_bash '_zsh_clear_p10k_caches'
    assert_success
    assert_output "0"
}

@test "bash: zsh_clear_p10k_caches prints 'No p10k caches' when empty" {
    run_in_bash 'zsh_clear_p10k_caches'
    assert_success
    assert_output --partial "No p10k caches"
}

@test "bash: zsh_clear_p10k_caches prints cleared count when fixtures present" {
    _stage_all_fixtures
    run_in_bash 'zsh_clear_p10k_caches'
    assert_success
    assert_output --partial "Cleared p10k caches"
    assert_output --partial "5 artifact"
}

@test "zsh: cleaner removes dump .zsh and .zwc (issue #705 core regression)" {
    _stage_all_fixtures
    run_in_zsh '_zsh_clear_p10k_caches'
    assert_success
    [ ! -e "${P10K_CACHE_DIR}/p10k-dump-${USER}.zsh" ]
    [ ! -e "${P10K_CACHE_DIR}/p10k-dump-${USER}.zsh.zwc" ]
}
