#!/usr/bin/env bats
# tests/bats/lint/agents_md_lines.bats
# Issue #2152 — scripts/lint_agents_md_lines.sh 회귀 가드.
# AGENTS.md 는 100줄 미만(99줄까지 PASS, 100줄부터 FAIL). 각 FAIL 케이스는 양성 대조를 둔다.

load '../test_helper'

LINTER="${_BATS_REAL_DOTFILES_ROOT}/scripts/lint_agents_md_lines.sh"

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/sub"
    git -C "$REPO" init -q
}

# $1 = 경로, $2 = 줄 수
write_lines() {
    seq "$2" >"$REPO/$1"
    git -C "$REPO" add "$1"
}

run_linter() {
    cd "$REPO" && run sh "$LINTER"
}

@test "AGENTS.md files under 100 lines pass" {
    write_lines AGENTS.md 99
    write_lines sub/AGENTS.md 10
    run_linter
    assert_success
    assert_output --partial "checked=2 errors=0"
}

@test "a 101-line AGENTS.md fails" {
    write_lines AGENTS.md 10
    write_lines sub/AGENTS.md 101
    run_linter
    assert_failure 1
    assert_output --partial "FAIL  sub/AGENTS.md — 101줄"
}

@test "exactly 100 lines fails (rule is under 100)" {
    write_lines AGENTS.md 100
    run_linter
    assert_failure 1
}

@test "missing trailing newline is still counted" {
    printf '%s' "$(seq 100)" >"$REPO/AGENTS.md"
    git -C "$REPO" add AGENTS.md
    run_linter
    assert_failure 1
}

@test "CLAUDE.md over 100 lines is reported but does not fail" {
    write_lines AGENTS.md 5
    write_lines CLAUDE.md 150
    run_linter
    assert_success
    assert_output --partial "info  CLAUDE.md — 150줄"
}

@test "only files named exactly AGENTS.md are checked" {
    write_lines AGENTS.md 5
    write_lines sub/MY_AGENTS.md 150
    run_linter
    assert_success
}

@test "running from a subdirectory still checks the whole repo" {
    write_lines AGENTS.md 120
    cd "$REPO/sub" && run sh "$LINTER"
    assert_failure 1
    assert_output --partial "FAIL  AGENTS.md"
}

@test "untracked AGENTS.md is ignored" {
    write_lines AGENTS.md 5
    seq 200 >"$REPO/sub/AGENTS.md"
    run_linter
    assert_success
}
