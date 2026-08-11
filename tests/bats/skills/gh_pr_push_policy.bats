#!/usr/bin/env bats
# tests/bats/skills/gh_pr_push_policy.bats
# Verify the Step 1b branch-state logic documented in
#   claude/skills/gh-pr/references/branch-state.md
#   claude/skills/gh-pr/references/push-and-create.md  (policy table)
# Source-of-truth fixture: _fixtures/gh_pr_push_policy.sh.
#
# Issue #1315 verification checklist:
#   F-1-1  no upstream                        → push -u origin HEAD
#   F-1-2  upstream == origin/<current>       → bare push
#   F-1-3  upstream == origin/main, on feature → push -u origin HEAD (NOT bare)
#   F-1-4  upstream diverged                  → STOP (pre-existing row)
#   F-2-1  on base + local-only commits       → auto-branch + rewind
#   F-2-2  on base + commits already on origin → stop as before
#   F-2-3  Korean commit titles               → ASCII-safe branch names

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_push_policy.sh"
}

teardown() {
    teardown_isolated_home
}

# ── F-1-0: upstream ref normalisation ─────────────────────────────────
@test "normalize: refs/remotes/origin/main → origin/main" {
    run gh_pr_normalize_upstream 'refs/remotes/origin/main'
    assert_success
    assert_output 'origin/main'
}

@test "normalize: already-abbreviated origin/main passes through" {
    run gh_pr_normalize_upstream 'origin/main'
    assert_success
    assert_output 'origin/main'
}

@test "normalize: empty upstream stays empty" {
    run gh_pr_normalize_upstream ''
    assert_success
    [ -z "$output" ]
}

# ── F-1-1: no upstream ────────────────────────────────────────────────
@test "F-1-1: no upstream → push -u origin HEAD" {
    run gh_pr_push_action 'feat/issue-1315' '' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-1: no upstream is NOT reported as a mispair" {
    run gh_pr_upstream_is_mispaired '' 'feat/issue-1315'
    [ "$status" -eq 1 ]
}

# ── F-1-2: correctly paired upstream ──────────────────────────────────
@test "F-1-2: upstream == origin/<current> → bare push" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/feat/issue-1315' ''
    assert_success
    assert_output 'push'
}

@test "F-1-2: full symbolic ref form also pairs cleanly → bare push" {
    run gh_pr_push_action 'feat/issue-1315' \
        'refs/remotes/origin/feat/issue-1315' ''
    assert_success
    assert_output 'push'
}

@test "F-1-2: matched pairing is not a mispair (rc=1)" {
    run gh_pr_upstream_is_mispaired 'origin/feat/issue-1315' 'feat/issue-1315'
    [ "$status" -eq 1 ]
}

# ── F-1-3: mispaired upstream (the #1315 bug) ─────────────────────────
@test "F-1-3: upstream origin/main on a feature branch → mispair detected" {
    run gh_pr_upstream_is_mispaired 'origin/main' 'feat/issue-1315'
    assert_success
}

@test "F-1-3: upstream origin/main on a feature branch → push -u origin HEAD" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/main' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-3: mispaired state must NOT prescribe a bare push" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/main' ''
    assert_success
    refute_output 'push'
    refute_output --partial 'STOP'
}

@test "F-1-3: worktree-created branch tracking refs/remotes/origin/main → push -u" {
    # git worktree add -b <branch> off origin/main leaves this exact state.
    run gh_pr_push_action 'wt/issue-1315/1' 'refs/remotes/origin/main' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-3: mispair wins over a bogus 'diverged' verdict" {
    # While mispaired, ahead/behind is computed against base, so the
    # divergence signal is unreliable — re-pairing must take precedence.
    run gh_pr_push_action 'feat/issue-1315' 'origin/main' 'diverged'
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-3: intentionally differently-named tracking branch → push -u (accepted trade-off)" {
    run gh_pr_push_action 'fix' 'origin/hotfix-2026-08' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

# ── F-1-4: diverged upstream (regression guard, pre-existing row) ──────
@test "F-1-4: paired upstream diverged → STOP" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/feat/issue-1315' 'diverged'
    assert_success
    assert_output 'STOP'
}

@test "F-1-4: paired upstream diverged (full ref form) → STOP" {
    run gh_pr_push_action 'feat/issue-1315' \
        'refs/remotes/origin/feat/issue-1315' 'diverged'
    assert_success
    assert_output 'STOP'
}

# ── F-2-0: not on the base branch → untouched normal path ─────────────
@test "F-2-0: on a feature branch → not-on-base" {
    run gh_pr_base_branch_decision 'feat/issue-1315' 'main' 'aaa111' 'aaa111' ''
    assert_success
    assert_output 'not-on-base'
}

@test "F-2-0: base branch may be a parent PR head ref (stacked PR)" {
    run gh_pr_base_branch_decision 'feat/child' 'feat/parent' '' '' ''
    assert_success
    assert_output 'not-on-base'
}

# ── F-2-1: on base with local-only commits → auto-branch + rewind ─────
@test "F-2-1: on base, local-only commits not on origin → auto-branch-and-rewind" {
    run gh_pr_base_branch_decision 'main' 'main' \
        $'aaa111\nbbb222' $'aaa111\nbbb222' $'ccc333\nddd444'
    assert_success
    assert_output 'auto-branch-and-rewind'
}

@test "F-2-1: set comparison is order-insensitive" {
    run gh_pr_base_branch_decision 'main' 'main' \
        $'bbb222\naaa111' $'aaa111\nbbb222' 'ccc333'
    assert_success
    assert_output 'auto-branch-and-rewind'
}

@test "F-2-1: straggler left on base (sets differ) → warn only, no rewind" {
    run gh_pr_base_branch_decision 'main' 'main' \
        $'aaa111\nbbb222' 'aaa111' 'ccc333'
    assert_success
    assert_output 'auto-branch-warn-only'
}

@test "F-2-1: empty local-only range → nothing-to-pr (dirty tree is out of scope)" {
    run gh_pr_base_branch_decision 'main' 'main' '' '' 'ccc333'
    assert_success
    assert_output 'nothing-to-pr'
}

# ── F-2-2: commits already pushed to origin/<base> → stop as before ───
@test "F-2-2: moved commits already on origin/<base> → stop-already-pushed" {
    run gh_pr_base_branch_decision 'main' 'main' \
        $'aaa111\nbbb222' $'aaa111\nbbb222' $'aaa111\nccc333'
    assert_success
    assert_output 'stop-already-pushed'
    refute_output --partial 'rewind'
}

@test "F-2-2: stop-already-pushed never prescribes an auto-branch" {
    run gh_pr_base_branch_decision 'main' 'main' \
        'aaa111' 'aaa111' 'aaa111'
    assert_success
    refute_output --partial 'auto-branch'
}

# ── F-2-3: branch-name generator, Korean titles ───────────────────────
@test "F-2-3: Korean feat title → type parsed from the ASCII prefix" {
    run gh_pr_commit_type 'feat(devx): 머지된 PR 을 재검증하는 스킬 신설'
    assert_success
    assert_output 'feat'
}

@test "F-2-3: Korean fix title without scope → fix" {
    run gh_pr_commit_type 'fix: 리뷰 반영 및 변수명 오타 수정'
    assert_success
    assert_output 'fix'
}

@test "F-2-3: breaking-change marker still parses the type" {
    run gh_pr_commit_type 'refactor(shell-common)!: 인터페이스 정리'
    assert_success
    assert_output 'refactor'
}

@test "F-2-3: title with no conventional prefix (pure Korean) → chore" {
    run gh_pr_commit_type '한글로만 작성된 커밋 제목'
    assert_success
    assert_output 'chore'
}

@test "F-2-3: unknown ASCII prefix → chore" {
    run gh_pr_commit_type 'wibble: something'
    assert_success
    assert_output 'chore'
}

@test "F-2-3: Korean title + issue number → <type>/issue-<N>" {
    local _type
    _type=$(gh_pr_commit_type 'feat(devx): 머지된 PR 을 재검증하는 스킬 신설')
    run gh_pr_branch_name "$_type" '1315' '20260811' 'bf5b868'
    assert_success
    assert_output 'feat/issue-1315'
}

@test "F-2-3: Korean title without issue number → <type>/<YYYYMMDD>-<short-sha>" {
    local _type
    _type=$(gh_pr_commit_type 'fix: 리뷰 반영 및 변수명 오타 수정')
    run gh_pr_branch_name "$_type" '' '20260811' 'bf5b868'
    assert_success
    assert_output 'fix/20260811-bf5b868'
}

@test "F-2-3: generated branch names are pure ASCII" {
    local _name
    _name=$(gh_pr_branch_name \
        "$(gh_pr_commit_type 'feat(devx): 한글 제목 그대로')" '' '20260811' 'abc1234')
    printf '%s' "$_name" | LC_ALL=C grep -qE '^[A-Za-z0-9/_.-]+$'
}

@test "F-2-3: generator is deterministic (same inputs → same name)" {
    local _a _b
    _a=$(gh_pr_branch_name feat '' '20260811' 'abc1234')
    _b=$(gh_pr_branch_name feat '' '20260811' 'abc1234')
    [ "$_a" = "$_b" ]
    [ "$_a" = 'feat/20260811-abc1234' ]
}

@test "F-2-3: non-numeric issue value falls back to the date form" {
    run gh_pr_branch_name feat 'not-a-number' '20260811' 'abc1234'
    assert_success
    assert_output 'feat/20260811-abc1234'
}

@test "F-2-3: unknown type passed directly to the generator → chore" {
    run gh_pr_branch_name 'bogus' '1315' '20260811' 'abc1234'
    assert_success
    assert_output 'chore/issue-1315'
}
