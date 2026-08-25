#!/usr/bin/env bats
# tests/bats/skills/gh_issue_create_dependency_detect.bats
# Locks the Step 2.6 trigger-phrase matrix documented in
#   claude/skills/gh-issue-create/references/dependency-detect.md
# and the --no-auto-deps escape documented in
#   claude/skills/gh-issue-create/SKILL.md.
#
# Source-of-truth fixture: _fixtures/gh_issue_create_dependency_detect.sh.
# It mirrors the detection half of the step (pure text -> issue numbers);
# the GraphQL half (Step 4.5 addBlockedBy) is out of scope here — the
# fixture never calls `gh`, so these tests stay network-free.

bats_require_minimum_version 1.5.0

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh"
}

teardown() {
    teardown_isolated_home
}

# ── Korean trailing triggers ─────────────────────────────────────────
@test "deps: '#13 완료 후' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 완료 후에 진행하자" 0
    assert_success
    assert_output '13'
}

@test "deps: '#13 이후에' is a dependency trigger" {
    run gh_issue_create_detect_deps "이 작업은 #13 이후에 하면 된다" 0
    assert_success
    assert_output '13'
}

@test "deps: '선행 이슈: #13' is a dependency trigger" {
    run gh_issue_create_detect_deps "선행 이슈: #13" 0
    assert_success
    assert_output '13'
}

# ── English leading triggers ─────────────────────────────────────────
@test "deps: 'depends on #13' is a dependency trigger (case-insensitive)" {
    run gh_issue_create_detect_deps "This DEPENDS ON #13 landing first" 0
    assert_success
    assert_output '13'
}

@test "deps: 'blocked by #13' is a dependency trigger" {
    run gh_issue_create_detect_deps "blocked by #13" 0
    assert_success
    assert_output '13'
}

# ── Negative: plain mentions must NOT link (F-1 오탐 방지) ───────────
@test "deps: '#13 참고' is a plain mention, not a dependency" {
    run gh_issue_create_detect_deps "#13 참고해서 작업" 0
    assert_success
    assert_output ''
}

@test "deps: '#13 관련' is a plain mention, not a dependency" {
    run gh_issue_create_detect_deps "#13 관련 내용은 아래 참조" 0
    assert_success
    assert_output ''
}

@test "deps: a bare '#13' with no trigger phrase is not a dependency" {
    run gh_issue_create_detect_deps "see #13 for context" 0
    assert_success
    assert_output ''
}

# ── Multiple + de-dup ────────────────────────────────────────────────
@test "deps: multiple triggers yield ascending, de-duped numbers" {
    run gh_issue_create_detect_deps \
        "#20 완료 후에 진행. blocked by #13. 그리고 #13 이후에 재확인." 0
    assert_success
    assert_line --index 0 '13'
    assert_line --index 1 '20'
    [ "${#lines[@]}" -eq 2 ]
}

# ── NF-2: cross-repo is out of v1 scope ──────────────────────────────
@test "deps: cross-repo 'owner/repo#13' warns and is skipped" {
    run --separate-stderr gh_issue_create_detect_deps \
        "depends on dEitY719/other-repo#13" 0
    assert_success
    assert_output ''
    assert_stderr --partial "cross-repo dependency detected but not supported in v1"
}

@test "deps: cross-repo skip does not drop a same-repo sibling" {
    run --separate-stderr gh_issue_create_detect_deps \
        "depends on dEitY719/other-repo#99 and blocked by #13" 0
    assert_success
    assert_output '13'
    assert_stderr --partial "cross-repo dependency detected but not supported in v1"
}

# ── F-3: --no-auto-deps escape ───────────────────────────────────────
@test "deps: --no-auto-deps skips detection entirely" {
    run gh_issue_create_detect_deps "#13 완료 후에 진행하자" 1
    assert_success
    assert_output ''
}
