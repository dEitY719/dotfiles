#!/usr/bin/env bats
# tests/bats/skills/gh_issue_create_auto_labels.bats
# Locks the seven-row compatibility matrix documented in
#   claude/skills/gh-issue-create/references/auto-labels.md
# and the Step 2.5 dispatch flow in
#   claude/skills/gh-issue-create/SKILL.md.
#
# Source-of-truth fixture: _fixtures/gh_issue_create_auto_labels.sh.
# It loads the real awk parser shipped at
# shell-common/functions/parse_yaml_defaults.sh and exposes a single
# helper — gh_issue_create_compose_labels — that mirrors the SKILL
# dispatch order so these tests catch drift between the prose and the
# implementation.

bats_require_minimum_version 1.5.0

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_create_auto_labels.sh"

    # The dotfiles SSOT under test (committed alongside this suite).
    DOTFILES_YML="${_BATS_REAL_DOTFILES_ROOT}/.gh-issue-defaults.yml"
    # Mock of `gh label list --jq '.[].name'` for the dotfiles repo.
    DOTFILES_EXISTING="bug,documentation,enhancement,feat,refactor,test,ci,skill"
}

teardown() {
    teardown_isolated_home
}

# ── Row 1 ────────────────────────────────────────────────────────────
@test "auto-labels: dotfiles 'feat: ...' → --label feat" {
    run gh_issue_create_compose_labels \
        "$DOTFILES_YML" feat "" "$DOTFILES_EXISTING" 0
    assert_success
    assert_output 'feat'
}

# ── Row 2 ────────────────────────────────────────────────────────────
@test "auto-labels: dotfiles 'chore: ...' → empty (chore=[])" {
    run gh_issue_create_compose_labels \
        "$DOTFILES_YML" chore "" "$DOTFILES_EXISTING" 0
    assert_success
    assert_output ''
}

# ── Row 3 ────────────────────────────────────────────────────────────
@test "auto-labels: feat + user '--label skill' → union (feat, skill)" {
    run gh_issue_create_compose_labels \
        "$DOTFILES_YML" feat "skill" "$DOTFILES_EXISTING" 0
    assert_success
    assert_line --index 0 'feat'
    assert_line --index 1 'skill'
    [ "${#lines[@]}" -eq 2 ]
}

# ── Row 4 ────────────────────────────────────────────────────────────
@test "auto-labels: AgentToolbox-style static + prefix → both applied" {
    YML="$(mktemp)"
    cat >"$YML" <<'YAML'
default_labels:
  static: [pro-friendly, phase:1]
  by_title_prefix:
    feat: [feat]
milestone: auto
YAML
    EXISTING="pro-friendly,phase:1,feat,bug"

    run gh_issue_create_compose_labels "$YML" feat "" "$EXISTING" 0
    rm -f "$YML"

    assert_success
    assert_line --index 0 'pro-friendly'
    assert_line --index 1 'phase:1'
    assert_line --index 2 'feat'
    [ "${#lines[@]}" -eq 3 ]
}

# ── Row 5 ────────────────────────────────────────────────────────────
@test "auto-labels: generic repo (no SSOT) → no auto labels" {
    run gh_issue_create_compose_labels "" feat "" "$DOTFILES_EXISTING" 0
    assert_success
    assert_output ''
}

# ── Row 6 ────────────────────────────────────────────────────────────
@test "auto-labels: --no-auto-labels honours user labels only" {
    run gh_issue_create_compose_labels \
        "$DOTFILES_YML" feat "skill" "$DOTFILES_EXISTING" 1
    assert_success
    assert_output 'skill'
}

# ── Row 7 ────────────────────────────────────────────────────────────
@test "auto-labels: missing target label → warn skip + keep others" {
    # 'documentation' is the prefix-mapped label for docs; user added
    # 'skill'; the mocked repo is missing 'documentation'.
    EXISTING_NO_DOCS="bug,enhancement,feat,refactor,test,ci,skill"

    # Use --separate-stderr so we can assert stdout (kept labels) and
    # stderr (warning) independently.
    run --separate-stderr gh_issue_create_compose_labels \
        "$DOTFILES_YML" docs "skill" "$EXISTING_NO_DOCS" 0
    assert_success
    # 'documentation' got dropped; 'skill' (user) survives on stdout.
    assert_output 'skill'
    # The drop surfaces on stderr.
    [[ "$stderr" == *"auto-labels: label 'documentation' not found"* ]]
    [[ "$stderr" != *"label 'skill' not found"* ]]
}
