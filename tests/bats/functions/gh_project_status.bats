#!/usr/bin/env bats
# tests/bats/functions/gh_project_status.bats
# Unit tests for the shared _gh_project_status_sync helper extracted from
# gh_flow.sh. Network-dependent paths (the actual GraphQL query + mutation)
# are not exercised — fixturing live projectV2 state is impractical. We
# cover loading, opt-out guards, arg validation, --only-from option
# parsing, and the _gh_project_status_in_list membership helper.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Loading: helper available in both bash and zsh after main.* sources it
# ---------------------------------------------------------------------------

@test "bash: _gh_project_status_sync helper exists" {
    run_in_bash 'declare -f _gh_project_status_sync >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_project_status_sync helper exists" {
    run_in_zsh 'typeset -f _gh_project_status_sync >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_project_status_in_list helper exists" {
    run_in_bash 'declare -f _gh_project_status_in_list >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Opt-out guards
# ---------------------------------------------------------------------------

@test "opt-out: GH_PROJECT_STATUS_SYNC=0 returns silently" {
    run_in_bash 'GH_PROJECT_STATUS_SYNC=0 _gh_project_status_sync issue 1 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "[gh-project-status]"
}

@test "opt-out: legacy GH_FLOW_PROJECT_STATUS_SYNC=0 still honored" {
    # Backwards-compat: callers that exported the old name in their env or
    # CI config keep working without churn.
    run_in_bash 'GH_FLOW_PROJECT_STATUS_SYNC=0 _gh_project_status_sync issue 1 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "[gh-project-status]"
}

# ---------------------------------------------------------------------------
# Arg validation (early returns, no network)
# ---------------------------------------------------------------------------

@test "validation: missing args returns silently" {
    run_in_bash '_gh_project_status_sync 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    refute_output --partial "[gh-project-status]"
}

@test "validation: invalid kind returns 0 with warning" {
    run_in_bash '_gh_project_status_sync bogus 42 "In progress" 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "invalid kind=bogus"
}

# ---------------------------------------------------------------------------
# --only-from option parsing
# ---------------------------------------------------------------------------

@test "only-from: unknown option rejected with stderr warning" {
    run_in_bash '_gh_project_status_sync issue 42 "In progress" --bogus 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "unknown option: --bogus"
}

@test "only-from: missing value rejected" {
    run_in_bash '_gh_project_status_sync issue 42 "In progress" --only-from 2>&1; echo "rc=$?"'
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "--only-from requires an argument"
}

# ---------------------------------------------------------------------------
# _gh_project_status_in_list membership semantics
# ---------------------------------------------------------------------------

@test "in_list: single-item match" {
    run_in_bash '_gh_project_status_in_list "Backlog" "Backlog" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

@test "in_list: comma-separated match (first)" {
    run_in_bash '_gh_project_status_in_list "Backlog" "Backlog,In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

@test "in_list: comma-separated match (last)" {
    run_in_bash '_gh_project_status_in_list "In progress" "Backlog,In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}

@test "in_list: no match returns 1" {
    run_in_bash '_gh_project_status_in_list "In review" "Backlog,In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "NO"
}

@test "in_list: empty current value never matches" {
    # Important guard: items with no Status set should not satisfy
    # --only-from "" or any non-empty whitelist.
    run_in_bash '_gh_project_status_in_list "" "Backlog" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "NO"
}

@test "in_list: status names with internal spaces are preserved" {
    # Regression: a naive trim or word-split would break "In progress".
    run_in_bash '_gh_project_status_in_list "In progress" "In progress" && echo MATCH || echo NO'
    assert_success
    assert_output --partial "MATCH"
}
