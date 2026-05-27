#!/usr/bin/env bats
# tests/bats/functions/docker_help_recommend.bats
# Regression test for issue #777 — docker-help PWD-aware compose recommendation.
# Covers AC cases A-E plus `here` subcommand and non-compose regressions.

load '../test_helper'

setup() {
    setup_isolated_home
    TEST_PWD="$(mktemp -d)"
}

teardown() {
    if [ -n "$TEST_PWD" ] && [ -d "$TEST_PWD" ]; then
        rm -rf "$TEST_PWD"
    fi
    teardown_isolated_home
}

@test "bash: case A — base + fake variant → fake overlay command" {
    : >"$TEST_PWD/docker-compose.yml"
    : >"$TEST_PWD/docker-compose.fake.yml"
    run_in_bash "cd '$TEST_PWD' && docker_help"
    assert_success
    assert_output --partial "docker compose -f docker-compose.yml -f docker-compose.fake.yml up -d --build"
}

@test "bash: case B — base only → simple up command" {
    : >"$TEST_PWD/docker-compose.yml"
    run_in_bash "cd '$TEST_PWD' && docker_help"
    assert_success
    assert_output --partial "docker compose up -d --build"
    refute_output --partial "-f docker-compose.yml -f"
}

@test "bash: case C — base + 2 variants without fake → no single recommendation + helper hint" {
    : >"$TEST_PWD/docker-compose.yml"
    : >"$TEST_PWD/docker-compose.dev.yml"
    : >"$TEST_PWD/docker-compose.prod.yml"
    run_in_bash "cd '$TEST_PWD' && docker_help"
    assert_success
    refute_output --partial "Recommended command"
    assert_output --partial "Candidate compose files"
    assert_output --partial "docker-compose.dev.yml"
    assert_output --partial "docker-compose.prod.yml"
    assert_output --partial "helper scripts"
}

@test "bash: case D — no compose file → existing summary (regression)" {
    run_in_bash "cd '$TEST_PWD' && docker_help"
    assert_success
    assert_output --partial "Usage: docker-help [section|--list|--all]"
    refute_output --partial "Recommended command"
    refute_output --partial "Detected Docker Compose"
}

@test "bash: case E — compose.yml (new-style) only → simple up command" {
    : >"$TEST_PWD/compose.yml"
    run_in_bash "cd '$TEST_PWD' && docker_help"
    assert_success
    assert_output --partial "docker compose up -d --build"
    assert_output --partial "base:    compose.yml"
}

@test "bash: case A via 'docker-help here' explicit invocation" {
    : >"$TEST_PWD/docker-compose.yml"
    : >"$TEST_PWD/docker-compose.fake.yml"
    run_in_bash "cd '$TEST_PWD' && docker_help here"
    assert_success
    assert_output --partial "docker compose -f docker-compose.yml -f docker-compose.fake.yml up -d --build"
}

@test "bash: 'docker-help here' in empty dir reports no compose files" {
    run_in_bash "cd '$TEST_PWD' && docker_help here"
    assert_failure
    assert_output --partial "No Docker Compose files"
}

@test "bash: regression — docker-help compose unchanged" {
    run_in_bash "cd '$TEST_PWD' && docker_help compose"
    assert_success
    assert_output --partial "dcud"
}

@test "bash: regression — docker-help --all unchanged" {
    run_in_bash "cd '$TEST_PWD' && docker_help --all"
    assert_success
    assert_output --partial "Docker Compose Basics"
}

@test "bash: regression — docker-help --help unchanged" {
    run_in_bash "cd '$TEST_PWD' && docker_help --help"
    assert_success
    assert_output --partial "Usage: docker-help [section|--list|--all]"
}

@test "zsh: case A — base + fake variant → fake overlay command" {
    : >"$TEST_PWD/docker-compose.yml"
    : >"$TEST_PWD/docker-compose.fake.yml"
    run_in_zsh "cd '$TEST_PWD' && docker_help"
    assert_success
    assert_output --partial "docker compose -f docker-compose.yml -f docker-compose.fake.yml up -d --build"
}

@test "zsh: case D — no compose file → existing summary (regression)" {
    run_in_zsh "cd '$TEST_PWD' && docker_help"
    assert_success
    assert_output --partial "Usage: docker-help [section|--list|--all]"
    refute_output --partial "Recommended command"
}

@test "zsh: case E — compose.yml (new-style) only → simple up command" {
    : >"$TEST_PWD/compose.yml"
    run_in_zsh "cd '$TEST_PWD' && docker_help"
    assert_success
    assert_output --partial "docker compose up -d --build"
}
