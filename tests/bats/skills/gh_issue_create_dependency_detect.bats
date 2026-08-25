#!/usr/bin/env bats
# tests/bats/skills/gh_issue_create_dependency_detect.bats
# Locks the Step 2.6 trigger-phrase matrix documented in
#   claude/skills/gh-issue-create/references/dependency-detect.md
# and the --no-auto-deps escape documented in
#   claude/skills/gh-issue-create/SKILL.md.
#
# Source-of-truth fixture: _fixtures/gh_issue_create_dependency_detect.sh.
# It mirrors the detection half (pure text -> issue numbers) and the Step
# 4.5 outcome classification (which id/mutation states raise the NF-1
# warning). The two `gh api graphql` calls themselves are out of scope —
# mocking `gh` would test the mock — so these tests stay network-free.

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

# ── F-1 (#1424 review): 완료/해결 conjugations beyond "완료 후" ──────
@test "deps: '#13 완료되면' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 완료되면 바로 시작하자" 0
    assert_success
    assert_output '13'
}

@test "deps: '#13 해결 후' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 해결 후에 재측정" 0
    assert_success
    assert_output '13'
}

@test "deps: '#13 완료하고' is a dependency trigger" {
    run gh_issue_create_detect_deps "#13 완료하고 넘어가자" 0
    assert_success
    assert_output '13'
}

@test "deps: '선행이슈 #13' matches without a colon" {
    run gh_issue_create_detect_deps "선행이슈 #13" 0
    assert_success
    assert_output '13'
}

@test "deps: a trigger word detached from the reference does not link" {
    # The 완료/해결 branch requires adjacency. Here '검토 후' belongs to a
    # different clause than '#13', so widening the pattern to '#N .* 후'
    # would produce exactly the false positive F-1 forbids.
    run gh_issue_create_detect_deps "#13 참고. 검토 후 진행하자" 0
    assert_success
    assert_output ''
}

# ── Pipefail safety (#1424 review) ───────────────────────────────────
@test "deps: no match under 'set -e -o pipefail' still returns cleanly" {
    # grep exits 1 on no-match; without the pipeline's `|| true` an errexit
    # caller would abort issue creation over "nothing to link".
    run bash -c "
        set -e -o pipefail
        source '${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_create_dependency_detect.sh'
        gh_issue_create_detect_deps '아무 의존성도 없는 대화' 0
        echo REACHED_END
    "
    assert_success
    assert_output 'REACHED_END'
}

# ── NF-1: Step 4.5 link-outcome classification (#1424 review) ────────
@test "link: both ids present and mutation ok → no warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 0 13
    assert_success
    assert_output ''
    [ -z "$stderr" ]
}

@test "link: null new-issue id → NF-1 warning, mutation never reached" {
    run --separate-stderr gh_issue_create_dep_link_outcome "" "I_dep" 0 13
    assert_success
    assert_output ''
    [[ "$stderr" == *"[WARN] Blocked by #13 링크 실패"* ]]
}

@test "link: null dep-issue id → NF-1 warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "" 0 13
    assert_success
    assert_output ''
    [[ "$stderr" == *"[WARN] Blocked by #13 링크 실패"* ]]
}

@test "link: rejected mutation → NF-1 warning naming that issue" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 20
    assert_success
    assert_output ''
    [[ "$stderr" == *"[WARN] Blocked by #20 링크 실패 — GH UI에서 수동 추가 필요"* ]]
}

# ── Drift guard: doc and fixture must share one reference regex ──────
@test "drift: the doc's reference regex is byte-identical to the fixture's" {
    # The SKILL prose is what actually runs; the fixture is what the tests
    # exercise. Without this guard, editing one and not the other leaves the
    # suite green while shipped behaviour diverges. Same pattern as
    # post_gh_pr_create_hook.bats T20.
    DOC="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-issue-create/references/dependency-detect.md"
    run grep -Fq "$_GH_DEPS_REF" "$DOC"
    assert_success
}
