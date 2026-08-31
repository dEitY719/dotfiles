#!/usr/bin/env bats
# tests/bats/functions/devx_pr_review_all_source_path.bats
# Issue #1612 — sourcing devx_pr_review_all.sh from a clean, non-interactive
# shell (no dotfiles rc, no $SHELL_COMMON — the exact shape of Claude Code's
# own Bash tool) must define every public function, whether the caller
# sources the file by a relative or an absolute path. #1612 found several
# skill docs telling agents to source it via a bare `${SHELL_COMMON}/...`
# with no `$HOME` fallback; when that expands empty, an agent can fall back
# to a relative-path `source` instead — this test pins that both paths work
# so a future regression in the guard chain (dotfiles_root.sh) is caught
# here instead of silently dropping `review-passed`/`review-blocked` labels
# again.

load '../test_helper'

FUNCS="devx_pr_review_all_parse devx_pr_review_all_verdict devx_pr_review_all_aggregate devx_pr_review_all_lane_block devx_pr_review_all_already_reviewed devx_pr_review_all_apply_label"

setup() {
    setup_isolated_home
    ln -s "$_BATS_REAL_DOTFILES_ROOT" "$HOME/dotfiles"
}

teardown() {
    teardown_isolated_home
}

# A truly clean, non-interactive shell: no inherited $SHELL_COMMON/$DOTFILES_ROOT,
# no rc files — matching the environment #1612 traces the failure to.
run_clean_source() {
    local src_expr="$1"
    env -i HOME="$HOME" bash --noprofile --norc -c "
        cd '${_BATS_REAL_DOTFILES_ROOT}' || exit 99
        source ${src_expr} || exit 98
        for f in ${FUNCS}; do
            declare -f \"\$f\" >/dev/null 2>&1 || { echo \"MISSING:\$f\"; exit 1; }
        done
        echo ALL_DEFINED
    "
}

@test "relative-path source defines every public function in a clean shell" {
    run run_clean_source "shell-common/functions/devx_pr_review_all.sh"
    assert_success
    assert_output --partial "ALL_DEFINED"
}

@test "absolute-path source defines every public function in a clean shell (positive control)" {
    run run_clean_source "\"${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_review_all.sh\""
    assert_success
    assert_output --partial "ALL_DEFINED"
}

@test "\${SHELL_COMMON:-\$HOME/dotfiles/shell-common} fallback idiom defines every public function when SHELL_COMMON is unset" {
    run run_clean_source '"${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh"'
    assert_success
    assert_output --partial "ALL_DEFINED"
}
