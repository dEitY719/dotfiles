#!/usr/bin/env bats
# tests/bats/scripts/measure_skill_descriptions.bats
# scripts/measure-skill-descriptions.sh runs the canonical Check 16 from
# authoring-skills (skills/skill-check/lib/skill_check.sh, #2200) and parses its
# row "16<TAB><verdict><TAB><N> characters". A stub skill_check.sh under a fake
# WORKSPACE_ROOT pins that output contract here, so a format change fails loudly
# instead of every skill silently counting as N/A (PR #2220 review).

load '../test_helper'

SCRIPT_UNDER_TEST="${DOTFILES_ROOT}/scripts/measure-skill-descriptions.sh"

setup() {
    setup_isolated_home
    export WORKSPACE_ROOT="${TEST_TEMP_HOME}/ws"
    STUB_DIR="${WORKSPACE_ROOT}/authoring-skills/skills/skill-check/lib"
    mkdir -p "$STUB_DIR" "${TEST_TEMP_HOME}/skills/alpha" "${TEST_TEMP_HOME}/skills/beta"
    : >"${TEST_TEMP_HOME}/skills/alpha/SKILL.md"
    : >"${TEST_TEMP_HOME}/skills/beta/SKILL.md"
}

teardown() {
    teardown_isolated_home
}

# _stub_check16 <shell body> — the body sees the SKILL.md path as $1.
_stub_check16() {
    printf '#!/bin/sh\n%s\n' "$1" >"${STUB_DIR}/skill_check.sh"
}

@test "parses verdict and length from the canonical Check 16 row" {
    _stub_check16 'case "$1" in
*alpha*) printf "3\tPASS\tok\n16\tPASS\t120 characters\n" ;;
*) printf "16\tWARN\t300 characters\n" ;;
esac'
    run bash "$SCRIPT_UNDER_TEST" --skills-dir "${TEST_TEMP_HOME}/skills"
    assert_success
    assert_output --regexp 'alpha +120 PASS'
    assert_output --regexp 'beta +300 WARN'
    assert_output --partial '420'
}

@test "N/A row counts as missing description, not a failure" {
    _stub_check16 'case "$1" in
*alpha*) printf "16\tN/A\tno description\n" ;;
*) printf "16\tPASS\t50 characters\n" ;;
esac'
    run bash "$SCRIPT_UNDER_TEST" --skills-dir "${TEST_TEMP_HOME}/skills"
    assert_success
    assert_output --regexp 'alpha +- N/A'
}

@test "a missing Check 16 row fails instead of reading as N/A" {
    _stub_check16 'printf "3\tPASS\tok\n"'
    run bash "$SCRIPT_UNDER_TEST" --skills-dir "${TEST_TEMP_HOME}/skills"
    assert_failure
    assert_output --partial 'Check 16'
}

@test "missing canonical script fails with a clone hint" {
    run bash "$SCRIPT_UNDER_TEST" --skills-dir "${TEST_TEMP_HOME}/skills"
    assert_failure
    assert_output --partial 'authoring-skills'
}
