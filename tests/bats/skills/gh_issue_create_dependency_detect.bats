#!/usr/bin/env bats
# tests/bats/skills/gh_issue_create_dependency_detect.bats
# Locks the Step 2.6 trigger-phrase matrix and the --no-auto-deps escape.
#
# Source-of-truth fixture: _fixtures/gh_issue_create_dependency_detect.sh.
# It mirrors the detection half (pure text -> issue numbers) and the Step
# 4.5 outcome classification (which id/mutation states raise the NF-1
# warning). The two `gh api graphql` calls are still not mocked — mocking
# `gh` would test the mock — so the fixture-backed tests stay network-free.
#
# #1680: gh-issue-create moved out to its own marketplace repo, so the
# two drift guards and the two #1457 addBlockedBy argument-shape guards
# (both the offline doc grep and the live-schema introspection that
# existed only to re-verify that doc's recorded shape) were dropped —
# they belong in that repo now. The fixture below is consequently no
# longer pinned to dependency-detect.md.

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
# $5 carries the stderr captured from whichever GraphQL call failed; why it
# is kept at all is argued in references/dependency-detect.md (#1458).
@test "link: both ids present and mutation ok → no warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 0 13 ""
    assert_success
    assert_output ''
    refute_stderr
}

@test "link: a successful link stays silent even when stderr was captured" {
    # Harmlessness (#1458): gh can chatter on stderr and still succeed. The
    # 원인 line rides on the NF-1 warning, so it must never appear alone.
    run --separate-stderr gh_issue_create_dep_link_outcome \
        "I_new" "I_dep" 0 13 "note: unrelated gh chatter"
    assert_success
    assert_output ''
    refute_stderr
}

@test "link: null new-issue id → NF-1 warning, mutation never reached" {
    run --separate-stderr gh_issue_create_dep_link_outcome "" "I_dep" 0 13 ""
    assert_success
    assert_output ''
    assert_stderr --partial '[WARN] Blocked by #13 링크 실패'
}

@test "link: null dep-issue id → NF-1 warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "" 0 13 ""
    assert_success
    assert_output ''
    assert_stderr --partial '[WARN] Blocked by #13 링크 실패'
}

@test "link: rejected mutation → NF-1 warning naming that issue" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 20 ""
    assert_success
    assert_output ''
    assert_stderr --partial '[WARN] Blocked by #20 링크 실패 — GH UI에서 수동 추가 필요'
}

@test "link: no captured cause → the warning carries no 원인 line" {
    # NF-1 is unchanged when there is nothing to add: a bare failure still
    # produces exactly the one line it always did.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 20 ""
    assert_success
    assert_output ''
    refute_stderr --partial '원인:'
}

@test "link: a non-existent dep number surfaces its GraphQL cause" {
    # The empty-id branch, which is what a rejected id lookup reduces to
    # here. That the lookup's stderr survives to become $5 is the drift
    # guard's job, not this one's — $5 arrives opaque either way.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "" 0 999 \
        "gh: Could not resolve to an Issue with the number of 999. (repository.depIssue)"
    assert_success
    assert_stderr --partial '[WARN] Blocked by #999 링크 실패'
    assert_stderr --partial '원인: gh: Could not resolve to an Issue with the number of 999.'
}

@test "link: an argument-schema mismatch surfaces verbatim (#1445 regression)" {
    # This exact sentence was on the wire during #1445 and was thrown away.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 13 \
        "gh: Argument 'blockingIssueId' on InputObject 'AddBlockedByInput' is required. Expected type ID!"
    assert_success
    assert_stderr --partial '원인: '
    assert_stderr --partial 'AddBlockedByInput'
}

@test "link: a multi-line cause is truncated to its first line" {
    # 확정 3: the full GraphQL error would swamp \$DEP_WARNINGS in the Step 5
    # report, and the first line already separates schema/permission/network.
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 13 \
        "$(printf 'first line matters\nsecond line must not appear\nthird')"
    assert_success
    assert_stderr --partial '원인: first line matters'
    refute_stderr --partial 'second line must not appear'
}

@test "link: the 원인 line is indented directly under its warning" {
    run --separate-stderr gh_issue_create_dep_link_outcome "I_new" "I_dep" 1 13 "boom"
    assert_success
    assert_stderr_line --index 0 --partial '수동 추가 필요'
    assert_stderr_line --index 1 '    원인: boom'
}

@test "link: one failing sibling does not disturb the other's success" {
    # Per-N isolation (#1458 verification): #13 fails with a cause, #20 links.
    # setup() already sourced the fixture, so this runs in-process — no
    # second copy of the fixture path to keep in sync.
    _two_deps() {
        gh_issue_create_dep_link_outcome 'I_new' '' 0 13 \
            'gh: Could not resolve to an Issue with the number of 13.'
        gh_issue_create_dep_link_outcome 'I_new' 'I_dep' 0 20 ''
    }
    run --separate-stderr _two_deps
    assert_success
    assert_stderr --partial 'Blocked by #13 링크 실패'
    assert_stderr --partial '원인: gh: Could not resolve'
    refute_stderr --partial '#20'
}
