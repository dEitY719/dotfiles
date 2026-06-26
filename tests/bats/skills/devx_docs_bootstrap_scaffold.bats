#!/usr/bin/env bats
# tests/bats/skills/devx_docs_bootstrap_scaffold.bats
# Offline coverage for claude/skills/devx-docs-bootstrap/lib/scaffold.sh (#1028).

load '../test_helper'

SCAFFOLD="${DOTFILES_ROOT}/claude/skills/devx-docs-bootstrap/lib/scaffold.sh"

setup() {
    setup_isolated_home
    WORK="${TEST_TEMP_HOME}/repo"
    mkdir -p "$WORK"
}

teardown() {
    teardown_isolated_home
}

run_scaffold() {
    # Pass args as real positional parameters (not interpolated into the -c
    # string) so a zero-arg call stays zero-arg — `printf '%q ' "$@"` would
    # emit one empty token, making scaffold.sh target "/docs" (gemini PR
    # #1030 review).
    run bash -c 'cd "$1"; shift; NO_COLOR=1 bash "$@"' bash "$WORK" "$SCAFFOLD" "$@"
}

LEAVES="adr product design architecture/system architecture/features testing guides public"

@test "script exists and is executable" {
    [ -f "$SCAFFOLD" ]
    [ -x "$SCAFFOLD" ] || head -1 "$SCAFFOLD" | grep -q '^#!'
}

@test "--help prints usage and writes nothing" {
    run_scaffold --help
    assert_success
    assert_output --partial "devx:docs-bootstrap"
    assert_output --partial "Mode"
    [ ! -d "${WORK}/docs" ]
}

@test "dry-run (default) prints a create plan but writes nothing" {
    run_scaffold
    assert_success
    assert_output --partial "[dry-run]"
    assert_output --partial "create"
    # Zero-arg call must keep TARGET="." (→ ./docs under $WORK), NOT collapse
    # to "" which would target the system-root /docs (gemini PR #1030 review).
    assert_output --partial "Plan for ./docs/"
    refute_output --partial "Plan for /docs/"
    [ ! -d "${WORK}/docs" ]
}

@test "rejects an empty target path" {
    run bash -c 'NO_COLOR=1 bash "$1" "" --apply' bash "$SCAFFOLD"
    assert_failure
    assert_output --partial "Target path cannot be empty"
}

@test "rejects multiple target paths" {
    run_scaffold "${TEST_TEMP_HOME}/a" "${TEST_TEMP_HOME}/b" --apply
    assert_failure
    assert_output --partial "Multiple target paths"
}

@test "--apply creates all 8 leaf dirs with .gitkeep and a README" {
    run_scaffold --apply
    assert_success
    assert_output --partial "[OK]"
    for d in $LEAVES; do
        [ -d "${WORK}/docs/${d}" ] || { echo "missing dir ${d}"; return 1; }
        [ -f "${WORK}/docs/${d}/.gitkeep" ] || { echo "missing gitkeep ${d}"; return 1; }
    done
    [ -f "${WORK}/docs/README.md" ]
    grep -q "문서 관리 정책" "${WORK}/docs/README.md"
    # architecture/ itself is a parent, not a leaf — it has no own .gitkeep
    [ ! -f "${WORK}/docs/architecture/.gitkeep" ]
}

@test "--check fails on an empty repo, passes after --apply" {
    run_scaffold --check
    assert_failure
    assert_output --partial "missing"

    run_scaffold --apply
    assert_success

    run_scaffold --check
    assert_success
    assert_output --partial "conforms"
}

@test "re-running --apply is idempotent (skips existing)" {
    run_scaffold --apply
    assert_success
    run_scaffold --apply
    assert_success
    assert_output --partial "skip"
    assert_output --partial "(exists)"
}

@test "README is not overwritten without --force, overwritten with --force" {
    run_scaffold --apply
    assert_success
    printf 'CUSTOM EDIT\n' >"${WORK}/docs/README.md"

    run_scaffold --apply
    assert_success
    grep -q "CUSTOM EDIT" "${WORK}/docs/README.md"

    run_scaffold --apply --force
    assert_success
    ! grep -q "CUSTOM EDIT" "${WORK}/docs/README.md"
    grep -q "문서 관리 정책" "${WORK}/docs/README.md"
}

@test "--check overrides --apply and stays read-only" {
    run_scaffold --check --apply
    assert_failure
    assert_output --partial "read-only audit wins"
    [ ! -d "${WORK}/docs" ]
}

@test "accepts an explicit target path argument" {
    run_scaffold "${TEST_TEMP_HOME}/other" --apply
    assert_success
    [ -d "${TEST_TEMP_HOME}/other/docs/adr" ]
    [ -f "${TEST_TEMP_HOME}/other/docs/README.md" ]
}
